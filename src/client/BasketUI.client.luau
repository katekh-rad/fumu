--[[
	BasketUI.client.luau

	Окно корзины по клавише B. Целиком строится кодом — никаких
	заранее собранных GUI в Studio, чтобы весь интерфейс лежал в git.

	Клиент здесь только ОТОБРАЖАЕТ то, что прислал сервер, и шлёт
	намерения. Съедобность неоткрытых видов и нерассмотренная порча
	сюда вообще не приходят.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local getBasketState = ReplicatedStorage:WaitForChild("GetBasketState") :: RemoteFunction
local discardMushroom = ReplicatedStorage:WaitForChild("DiscardMushroom") :: RemoteEvent
local confirmBasket = ReplicatedStorage:WaitForChild("ConfirmBasket") :: RemoteEvent
local useToolOnSlot = ReplicatedStorage:WaitForChild("UseToolOnSlot") :: RemoteEvent
local markMushroom = ReplicatedStorage:WaitForChild("MarkMushroom") :: RemoteEvent
local buyItem = ReplicatedStorage:WaitForChild("BuyItem") :: RemoteEvent
local purchaseResult = ReplicatedStorage:WaitForChild("PurchaseResult") :: RemoteEvent

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Tools = require(ReplicatedStorage.Shared.Tools)
local Baskets = require(ReplicatedStorage.Shared.Baskets)
local basketUpdated = ReplicatedStorage:WaitForChild("BasketUpdated") :: RemoteEvent
local confirmResult = ReplicatedStorage:WaitForChild("BasketConfirmResult") :: RemoteEvent

local COLORS = {
	background = Color3.fromRGB(32, 28, 24),
	panel = Color3.fromRGB(46, 40, 34),
	row = Color3.fromRGB(58, 51, 43),
	rowHover = Color3.fromRGB(72, 63, 53),
	text = Color3.fromRGB(240, 235, 225),
	textDim = Color3.fromRGB(160, 150, 138),
	edible = Color3.fromRGB(120, 210, 110), -- зелёный
	poison = Color3.fromRGB(225, 95, 85), -- красный
	accent = Color3.fromRGB(200, 165, 90),
	accentDim = Color3.fromRGB(96, 84, 62), -- неактивная кнопка
	stem = Color3.fromRGB(235, 220, 195), -- ножка, как в 3D-модели
	moldLight = Color3.fromRGB(215, 225, 200), -- пятна плесени
	moldDark = Color3.fromRGB(125, 150, 105),
	moldHalo = Color3.fromRGB(150, 170, 135), -- пушистый ореол плесени
	wormHole = Color3.fromRGB(45, 32, 24), -- ходы червей
	wormEdge = Color3.fromRGB(150, 105, 60), -- изъеденный край хода
	lensGlass = Color3.fromRGB(170, 205, 225), -- стекло лупы
	lensHandle = Color3.fromRGB(110, 72, 40), -- ручка лупы
	basketBody = Color3.fromRGB(176, 124, 64), -- плетёная корзина
	basketWeave = Color3.fromRGB(128, 86, 40),
}

-- Цвет оправы лупы по уровню: так лупы различаются без надписей.
local LENS_RIM = {
	Color3.fromRGB(176, 120, 70), -- x5: бронза
	Color3.fromRGB(200, 205, 215), -- x10: серебро
	Color3.fromRGB(240, 195, 60), -- x20: золото
}

-- Насколько близко к большой корзине надо стоять. Держим в одном значении с
-- сервером (BasketService.STATION_RANGE) — клиент только подсказывает,
-- решает всё равно сервер.
local STATION_RANGE = 18

local isOpen = false
local latestState = nil
local detailInstanceId: string? = nil
local activeTab = "basket" -- "basket" | "shop"

-- === Пиктограмма гриба ===

-- Где на шляпке могут быть следы порчи (доли размера шляпки, только
-- видимая верхняя часть). Какие из них заняты — зависит от конкретного
-- гриба (см. spotSeed), так что игрок не знает заранее, куда смотреть.
local DEFECT_SPOTS = {
	{ 0.30, 0.28 },
	{ 0.64, 0.20 },
	{ 0.48, 0.45 },
	{ 0.78, 0.40 },
	{ 0.20, 0.50 },
	{ 0.45, 0.14 },
	{ 0.62, 0.52 },
	{ 0.36, 0.40 },
}

-- Что видно под лупой каждого уровня: одна и та же порча под сильной
-- лупой выглядит подробнее.
--   count     — сколько точек на шляпке
--   scale     — диаметр точки как доля размера иконки
--   stemHoles — сколько червоточин видно на ножке
local DEFECT_VIEW = {
	{ count = 1, scale = 0.04, stemHoles = 0 }, -- x5: одна крошечная точка
	{ count = 3, scale = 0.045, stemHoles = 1 }, -- x10: несколько точек
	{ count = 5, scale = 0.055, stemHoles = 2 }, -- x20: много точек
}

-- Стабильное число из instanceId: у одного и того же гриба точки
-- всегда на тех же местах, у разных грибов — на разных.
local function spotSeed(instanceId: string): number
	local sum = 0
	for i = 1, #instanceId do
		sum += string.byte(instanceId, i) * i
	end
	return sum
end

local function addSpot(
	parent: GuiObject,
	x: number,
	y: number,
	diameter: number,
	color: Color3,
	transparency: number?
)
	local spot = Instance.new("Frame")
	spot.BackgroundTransparency = transparency or 0
	spot.Size = UDim2.new(0, diameter, 0, diameter)
	spot.Position = UDim2.new(x, 0, y, 0)
	spot.AnchorPoint = Vector2.new(0.5, 0.5)
	spot.BackgroundColor3 = color
	spot.BorderSizePixel = 0
	spot.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = spot
end

-- Рисует гриб: скруглённая шляпка нужного цвета + светлая ножка.
-- Цвет шляпки совпадает с цветом 3D-модели, так что иконка в списке и
-- крупный вид — это одно и то же изображение в разном масштабе.
-- defect передаётся только для увеличенного вида и только когда порчу
-- разглядели лупой. viewLevel — уровень лупы, которой смотрели.
local function makeMushroomIcon(
	color: Color3,
	size: number,
	defect: string?,
	viewLevel: number?,
	seed: number?
): Frame
	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(0, size, 0, size)
	holder.BackgroundTransparency = 1

	-- Ножка: узкий прямоугольник в нижней части
	local stem = Instance.new("Frame")
	stem.Size = UDim2.new(0, size * 0.26, 0, size * 0.45)
	stem.Position = UDim2.new(0.5, 0, 1, 0)
	stem.AnchorPoint = Vector2.new(0.5, 1)
	stem.BackgroundColor3 = COLORS.stem
	stem.BorderSizePixel = 0
	stem.Parent = holder

	local stemCorner = Instance.new("UICorner")
	stemCorner.CornerRadius = UDim.new(0, math.max(2, size * 0.06))
	stemCorner.Parent = stem

	-- Шляпка: круг, у которого видна только верхняя половина.
	-- UICorner скругляет все углы сразу, поэтому берём полный круг и
	-- обрезаем низ через ClipsDescendants на контейнере.
	local capClip = Instance.new("Frame")
	capClip.Size = UDim2.new(0, size * 0.92, 0, size * 0.5)
	capClip.Position = UDim2.new(0.5, 0, 0, size * 0.08)
	capClip.AnchorPoint = Vector2.new(0.5, 0)
	capClip.BackgroundTransparency = 1
	capClip.ClipsDescendants = true
	capClip.Parent = holder

	local cap = Instance.new("Frame")
	cap.Size = UDim2.new(0, size * 0.92, 0, size * 0.8)
	cap.Position = UDim2.new(0.5, 0, 0, 0)
	cap.AnchorPoint = Vector2.new(0.5, 0)
	cap.BackgroundColor3 = color
	cap.BorderSizePixel = 0
	cap.Parent = capClip

	local capCorner = Instance.new("UICorner")
	capCorner.CornerRadius = UDim.new(1, 0)
	capCorner.Parent = cap

	local view = viewLevel and DEFECT_VIEW[viewLevel]
	if defect and view then
		-- Подсказок нет: игрок должен сам заметить точку. Поэтому у
		-- каждой точки контрастный край — иначе на 4 px её не разглядеть.
		local diameter = math.max(3, math.floor(size * view.scale))
		local start = (seed or 0) % #DEFECT_SPOTS
		for i = 1, view.count do
			-- шаг 3 при 8 позициях обходит все места вразброс
			local point = DEFECT_SPOTS[(start + (i - 1) * 3) % #DEFECT_SPOTS + 1]
			if defect == "mold" then
				-- мягкий ореол, чтобы не путать с белыми пятнами мухомора
				local moldColor = if i % 2 == 0 then COLORS.moldDark else COLORS.moldLight
				addSpot(cap, point[1], point[2], math.floor(diameter * 1.7), COLORS.moldHalo, 0.55)
				addSpot(cap, point[1], point[2], diameter, moldColor)
			else
				-- тёмная дырка со светлым изъеденным краем
				addSpot(cap, point[1], point[2], diameter + math.max(2, math.floor(diameter * 0.6)), COLORS.wormEdge)
				addSpot(cap, point[1], point[2], diameter, COLORS.wormHole)
			end
		end
		if defect == "worms" then
			-- червоточины на ножке видны только под лупой посильнее
			local stemPoints = { { 0.4, 0.35 }, { 0.6, 0.7 } }
			for i = 1, view.stemHoles do
				local d = math.max(2, math.floor(diameter * 0.8))
				local point = stemPoints[i]
				addSpot(stem, point[1], point[2], d + math.max(2, math.floor(d * 0.6)), COLORS.wormEdge)
				addSpot(stem, point[1], point[2], d, COLORS.wormHole)
			end
		end
	end

	return holder
end

-- Ставит ZIndex всему рисунку сразу (оверлеи лежат на уровне 11)
local function setZIndex(root: GuiObject, zIndex: number)
	root.ZIndex = zIndex
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = zIndex
		end
	end
end

local function roundCorners(target: GuiObject, radius: UDim)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = target
end

-- === Галочка, крестик и стрелка из полосок ===
--
-- Рисуем их фигурами, а не символами ✓ ✗ ← : этих символов нет в шрифте
-- Gotham, и вместо них система подставляет пустой прямоугольник цвета
-- текста. Именно поэтому кнопка «не беру» выглядела красным
-- прямоугольником, а не крестиком.

local function makeBar(
	parent: GuiObject,
	width: number,
	thickness: number,
	offsetX: number,
	offsetY: number,
	angle: number,
	color: Color3
): Frame
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.new(0.5, offsetX, 0.5, offsetY)
	bar.Size = UDim2.fromOffset(math.max(1, width), math.max(1, thickness))
	bar.Rotation = angle
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar.Parent = parent
	roundCorners(bar, UDim.new(1, 0))
	return bar
end

local function clearShape(parent: GuiObject)
	for _, child in parent:GetChildren() do
		if child.Name == "Bar" then
			child:Destroy()
		end
	end
end

-- Крестик: две полоски накрест
local function drawCross(parent: GuiObject, size: number, thickness: number, color: Color3)
	clearShape(parent)
	makeBar(parent, size, thickness, 0, 0, 45, color)
	makeBar(parent, size, thickness, 0, 0, -45, color)
end

-- Галочка: короткая полоска вниз-вправо и длинная вверх-вправо
local function drawCheck(parent: GuiObject, size: number, thickness: number, color: Color3)
	clearShape(parent)
	makeBar(parent, size * 0.42, thickness, -size * 0.2, size * 0.1, 45, color)
	makeBar(parent, size * 0.64, thickness, size * 0.175, size * 0.025, -45, color)
end

-- Стрелка влево: полоска и два уса на левом конце
local function drawBackArrow(parent: GuiObject, size: number, thickness: number, color: Color3)
	clearShape(parent)
	makeBar(parent, size, thickness, 0, 0, 0, color)
	makeBar(parent, size * 0.42, thickness, -size * 0.35, -size * 0.15, -45, color)
	makeBar(parent, size * 0.42, thickness, -size * 0.35, size * 0.15, 45, color)
end

-- Пиктограмма лупы: круглое стекло в цветной оправе + ручка.
-- Уровень лупы виден по цвету оправы и по точкам (1-3) внизу слева.
local function makeMagnifierIcon(level: number, size: number, showDots: boolean?): Frame
	local rimColor = LENS_RIM[level] or LENS_RIM[1]

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(0, size, 0, size)
	holder.BackgroundTransparency = 1

	-- Ручка: вертикальная планка, повёрнутая на 45° ("\")
	local handle = Instance.new("Frame")
	handle.Size = UDim2.new(0, math.max(3, size * 0.16), 0, size * 0.44)
	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	handle.Position = UDim2.new(0, size * 0.72, 0, size * 0.72)
	handle.Rotation = -45
	handle.BackgroundColor3 = COLORS.lensHandle
	handle.BorderSizePixel = 0
	handle.Parent = holder
	roundCorners(handle, UDim.new(0, math.max(2, size * 0.06)))

	-- Стекло
	local lens = Instance.new("Frame")
	lens.Size = UDim2.new(0, size * 0.6, 0, size * 0.6)
	lens.Position = UDim2.new(0, size * 0.06, 0, size * 0.06)
	lens.BackgroundColor3 = COLORS.lensGlass
	lens.BackgroundTransparency = 0.35
	lens.BorderSizePixel = 0
	lens.Parent = holder
	roundCorners(lens, UDim.new(1, 0))

	local rim = Instance.new("UIStroke")
	rim.Thickness = math.max(2, math.floor(size * 0.07))
	rim.Color = rimColor
	rim.Parent = lens

	-- Блик на стекле
	local glint = Instance.new("Frame")
	glint.Size = UDim2.new(0.22, 0, 0.22, 0)
	glint.Position = UDim2.new(0.22, 0, 0.2, 0)
	glint.BackgroundColor3 = Color3.new(1, 1, 1)
	glint.BackgroundTransparency = 0.35
	glint.BorderSizePixel = 0
	glint.Parent = lens
	roundCorners(glint, UDim.new(1, 0))

	if showDots ~= false then
		local dotSize = math.max(3, math.floor(size * 0.09))
		for i = 1, level do
			local dot = Instance.new("Frame")
			dot.Size = UDim2.new(0, dotSize, 0, dotSize)
			dot.Position = UDim2.new(0, size * (0.06 + (i - 1) * 0.14), 0, size * 0.84)
			dot.BackgroundColor3 = rimColor
			dot.BorderSizePixel = 0
			dot.Parent = holder
			roundCorners(dot, UDim.new(1, 0))
		end
	end

	return holder
end

-- Пиктограмма корзины: плетёный короб с ободком и дугой-ручкой.
local function makeBasketIcon(size: number): Frame
	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(0, size, 0, size)
	holder.BackgroundTransparency = 1

	local thickness = math.max(2, math.floor(size * 0.07))

	-- Ручка: верхняя половина кольца (кольцо обрезаем контейнером)
	local handleClip = Instance.new("Frame")
	handleClip.Size = UDim2.new(0, size * 0.62, 0, size * 0.34)
	handleClip.Position = UDim2.new(0, size * 0.19, 0, size * 0.1)
	handleClip.BackgroundTransparency = 1
	handleClip.ClipsDescendants = true
	handleClip.Parent = holder

	local ring = Instance.new("Frame")
	ring.Size = UDim2.new(1, -thickness * 2, 0, size * 0.62 - thickness * 2)
	ring.Position = UDim2.new(0, thickness, 0, thickness)
	ring.BackgroundTransparency = 1
	ring.Parent = handleClip
	roundCorners(ring, UDim.new(1, 0))

	local ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = thickness
	ringStroke.Color = COLORS.basketWeave
	ringStroke.Parent = ring

	-- Короб
	local body = Instance.new("Frame")
	body.Size = UDim2.new(0, size * 0.8, 0, size * 0.44)
	body.Position = UDim2.new(0, size * 0.1, 0, size * 0.46)
	body.BackgroundColor3 = COLORS.basketBody
	body.BorderSizePixel = 0
	body.Parent = holder
	roundCorners(body, UDim.new(0, math.max(3, size * 0.12)))

	-- Плетение: две тёмные полосы
	for _, y in { 0.35, 0.68 } do
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0.86, 0, 0, math.max(2, math.floor(size * 0.05)))
		stripe.Position = UDim2.new(0.07, 0, y, 0)
		stripe.BackgroundColor3 = COLORS.basketWeave
		stripe.BorderSizePixel = 0
		stripe.Parent = body
	end

	-- Ободок сверху, чуть шире короба
	local rim = Instance.new("Frame")
	rim.Size = UDim2.new(0, size * 0.9, 0, math.max(3, size * 0.09))
	rim.Position = UDim2.new(0, size * 0.05, 0, size * 0.42)
	rim.BackgroundColor3 = COLORS.basketWeave
	rim.BorderSizePixel = 0
	rim.Parent = holder
	roundCorners(rim, UDim.new(0, math.max(2, size * 0.04)))

	return holder
end

-- === Построение интерфейса ===

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BasketUI"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
-- Доля экрана, а не фиксированные пиксели: на маленьком окне Studio
-- фиксированная панель обрезалась и нижняя кнопка уезжала за край.
panel.Size = UDim2.new(0.9, 0, 0.9, 0)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = COLORS.background
panel.BorderSizePixel = 0
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

-- Но не даём растянуться до нечитаемой ширины на больших мониторах
local panelConstraint = Instance.new("UISizeConstraint")
panelConstraint.MaxSize = Vector2.new(620, 760)
panelConstraint.MinSize = Vector2.new(300, 380)
panelConstraint.Parent = panel

local header = Instance.new("TextLabel")
header.Size = UDim2.new(1, -70, 0, 30)
header.Position = UDim2.new(0, 16, 0, 12)
header.BackgroundTransparency = 1
header.Font = Enum.Font.GothamBold
header.TextSize = 20
header.TextColor3 = COLORS.text
header.TextXAlignment = Enum.TextXAlignment.Left
header.Text = "Корзина"
header.Parent = panel

local subheader = Instance.new("TextLabel")
subheader.Size = UDim2.new(1, -70, 0, 18)
subheader.Position = UDim2.new(0, 16, 0, 42)
subheader.BackgroundTransparency = 1
subheader.Font = Enum.Font.Gotham
subheader.TextSize = 13
subheader.TextColor3 = COLORS.textDim
subheader.TextXAlignment = Enum.TextXAlignment.Left
subheader.Text = ""
subheader.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 32, 0, 32)
closeButton.Position = UDim2.new(1, -46, 0, 14)
closeButton.BackgroundColor3 = COLORS.panel
closeButton.BorderSizePixel = 0
closeButton.Text = ""
closeButton.Parent = panel

-- Крестик рисуем двумя полосками, а не символом шрифта: символ ✕ есть
-- не во всех шрифтах и на части устройств выглядел пустым прямоугольником.
for _, angle in { 45, -45 } do
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.5)
	bar.Size = UDim2.new(0, 16, 0, 2)
	bar.Rotation = angle
	bar.BackgroundColor3 = COLORS.text
	bar.BorderSizePixel = 0
	bar.Parent = closeButton

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar
end

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = closeButton

-- Вкладки "Корзина" / "Магазин"
local tabRow = Instance.new("Frame")
tabRow.Size = UDim2.new(1, -32, 0, 32)
tabRow.Position = UDim2.new(0, 16, 0, 68)
tabRow.BackgroundTransparency = 1
tabRow.Parent = panel

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 8)
tabLayout.Parent = tabRow

local function makeTab(text: string, order: number): TextButton
	local tab = Instance.new("TextButton")
	tab.Size = UDim2.new(0, 110, 1, 0)
	tab.BackgroundColor3 = COLORS.panel
	tab.BorderSizePixel = 0
	tab.Font = Enum.Font.GothamMedium
	tab.TextSize = 14
	tab.TextColor3 = COLORS.textDim
	tab.Text = text
	tab.AutoButtonColor = false
	tab.LayoutOrder = order
	tab.Parent = tabRow

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = tab

	return tab
end

local basketTab = makeTab("Корзина", 1)
local shopTab = makeTab("Магазин", 2)

-- Список грибов. Высота считается от низа панели, чтобы футер с
-- кнопкой подтверждения всегда оставался видимым.
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -32, 1, -208)
scroll.Position = UDim2.new(0, 16, 0, 108)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = panel

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scroll

local footer = Instance.new("Frame")
footer.Size = UDim2.new(1, -32, 0, 76)
footer.Position = UDim2.new(0, 16, 1, -88)
footer.BackgroundTransparency = 1
footer.Parent = panel

local confirmButton = Instance.new("TextButton")
confirmButton.Size = UDim2.new(1, 0, 0, 40)
confirmButton.Position = UDim2.new(0, 0, 1, -40)
confirmButton.BackgroundColor3 = COLORS.accent
confirmButton.BorderSizePixel = 0
confirmButton.Font = Enum.Font.GothamBold
confirmButton.TextSize = 15
confirmButton.TextColor3 = COLORS.background
confirmButton.Text = "Подтвердить разбор"
confirmButton.Parent = footer

local confirmCorner = Instance.new("UICorner")
confirmCorner.CornerRadius = UDim.new(0, 8)
confirmCorner.Parent = confirmButton

-- === Детальный просмотр одного гриба ===

local detailOverlay = Instance.new("Frame")
detailOverlay.Size = UDim2.new(1, 0, 1, 0)
detailOverlay.BackgroundColor3 = COLORS.background
detailOverlay.BackgroundTransparency = 0.15
detailOverlay.BorderSizePixel = 0
detailOverlay.Visible = false
detailOverlay.ZIndex = 10
detailOverlay.Parent = panel

local detailCorner = Instance.new("UICorner")
detailCorner.CornerRadius = UDim.new(0, 12)
detailCorner.Parent = detailOverlay

local detailBack = Instance.new("TextButton")
detailBack.Size = UDim2.new(0, 32, 0, 32)
detailBack.Position = UDim2.new(0, 14, 0, 14)
detailBack.BackgroundColor3 = COLORS.panel
detailBack.BorderSizePixel = 0
detailBack.Font = Enum.Font.GothamBold
detailBack.TextSize = 16
detailBack.TextColor3 = COLORS.textDim
detailBack.Text = ""
detailBack.ZIndex = 11
detailBack.Parent = detailOverlay
drawBackArrow(detailBack, 16, 2, COLORS.text)

local detailBackCorner = Instance.new("UICorner")
detailBackCorner.CornerRadius = UDim.new(0, 8)
detailBackCorner.Parent = detailBack

-- Содержимое детального просмотра выкладываем вертикальным списком,
-- а не фиксированными отступами от верха: панель теперь резиновая, и
-- жёсткие координаты уезжали за край на маленьком окне.
local detailBody = Instance.new("Frame")
detailBody.Size = UDim2.new(1, -32, 1, -70)
detailBody.Position = UDim2.new(0.5, 0, 0, 58)
detailBody.AnchorPoint = Vector2.new(0.5, 0)
detailBody.BackgroundTransparency = 1
detailBody.ZIndex = 11
detailBody.Parent = detailOverlay

local detailLayout = Instance.new("UIListLayout")
detailLayout.FillDirection = Enum.FillDirection.Vertical
detailLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
detailLayout.VerticalAlignment = Enum.VerticalAlignment.Top
detailLayout.Padding = UDim.new(0, 10)
detailLayout.SortOrder = Enum.SortOrder.LayoutOrder
detailLayout.Parent = detailBody

-- Картинка занимает долю высоты панели, поэтому остаётся крупной на
-- большом экране и не выдавливает кнопки на маленьком.
local detailIconHolder = Instance.new("Frame")
detailIconHolder.Size = UDim2.new(0, 180, 0.38, 0)
detailIconHolder.BackgroundTransparency = 1
detailIconHolder.LayoutOrder = 1
detailIconHolder.ZIndex = 11
detailIconHolder.Parent = detailBody

local detailName = Instance.new("TextLabel")
detailName.Size = UDim2.new(1, 0, 0, 30)
detailName.BackgroundTransparency = 1
detailName.Font = Enum.Font.GothamBold
detailName.TextSize = 20
detailName.LayoutOrder = 2
detailName.ZIndex = 11
detailName.Text = ""
detailName.Parent = detailBody

local detailHint = Instance.new("TextLabel")
detailHint.Size = UDim2.new(0.9, 0, 0, 44)
detailHint.BackgroundTransparency = 1
detailHint.Font = Enum.Font.Gotham
detailHint.TextSize = 13
detailHint.TextColor3 = COLORS.textDim
detailHint.TextWrapped = true
detailHint.LayoutOrder = 3
detailHint.ZIndex = 11
detailHint.Text = ""
detailHint.Parent = detailBody

-- Галочка (оставить) и крестик (выбросить)
local decisionRow = Instance.new("Frame")
decisionRow.Size = UDim2.new(1, 0, 0, 76)
decisionRow.BackgroundTransparency = 1
decisionRow.LayoutOrder = 4
decisionRow.ZIndex = 11
decisionRow.Parent = detailBody

local decisionLayout = Instance.new("UIListLayout")
decisionLayout.FillDirection = Enum.FillDirection.Horizontal
decisionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
decisionLayout.VerticalAlignment = Enum.VerticalAlignment.Center
decisionLayout.Padding = UDim.new(0, 16)
decisionLayout.SortOrder = Enum.SortOrder.LayoutOrder
decisionLayout.Parent = decisionRow

local keepButton = Instance.new("TextButton")
keepButton.Size = UDim2.new(0, 76, 0, 76)
keepButton.BackgroundColor3 = COLORS.panel
keepButton.BorderSizePixel = 0
keepButton.Font = Enum.Font.GothamBold
keepButton.TextSize = 34
keepButton.TextColor3 = COLORS.edible
keepButton.Text = ""
keepButton.LayoutOrder = 2
keepButton.ZIndex = 11
keepButton.Parent = decisionRow
drawCheck(keepButton, 38, 6, COLORS.edible)

local keepCorner = Instance.new("UICorner")
keepCorner.CornerRadius = UDim.new(0, 12)
keepCorner.Parent = keepButton

local dropButton = Instance.new("TextButton")
dropButton.Size = UDim2.new(0, 76, 0, 76)
dropButton.BackgroundColor3 = COLORS.panel
dropButton.BorderSizePixel = 0
dropButton.Font = Enum.Font.GothamBold
dropButton.TextSize = 34
dropButton.TextColor3 = COLORS.poison
dropButton.Text = ""
dropButton.LayoutOrder = 3
dropButton.ZIndex = 11
dropButton.Parent = decisionRow
drawCross(dropButton, 32, 6, COLORS.poison)

local dropCorner = Instance.new("UICorner")
dropCorner.CornerRadius = UDim.new(0, 12)
dropCorner.Parent = dropButton

-- Кнопка "рассмотреть" — без надписи, только пиктограмма лучшей лупы.
-- Стоит первой: сначала посмотри, потом решай.
local inspectButton = Instance.new("TextButton")
inspectButton.Size = UDim2.new(0, 76, 0, 76)
inspectButton.BackgroundColor3 = COLORS.panel
inspectButton.BorderSizePixel = 0
inspectButton.Text = ""
inspectButton.LayoutOrder = 1
inspectButton.ZIndex = 11
inspectButton.Visible = false
inspectButton.Parent = decisionRow
roundCorners(inspectButton, UDim.new(0, 12))

-- Рамка-подсветка: есть что рассматривать
local inspectGlow = Instance.new("UIStroke")
inspectGlow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
inspectGlow.Thickness = 2
inspectGlow.Color = COLORS.accent
inspectGlow.Parent = inspectButton

-- Полупрозрачная шторка поверх: гриб уже осмотрен этой лупой
local inspectDim = Instance.new("Frame")
inspectDim.Size = UDim2.new(1, 0, 1, 0)
inspectDim.BackgroundColor3 = COLORS.panel
inspectDim.BackgroundTransparency = 0.4
inspectDim.BorderSizePixel = 0
inspectDim.ZIndex = 13
inspectDim.Parent = inspectButton
roundCorners(inspectDim, UDim.new(0, 12))

local inspectIcon: Frame? = nil
local inspectIconLevel = 0

-- === Экран итогов разбора ===

local resultOverlay = Instance.new("Frame")
resultOverlay.Size = UDim2.new(1, 0, 1, 0)
resultOverlay.BackgroundColor3 = COLORS.background
resultOverlay.BackgroundTransparency = 0.05
resultOverlay.BorderSizePixel = 0
resultOverlay.Visible = false
resultOverlay.ZIndex = 20
resultOverlay.Parent = panel

local resultCorner = Instance.new("UICorner")
resultCorner.CornerRadius = UDim.new(0, 12)
resultCorner.Parent = resultOverlay

local resultBody = Instance.new("Frame")
resultBody.Size = UDim2.new(1, -40, 1, -40)
resultBody.Position = UDim2.new(0.5, 0, 0.5, 0)
resultBody.AnchorPoint = Vector2.new(0.5, 0.5)
resultBody.BackgroundTransparency = 1
resultBody.ZIndex = 21
resultBody.Parent = resultOverlay

local resultLayout = Instance.new("UIListLayout")
resultLayout.FillDirection = Enum.FillDirection.Vertical
resultLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
resultLayout.VerticalAlignment = Enum.VerticalAlignment.Center
resultLayout.Padding = UDim.new(0, 12)
resultLayout.SortOrder = Enum.SortOrder.LayoutOrder
resultLayout.Parent = resultBody

local resultTitle = Instance.new("TextLabel")
resultTitle.Size = UDim2.new(1, 0, 0, 26)
resultTitle.BackgroundTransparency = 1
resultTitle.Font = Enum.Font.Gotham
resultTitle.TextSize = 15
resultTitle.TextColor3 = COLORS.textDim
resultTitle.Text = "Разбор завершён"
resultTitle.LayoutOrder = 1
resultTitle.ZIndex = 21
resultTitle.Parent = resultBody

local resultDelta = Instance.new("TextLabel")
resultDelta.Size = UDim2.new(1, 0, 0, 64)
resultDelta.BackgroundTransparency = 1
resultDelta.Font = Enum.Font.GothamBold
resultDelta.TextSize = 52
resultDelta.Text = ""
resultDelta.LayoutOrder = 2
resultDelta.ZIndex = 21
resultDelta.Parent = resultBody

local resultBreakdown = Instance.new("TextLabel")
resultBreakdown.Size = UDim2.new(1, 0, 0, 66)
resultBreakdown.BackgroundTransparency = 1
resultBreakdown.Font = Enum.Font.GothamMedium
resultBreakdown.TextSize = 15
resultBreakdown.TextColor3 = COLORS.text
resultBreakdown.RichText = true
resultBreakdown.TextWrapped = true
resultBreakdown.Text = ""
resultBreakdown.LayoutOrder = 3
resultBreakdown.ZIndex = 21
resultBreakdown.Parent = resultBody

local resultTotal = Instance.new("TextLabel")
resultTotal.Size = UDim2.new(1, 0, 0, 24)
resultTotal.BackgroundTransparency = 1
resultTotal.Font = Enum.Font.Gotham
resultTotal.TextSize = 14
resultTotal.TextColor3 = COLORS.textDim
resultTotal.Text = ""
resultTotal.LayoutOrder = 4
resultTotal.ZIndex = 21
resultTotal.Parent = resultBody

local resultDiscovered = Instance.new("TextLabel")
resultDiscovered.Size = UDim2.new(0.9, 0, 0, 44)
resultDiscovered.BackgroundTransparency = 1
resultDiscovered.Font = Enum.Font.Gotham
resultDiscovered.TextSize = 13
resultDiscovered.TextColor3 = COLORS.accent
resultDiscovered.TextWrapped = true
resultDiscovered.Text = ""
resultDiscovered.LayoutOrder = 5
resultDiscovered.ZIndex = 21
resultDiscovered.Parent = resultBody

local resultClose = Instance.new("TextButton")
resultClose.Size = UDim2.new(0, 160, 0, 42)
resultClose.BackgroundColor3 = COLORS.accent
resultClose.BorderSizePixel = 0
resultClose.Font = Enum.Font.GothamBold
resultClose.TextSize = 15
resultClose.TextColor3 = COLORS.background
resultClose.Text = "Хорошо"
resultClose.LayoutOrder = 6
resultClose.ZIndex = 21
resultClose.Parent = resultBody

local resultCloseCorner = Instance.new("UICorner")
resultCloseCorner.CornerRadius = UDim.new(0, 8)
resultCloseCorner.Parent = resultClose

resultClose.Activated:Connect(function()
	resultOverlay.Visible = false
end)

local function closeDetail()
	detailInstanceId = nil
	detailOverlay.Visible = false
end

local function findSlot(instanceId: string)
	if not latestState then
		return nil
	end
	for _, slot in latestState.slots do
		if slot.instanceId == instanceId then
			return slot
		end
	end
	return nil
end

-- Размер гриба в детальном просмотре без лупы
local BASE_ICON_SIZE = 70

local function renderDetail()
	if not detailInstanceId then
		return
	end
	local slot = findSlot(detailInstanceId)
	if not slot then
		closeDetail() -- гриб исчез (выброшен или корзина подтверждена)
		return
	end

	-- Размер картинки = сила лупы, которой гриб рассматривали.
	-- Без осмотра гриб маленький, как в корзине, и порчи не видно.
	local bestTool = latestState.bestToolId and Tools[latestState.bestToolId]
	local wantedSize = BASE_ICON_SIZE
	for _, tool in Tools do
		if tool.level == slot.inspectedLevel then
			wantedSize = tool.iconSize
		end
	end
	local iconSize = math.min(wantedSize, math.max(BASE_ICON_SIZE, detailIconHolder.AbsoluteSize.Y))

	detailIconHolder:ClearAllChildren()
	local icon = makeMushroomIcon(slot.color, iconSize, slot.defect, slot.inspectedLevel, spotSeed(slot.instanceId))
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.ZIndex = 11
	for _, descendant in icon:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = 11
		end
	end
	icon.Parent = detailIconHolder

	-- Выбранный гриб: кнопка заливается зелёным, а сама галочка
	-- перерисовывается тёмной, иначе зелёное по зелёному не видно.
	if slot.kept then
		keepButton.BackgroundColor3 = COLORS.edible
		drawCheck(keepButton, 38, 6, COLORS.background)
	else
		keepButton.BackgroundColor3 = COLORS.panel
		drawCheck(keepButton, 38, 6, COLORS.edible)
	end

	local displayName = if slot.discovered then slot.name else "???"

	-- Про порчу игра ничего не пишет: лупа только увеличивает гриб,
	-- заметить следы игрок должен сам.
	if not bestTool then
		detailName.Text = "???"
		detailName.TextColor3 = COLORS.textDim
		detailHint.Text = "Без лупы не разглядеть ни вид, ни порчу. Доверься чутью."
	else
		-- Только название, без отметки съедобности: какой вид
		-- съедобный, игрок запоминает сам.
		if slot.discovered then
			detailName.Text = displayName
			detailName.TextColor3 = COLORS.text
		else
			detailName.Text = "???"
			detailName.TextColor3 = COLORS.textDim
		end
		detailHint.Text = if slot.inspectedLevel == 0
			then "Рассмотри гриб лупой: нет ли плесени или червей?"
			else "Присмотрись: нет ли на грибе плесени или следов червей?"
	end

	-- Кнопка лупы: самая сильная купленная лупа
	inspectButton.Visible = bestTool ~= nil
	if bestTool then
		if inspectIconLevel ~= bestTool.level then
			if inspectIcon then
				inspectIcon:Destroy()
			end
			local newIcon = makeMagnifierIcon(bestTool.level, 54)
			newIcon.AnchorPoint = Vector2.new(0.5, 0.5)
			newIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
			setZIndex(newIcon, 12)
			newIcon.Parent = inspectButton
			inspectIcon = newIcon
			inspectIconLevel = bestTool.level
		end

		local alreadyInspected = slot.inspectedLevel >= bestTool.level
		inspectDim.Visible = alreadyInspected
		inspectGlow.Enabled = not alreadyInspected
		inspectButton.AutoButtonColor = not alreadyInspected
	end
end

local function openDetail(instanceId: string)
	detailInstanceId = instanceId
	detailOverlay.Visible = true
	renderDetail()
end

detailBack.Activated:Connect(closeDetail)
inspectButton.Activated:Connect(function()
	if not detailInstanceId or not latestState or not latestState.bestToolId then
		return
	end
	local slot = findSlot(detailInstanceId)
	local bestTool = Tools[latestState.bestToolId]
	if slot and bestTool and slot.inspectedLevel < bestTool.level then
		-- x20 осматривает всю корзину — это решает сервер
		useToolOnSlot:FireServer(detailInstanceId, bestTool.id)
	end
end)
keepButton.Activated:Connect(function()
	if detailInstanceId then
		markMushroom:FireServer(detailInstanceId, true)
		closeDetail()
	end
end)
dropButton.Activated:Connect(function()
	if detailInstanceId then
		discardMushroom:FireServer(detailInstanceId)
		closeDetail()
	end
end)

-- === Отрисовка списка ===

local function makeRow(slot, index: number): TextButton
	-- Вся строка — кнопка: клик по ней открывает детальный просмотр
	local row = Instance.new("TextButton")
	row.Size = UDim2.new(1, -6, 0, 52)
	row.BackgroundColor3 = COLORS.row
	row.BorderSizePixel = 0
	row.AutoButtonColor = false
	row.Text = ""
	row.LayoutOrder = index

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 8)
	rowCorner.Parent = row

	row.MouseEnter:Connect(function()
		row.BackgroundColor3 = COLORS.rowHover
	end)
	row.MouseLeave:Connect(function()
		row.BackgroundColor3 = COLORS.row
	end)
	row.Activated:Connect(function()
		openDetail(slot.instanceId)
	end)

	local icon = makeMushroomIcon(slot.color, 34)
	icon.Position = UDim2.new(0, 12, 0.5, -17)
	icon.Parent = row

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -144, 1, 0)
	label.Position = UDim2.new(0, 56, 0, 0)
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = row

	-- Подпись строки. Отметка игрока важнее всего остального: по ней
	-- сразу видно, что гриб уже разобран и пойдёт в счёт.
	local base = if slot.discovered then slot.name else "???"
	if slot.kept then
		label.Text = "Беру · " .. (if slot.discovered then slot.name else "Гриб")
		label.TextColor3 = COLORS.edible
	elseif slot.discovered then
		-- Вид выучен: только название, без подсказки о съедобности
		label.Text = base
		label.TextColor3 = COLORS.text
	else
		label.Text = base
		label.TextColor3 = COLORS.textDim
	end

	-- Маленькая лупа в строке: гриб уже осматривали (цвет = какой лупой)
	if slot.inspectedLevel > 0 then
		local mark = makeMagnifierIcon(slot.inspectedLevel, 22, false)
		mark.Position = UDim2.new(1, -78, 0.5, -11)
		mark.Parent = row
	end

	local trash = Instance.new("TextButton")
	trash.Size = UDim2.new(0, 36, 0, 32)
	trash.Position = UDim2.new(1, -46, 0.5, -16)
	trash.BackgroundColor3 = COLORS.panel
	trash.BorderSizePixel = 0
	trash.Font = Enum.Font.GothamBold
	trash.TextSize = 18
	trash.TextColor3 = COLORS.poison
	trash.Text = ""
	trash.Parent = row
	drawCross(trash, 14, 3, COLORS.poison)

	local trashCorner = Instance.new("UICorner")
	trashCorner.CornerRadius = UDim.new(0, 6)
	trashCorner.Parent = trash

	trash.Activated:Connect(function()
		discardMushroom:FireServer(slot.instanceId)
	end)

	return row
end

-- Считаем близость к большой корзине прямо на клиенте: сервер знает её тоже, но
-- пересылать обновление на каждый шаг игрока было бы расточительно.
local function isNearStation(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	for _, station in CollectionService:GetTagged(GameConfig.stationTag) do
		if station:IsA("Model") and station.Parent then
			if (station:GetPivot().Position - root.Position).Magnitude <= STATION_RANGE then
				return true
			end
		end
	end
	return false
end

local function refreshConfirmButton()
	local hasMushrooms = latestState ~= nil and #latestState.slots > 0
	confirmButton.Visible = hasMushrooms
	if not hasMushrooms then
		return
	end

	local keptCount = 0
	for _, slot in latestState.slots do
		if slot.kept then
			keptCount += 1
		end
	end

	if keptCount == 0 then
		confirmButton.Text = "Отметь грибы галочкой"
		confirmButton.BackgroundColor3 = COLORS.accentDim
		confirmButton.TextColor3 = COLORS.textDim
		confirmButton.AutoButtonColor = false
		return
	end

	if isNearStation() then
		confirmButton.Text = string.format("Подтвердить разбор (%d)", keptCount)
		confirmButton.BackgroundColor3 = COLORS.accent
		confirmButton.TextColor3 = COLORS.background
		confirmButton.AutoButtonColor = true
	else
		confirmButton.Text = "Дойди до большой корзины"
		confirmButton.BackgroundColor3 = COLORS.accentDim
		confirmButton.TextColor3 = COLORS.textDim
		confirmButton.AutoButtonColor = false
	end
end

local renderShop -- объявляем заранее: render вызывает её до определения

local function render(state)
	latestState = state
	if not state then
		return
	end

	subheader.Text = string.format(
		"%s — %d / %d   •   Очки: %d",
		state.basketName,
		#state.slots,
		state.capacity,
		state.score
	)

	if activeTab == "shop" then
		footer.Visible = false
		renderShop()
		return
	end
	footer.Visible = true

	-- Чистим всё, кроме layout — иначе старая подпись "Корзина пуста"
	-- оставалась висеть поверх списка.
	for _, child in scroll:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	if #state.slots == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -6, 0, 60)
		empty.BackgroundTransparency = 1
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 14
		empty.TextColor3 = COLORS.textDim
		empty.Text = "Корзина пуста.\nНайди грибы в лесу и собери их на E."
		empty.Parent = scroll
	else
		for index, slot in state.slots do
			makeRow(slot, index).Parent = scroll
		end
	end

	refreshConfirmButton()

	if detailInstanceId then
		renderDetail()
	end
end

-- === Магазин ===

local function makeShopRow(
	title: string,
	description: string,
	price: number,
	order: number,
	state: string, -- "buy" | "owned" | "locked"
	onBuy: () -> (),
	icon: Frame? -- пиктограмма вместо названия
): Frame
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, 74)
	row.BackgroundColor3 = COLORS.row
	row.BorderSizePixel = 0
	row.LayoutOrder = order

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row

	local desc = Instance.new("TextLabel")
	if icon then
		-- Пиктограмма слева, описание рядом по центру строки
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 12, 0.5, 0)
		icon.Parent = row
		desc.Size = UDim2.new(1, -198, 1, -16)
		desc.Position = UDim2.new(0, 76, 0, 8)
		desc.TextYAlignment = Enum.TextYAlignment.Center
		desc.TextSize = 13
	else
		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(1, -130, 0, 20)
		name.Position = UDim2.new(0, 12, 0, 10)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextSize = 14
		name.TextColor3 = COLORS.text
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = title
		name.Parent = row

		desc.Size = UDim2.new(1, -130, 0, 34)
		desc.Position = UDim2.new(0, 12, 0, 30)
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.TextSize = 12
	end
	desc.BackgroundTransparency = 1
	desc.Font = Enum.Font.Gotham
	desc.TextColor3 = COLORS.textDim
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextWrapped = true
	desc.Text = description
	desc.Parent = row

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 104, 0, 38)
	button.Position = UDim2.new(1, -116, 0.5, -19)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.Parent = row

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 8)
	buttonCorner.Parent = button

	if state == "owned" then
		button.Text = "Куплено"
		button.BackgroundColor3 = COLORS.panel
		button.TextColor3 = COLORS.edible
		button.AutoButtonColor = false
	elseif state == "locked" then
		button.Text = "Недоступно"
		button.BackgroundColor3 = COLORS.panel
		button.TextColor3 = COLORS.textDim
		button.AutoButtonColor = false
	else
		button.Text = string.format("%d очк.", price)
		button.BackgroundColor3 = COLORS.accent
		button.TextColor3 = COLORS.background
		button.AutoButtonColor = true
		button.Activated:Connect(onBuy)
	end

	return row
end

local BASKET_ORDER = { "SMALL", "MEDIUM", "LARGE", "HUGE" }
local TOOL_ORDER = { "MAGNIFIER", "MAGNIFIER_X10", "MAGNIFIER_X20" }

renderShop = function()
	for _, child in scroll:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	if not latestState then
		return
	end

	local order = 0
	local owned = latestState.ownedTools or {}

	-- Лупы: покупаются по порядку, как корзины
	for _, toolId in TOOL_ORDER do
		local tool = Tools[toolId]
		order += 1

		local state = "buy"
		if table.find(owned, toolId) then
			state = "owned"
		elseif tool.previous and not table.find(owned, tool.previous) then
			state = "locked"
		end
		makeShopRow(tool.name, tool.description, tool.price, order, state, function()
			buyItem:FireServer("tool", toolId)
		end, makeMagnifierIcon(tool.level, 50)).Parent = scroll
	end

	-- Следующая по очереди корзина: покупать вразнобой нельзя, иначе
	-- прогрессия теряет смысл.
	local currentIndex = table.find(BASKET_ORDER, latestState.basketId) or 1
	local nextId = BASKET_ORDER[currentIndex + 1]

	if nextId then
		local basket = Baskets[nextId]
		order += 1
		makeShopRow(
			basket.name,
			string.format("Вмещает %d грибов вместо %d", basket.capacity, latestState.capacity),
			basket.price,
			order,
			"buy",
			function()
				buyItem:FireServer("basket", nextId)
			end,
			makeBasketIcon(50)
		).Parent = scroll
	else
		order += 1
		makeShopRow(
			"Корзины",
			"У тебя самая большая корзина.",
			0,
			order,
			"owned",
			function() end,
			makeBasketIcon(50)
		).Parent = scroll
	end
end

-- === Открытие/закрытие ===

local refreshTabsOnOpen -- присваивается ниже, после создания вкладок

local function setOpen(open: boolean)
	isOpen = open
	screenGui.Enabled = open
	if not open then
		closeDetail()
		return
	end
	local ok, state = pcall(function()
		return getBasketState:InvokeServer()
	end)
	if ok then
		render(state)
		if refreshTabsOnOpen then
			refreshTabsOnOpen()
		end
	end
end

closeButton.Activated:Connect(function()
	setOpen(false)
end)

-- === Вкладки ===

local function refreshTabs()
	local shopAvailable = isNearStation()

	basketTab.BackgroundColor3 = if activeTab == "basket" then COLORS.accent else COLORS.panel
	basketTab.TextColor3 = if activeTab == "basket" then COLORS.background else COLORS.textDim

	if activeTab == "shop" then
		shopTab.BackgroundColor3 = COLORS.accent
		shopTab.TextColor3 = COLORS.background
	else
		shopTab.BackgroundColor3 = COLORS.panel
		shopTab.TextColor3 = if shopAvailable then COLORS.text else COLORS.textDim
	end

	shopTab.Text = if shopAvailable then "Магазин" else "Магазин 🔒"
end

local function setTab(tab: string)
	-- Торговать можно только у большой корзины: в лесу вкладка заблокирована.
	if tab == "shop" and not isNearStation() then
		return
	end
	activeTab = tab
	refreshTabs()
	render(latestState)
end

refreshTabsOnOpen = refreshTabs

basketTab.Activated:Connect(function()
	setTab("basket")
end)
shopTab.Activated:Connect(function()
	setTab("shop")
end)

confirmButton.Activated:Connect(function()
	if isNearStation() then
		confirmBasket:FireServer()
	end
end)

-- Пока окно открыто, следим за тем, отошёл ли игрок от корзины.
-- Раз в полсекунды достаточно — это не нуждается в каждом кадре.
task.spawn(function()
	while true do
		task.wait(0.5)
		if isOpen then
			refreshConfirmButton()
			-- если игрок ушёл от корзины, вкладку магазина надо закрыть
			if activeTab == "shop" and not isNearStation() then
				activeTab = "basket"
				render(latestState)
			end
			refreshTabs()
		end
	end
end)

basketUpdated.OnClientEvent:Connect(function(state)
	if isOpen then
		render(state)
	else
		latestState = state
	end
end)

-- Переход между картами: закрываем корзину и магазин, иначе игрок
-- попадает в психолес с открытым меню поверх экрана.
local psychoTransition = ReplicatedStorage:WaitForChild("PsychoTransition", 15)
if psychoTransition and psychoTransition:IsA("RemoteEvent") then
	psychoTransition.OnClientEvent:Connect(function()
		-- Закрываем окно и убираем экран итогов: на новой карте корзина
		-- должна открываться сразу списком, а не прошлым разбором.
		activeTab = "basket"
		resultOverlay.Visible = false
		setOpen(false)
	end)
end

confirmResult.OnClientEvent:Connect(function(result)
	closeDetail()

	-- Этот разбор открыл психолес: итоги не показываем, сейчас будет
	-- переход на другую карту.
	if result.hideResult then
		resultOverlay.Visible = false
		return
	end

	local delta = result.scoreDelta
	resultDelta.Text = string.format("%+d", delta)
	resultDelta.TextColor3 = if delta > 0
		then COLORS.edible
		elseif delta < 0 then COLORS.poison
		else COLORS.textDim

	-- RichText, чтобы в одной строке были и зелёное, и красное число
	local lines = {}
	table.insert(
		lines,
		string.format(
			'<font color="rgb(120,210,110)">✓ Съедобных: %d</font>',
			result.correct
		)
	)
	if result.wrong > 0 then
		table.insert(
			lines,
			string.format('<font color="rgb(225,95,85)">✗ Несъедобных: %d</font>', result.wrong)
		)
	end
	if (result.spoiled or 0) > 0 then
		table.insert(
			lines,
			string.format('<font color="rgb(160,150,138)">из них испорчено: %d</font>', result.spoiled)
		)
	end
	resultBreakdown.Text = table.concat(lines, "\n")

	resultTotal.Text = if (result.multiplier or 1) > 1
		then string.format("Всего очков: %d   •   психолес ×%d", result.newScore, result.multiplier)
		else string.format("Всего очков: %d", result.newScore)

	-- Названия найденных грибов показываем всегда, даже без лупы: так
	-- игрок знает, что было в корзине, но не знает, где какой.
	if result.foundNames and #result.foundNames > 0 then
		resultDiscovered.Text = "Нашли: " .. table.concat(result.foundNames, ", ")
	else
		resultDiscovered.Text = ""
	end

	resultOverlay.Visible = true
end)

purchaseResult.OnClientEvent:Connect(function(result)
	if result.ok then
		subheader.Text = "Куплено: " .. result.name
	else
		subheader.Text = result.reason
	end
	-- через пару секунд подзаголовок вернётся к обычному виду при
	-- следующем обновлении состояния
	task.delay(2.5, function()
		if isOpen and latestState then
			render(latestState)
		end
	end)
end)

local ACTION_NAME = "ToggleBasket"
ContextActionService:BindAction(ACTION_NAME, function(_name, inputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	setOpen(not isOpen)
	return Enum.ContextActionResult.Sink
end, true, Enum.KeyCode.B)
ContextActionService:SetTitle(ACTION_NAME, "Корзина")
