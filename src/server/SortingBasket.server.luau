--[[
	SortingBasket.server.luau

	Большая плетёная корзина — место, куда игрок приносит собранные
	грибы: там открывается разбор и магазин. Заменяет прежний стол
	с вывеской.

	Строится кодом при запуске сервера, поэтому лежит в git и не зависит
	от того, что расставлено в Studio. Сама корзина — это Model с тегом
	GameConfig.stationTag; по нему её находят BasketService (можно ли
	подтверждать разбор), клиентский UI и модуль зон.

	Форма как у корзины с фото: овальный короб из вертикальных прутьев,
	перевязанный горизонтальными полосами, сверху обод и дуга-ручка.
	Внутри лежат грибы, чтобы издалека было понятно, зачем она нужна.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MushroomTypes = require(ReplicatedStorage.Shared.MushroomTypes)

local CONFIG = {
	modelName = "SortingBasket",

	-- Где стоит корзина, если на карте не осталось старого стола.
	fallbackPosition = Vector3.new(0, 0, 0),

	-- Размеры короба (studs). Корзина намеренно большая: это ориентир,
	-- который видно издалека.
	radiusX = 9, -- половина длины (длинная сторона)
	radiusZ = 6.5, -- половина ширины
	height = 8,
	bottomTaper = 0.82, -- во сколько раз низ уже верха

	slatCount = 30, -- вертикальные прутья
	slatWidth = 1.1,
	slatThickness = 0.45,

	weaveRows = { 0.12, 0.34, 0.56, 0.78 }, -- высоты горизонтальных полос
	weaveHeight = 0.7,
	weaveThickness = 0.55,

	rimHeight = 1, -- обод сверху
	rimThickness = 0.9,

	-- Площадка появления игрока: ставится рядом с корзиной, если на
	-- карте нет своей SpawnLocation.
	spawnOffset = 18, -- на сколько studs в сторону от корзины
	spawnSize = Vector3.new(12, 1, 12),
	spawnColor = Color3.fromRGB(120, 150, 90),

	handleSegments = 16,
	handleHeight = 7.5, -- насколько дуга поднимается над ободом
	handleThickness = 0.8,

	wicker = Color3.fromRGB(205, 162, 108),
	wickerDark = Color3.fromRGB(176, 133, 82),
	rimColor = Color3.fromRGB(190, 147, 94),
}

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Wood
	part.Anchored = true
	-- Прутья и ручка сквозные: о тонкие части персонаж цепляется.
	-- За столкновения отвечает отдельная оболочка (см. CollisionHull).
	part.CanCollide = false
	part.Parent = parent
	return part
end

-- Точка на овале и направление "наружу" от него
local function ovalPoint(angle: number, radiusX: number, radiusZ: number): (Vector3, Vector3)
	local position = Vector3.new(math.cos(angle) * radiusX, 0, math.sin(angle) * radiusZ)
	-- нормаль к эллипсу: та же точка, но с обратными радиусами
	local outward = Vector3.new(math.cos(angle) / radiusX, 0, math.sin(angle) / radiusZ).Unit
	return position, outward
end

-- Кольцо из коротких отрезков по овалу: и плетение, и обод отличаются
-- только толщиной и цветом.
local function buildRing(
	parent: Instance,
	base: CFrame,
	y: number,
	radiusX: number,
	radiusZ: number,
	segmentHeight: number,
	segmentThickness: number,
	color: Color3,
	name: string
)
	local count = CONFIG.slatCount
	local perimeter = math.pi * (3 * (radiusX + radiusZ) - math.sqrt((3 * radiusX + radiusZ) * (radiusX + 3 * radiusZ)))
	local segmentLength = perimeter / count * 1.15

	for index = 1, count do
		local angle = (index - 1) / count * math.pi * 2
		local point, outward = ovalPoint(angle, radiusX, radiusZ)
		local worldPoint = point + Vector3.new(0, y, 0)
		makePart(
			name,
			Vector3.new(segmentLength, segmentHeight, segmentThickness),
			base * CFrame.lookAt(worldPoint, worldPoint + outward),
			color,
			parent
		)
	end
end

-- Грибы внутри корзины: шляпка и ножка, только съедобные виды.
local function buildMushroomsInside(parent: Instance, base: CFrame)
	local colors = {}
	for _, data in MushroomTypes do
		if data.isEdible then
			table.insert(colors, data.modelColor)
		end
	end

	local spots = {
		{ -4.5, 1.2, 0.9 },
		{ -1.5, -2.0, 1.15 },
		{ 1.8, 1.8, 1 },
		{ 5.0, -0.8, 1.2 },
		{ 0.2, 0.4, 1.35 },
		{ 3.4, 2.6, 0.85 },
		{ -3.0, -1.0, 1 },
	}

	for index, spot in spots do
		local color = colors[(index - 1) % #colors + 1]
		local scale = spot[3]
		local stemHeight = 1.6 * scale
		local localPosition = Vector3.new(spot[1], CONFIG.height * 0.62, spot[2])

		makePart(
			"MushroomStem",
			Vector3.new(0.7 * scale, stemHeight, 0.7 * scale),
			base * CFrame.new(localPosition + Vector3.new(0, stemHeight / 2, 0)),
			Color3.fromRGB(235, 220, 195),
			parent
		)

		local cap = Instance.new("Part")
		cap.Name = "MushroomCap"
		cap.Shape = Enum.PartType.Ball
		cap.Size = Vector3.new(2.6 * scale, 1.7 * scale, 2.6 * scale)
		cap.CFrame = base * CFrame.new(localPosition + Vector3.new(0, stemHeight + 0.3 * scale, 0))
		cap.Color = color
		cap.Material = Enum.Material.SmoothPlastic
		cap.Anchored = true
		cap.CanCollide = false
		cap.Parent = parent
	end
end

local function buildBasket(position: Vector3): Model
	local model = Instance.new("Model")
	model.Name = CONFIG.modelName

	-- Низ корзины на земле, дальше всё считаем от этой точки
	local base = CFrame.new(position)

	local bottomRadiusX = CONFIG.radiusX * CONFIG.bottomTaper
	local bottomRadiusZ = CONFIG.radiusZ * CONFIG.bottomTaper

	-- Дно: цилиндр, сплющенный в овал (ось цилиндра — локальный X,
	-- поэтому разворачиваем его "лёжа")
	local bottom = makePart(
		"Bottom",
		Vector3.new(0.8, bottomRadiusZ * 2, bottomRadiusX * 2),
		base * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, math.rad(90), math.rad(90)),
		CONFIG.wickerDark,
		model
	)
	bottom.Shape = Enum.PartType.Cylinder

	-- Вертикальные прутья наклонены наружу, поэтому корзина
	-- расширяется кверху, как на фото
	local tilt = math.atan2(CONFIG.radiusX - bottomRadiusX, CONFIG.height)
	local meanRadiusX = (CONFIG.radiusX + bottomRadiusX) / 2
	local meanRadiusZ = (CONFIG.radiusZ + bottomRadiusZ) / 2

	for index = 1, CONFIG.slatCount do
		local angle = (index - 1) / CONFIG.slatCount * math.pi * 2
		local point, outward = ovalPoint(angle, meanRadiusX, meanRadiusZ)
		local worldPoint = point + Vector3.new(0, CONFIG.height / 2, 0)

		local color = if index % 2 == 0 then CONFIG.wicker else CONFIG.wickerDark
		makePart(
			"Slat",
			Vector3.new(CONFIG.slatWidth, CONFIG.height, CONFIG.slatThickness),
			base * CFrame.lookAt(worldPoint, worldPoint + outward) * CFrame.Angles(-tilt, 0, 0),
			color,
			model
		)
	end

	-- Горизонтальное плетение
	for _, fraction in CONFIG.weaveRows do
		local y = CONFIG.height * fraction
		local widen = CONFIG.bottomTaper + (1 - CONFIG.bottomTaper) * fraction
		buildRing(
			model,
			base,
			y,
			CONFIG.radiusX * widen + 0.1,
			CONFIG.radiusZ * widen + 0.1,
			CONFIG.weaveHeight,
			CONFIG.weaveThickness,
			CONFIG.wicker,
			"Weave"
		)
	end

	-- Обод
	buildRing(
		model,
		base,
		CONFIG.height,
		CONFIG.radiusX + 0.15,
		CONFIG.radiusZ + 0.15,
		CONFIG.rimHeight,
		CONFIG.rimThickness,
		CONFIG.rimColor,
		"Rim"
	)

	-- Ручка: дуга поперёк короткой стороны, из отрезков по полукругу
	local previous = nil
	for index = 0, CONFIG.handleSegments do
		local t = index / CONFIG.handleSegments
		local angle = math.pi * t
		local current = Vector3.new(
			0,
			CONFIG.height + math.sin(angle) * CONFIG.handleHeight,
			math.cos(angle) * (CONFIG.radiusZ - 0.2)
		)
		if previous then
			local middle = (previous + current) / 2
			local length = (current - previous).Magnitude + 0.15
			makePart(
				"Handle",
				Vector3.new(CONFIG.handleThickness, CONFIG.handleThickness, length),
				base * CFrame.lookAt(middle, middle + (current - previous).Unit),
				CONFIG.wicker,
				model
			)
		end
		previous = current
	end

	-- Перевязка у основания ручки, как на фото
	for _, side in { -1, 1 } do
		makePart(
			"HandleWrap",
			Vector3.new(1.6, 1.6, 1.6),
			base * CFrame.new(0, CONFIG.height + 0.2, side * (CONFIG.radiusZ - 0.2)),
			CONFIG.wickerDark,
			model
		)
	end

	-- Столкновения вешаем на одну гладкую невидимую оболочку, а не на
	-- прутья: о тонкие части персонаж цепляется и застревает. Сами
	-- прутья остаются сквозными и только рисуют корзину.
	local hull = makePart(
		"CollisionHull",
		Vector3.new(CONFIG.height, CONFIG.radiusZ * 2 + 0.6, CONFIG.radiusX * 2 + 0.6),
		base * CFrame.new(0, CONFIG.height / 2, 0) * CFrame.Angles(0, math.rad(90), math.rad(90)),
		CONFIG.wicker,
		model
	)
	hull.Shape = Enum.PartType.Cylinder
	hull.Transparency = 1
	hull.CanCollide = true
	hull.CanQuery = false -- не мешает ProximityPrompt и лучам

	buildMushroomsInside(model, base)

	model.PrimaryPart = bottom
	model.Parent = workspace
	CollectionService:AddTag(model, GameConfig.stationTag)

	return model
end

-- Площадка появления: игрок должен начинать рядом с корзиной, иначе
-- он возникает неизвестно где и не понимает, куда нести грибы. Если на
-- карте уже есть своя SpawnLocation, ничего не трогаем.
local function ensureSpawnLocation(basketPosition: Vector3)
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("SpawnLocation") and instance.Name ~= "BasketSpawn" then
			return -- своя площадка есть, она главнее
		end
	end

	local existing = workspace:FindFirstChild("BasketSpawn")
	if existing then
		existing:Destroy()
	end

	-- Отходим в сторону от корзины и опускаем площадку на землю
	local target = basketPosition + Vector3.new(CONFIG.radiusX + CONFIG.spawnOffset, 0, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace:FindFirstChild(CONFIG.modelName) }

	local result = workspace:Raycast(Vector3.new(target.X, 500, target.Z), Vector3.new(0, -2000, 0), params)
	local groundY = if result then result.Position.Y else basketPosition.Y

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "BasketSpawn"
	spawn.Size = CONFIG.spawnSize
	spawn.Position = Vector3.new(target.X, groundY + CONFIG.spawnSize.Y / 2, target.Z)
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Color = CONFIG.spawnColor
	spawn.Material = Enum.Material.Grass
	spawn.Neutral = true
	spawn.Duration = 0 -- без щита неуязвимости
	spawn.Parent = workspace
end

-- Куда ставить: на место старого стола, если он ещё остался на карте,
-- иначе в центр карты, на землю.
local function resolvePosition(): Vector3
	for _, legacy in CollectionService:GetTagged("SortingStation") do
		if legacy:IsA("Model") and legacy.Parent then
			local pivot = legacy:GetPivot().Position
			local extents = legacy:GetExtentsSize()
			return Vector3.new(pivot.X, pivot.Y - extents.Y / 2, pivot.Z)
		elseif legacy:IsA("BasePart") and legacy.Parent then
			return legacy.Position - Vector3.new(0, legacy.Size.Y / 2, 0)
		end
	end

	local origin = CONFIG.fallbackPosition
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace:FindFirstChild(CONFIG.modelName) }

	local result = workspace:Raycast(Vector3.new(origin.X, 500, origin.Z), Vector3.new(0, -2000, 0), params)
	if result then
		return result.Position
	end
	return origin
end

local existing = workspace:FindFirstChild(CONFIG.modelName)
if existing then
	existing:Destroy() -- перезапуск сервера не должен плодить корзины
end

local basketPosition = resolvePosition()
buildBasket(basketPosition)
ensureSpawnLocation(basketPosition)
