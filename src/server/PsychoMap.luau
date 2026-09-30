--[[
	PsychoMap.luau

	Психоделический лес — награда за радужный гриб.

	Как это работает:
	  1. В обычном лесу с шансом GameConfig.psycho.rainbowChance вырастает
	     радужный гриб (вид RAINBOW_CAP, шляпка переливается).
	  2. Игрок приносит его к большой корзине и подтверждает как съедобный.
	  3. BasketService зовёт PsychoMap.Enter — игрока переносит на
	     отдельный остров далеко от основной карты.
	  4. Правила там те же, но очки за разбор удваиваются, а грибы
	     ярко-салатовые и одинаковые на вид: по цвету не угадаешь.
	  5. Как только игрок заработал psycho.targetScore очков ИЛИ вышло
	     psycho.timeLimitSeconds, его возвращает обратно.

	Остров строится один раз при старте сервера, далеко в стороне
	(psycho.islandOrigin), поэтому с основной карты его не видно.

	Очки игрока общие: PsychoMap ничего не обнуляет, он только считает,
	сколько заработано за текущий визит.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MushroomTypes = require(ReplicatedStorage.Shared.MushroomTypes)
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local CONFIG = GameConfig.psycho

local notify = ReplicatedStorage:FindFirstChild("Notify")
if not notify then
	notify = Instance.new("RemoteEvent")
	notify.Name = "Notify"
	notify.Parent = ReplicatedStorage
end

local PsychoMap = {}

-- Кто сейчас в психолесу: игрок -> { earned, startedAt, returnCFrame }
local visits: { [Player]: { earned: number, startedAt: number, returnCFrame: CFrame } } = {}

local islandFolder: Folder? = nil
-- Появляемся В СТОРОНЕ от корзины: если встать ровно в центр острова,
-- персонаж оказывается внутри корзины и застревает в ней.
local islandSpawn = CONFIG.islandOrigin + Vector3.new(0, 8, 26)

-- Сообщение клиенту о переходе: по нему закрывается окно корзины и
-- магазина, чтобы игрок не оказался на новой карте с открытым меню.
local psychoTransition = ReplicatedStorage:FindFirstChild("PsychoTransition")
if not psychoTransition then
	psychoTransition = Instance.new("RemoteEvent")
	psychoTransition.Name = "PsychoTransition"
	psychoTransition.Parent = ReplicatedStorage
end

-- === Постройка острова ===

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.Parent = parent
	return part
end

-- Дерево психолеса: ствол и три шара кроны. Крона помечается тегом
-- "Rainbow" — цвет ей перебирает клиентский скрипт RainbowEffect,
-- чтобы не гонять изменения цвета по сети каждый кадр.
local function buildTree(position: Vector3, scale: number, parent: Instance)
	local trunkHeight = 14 * scale

	local trunk = makePart(
		"Trunk",
		Vector3.new(trunkHeight, 2 * scale, 2 * scale),
		CFrame.new(position + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(80, 40, 90),
		parent
	)
	trunk.Shape = Enum.PartType.Cylinder
	trunk.CanCollide = true
	CollectionService:AddTag(trunk, "Rainbow")

	for index = 1, 3 do
		local crownSize = (9 + math.random() * 5) * scale
		local crown = makePart(
			"Crown",
			Vector3.new(crownSize, crownSize, crownSize),
			CFrame.new(
				position
					+ Vector3.new(
						(math.random() - 0.5) * 4 * scale,
						trunkHeight + crownSize * 0.35 + index * 1.5 * scale,
						(math.random() - 0.5) * 4 * scale
					)
			),
			Color3.fromRGB(255, 120, 220),
			parent
		)
		crown.Shape = Enum.PartType.Ball
		CollectionService:AddTag(crown, "Rainbow")
	end
end

-- Корзина психолеса: тот же смысл, что у большой корзины в обычном
-- лесу, только маленькая и светящаяся. Тег общий, поэтому разбор и
-- магазин работают здесь без единой правки в BasketService.
local function buildBasket(position: Vector3, parent: Instance)
	local basket = Instance.new("Model")
	basket.Name = "PsychoBasket"

	local body = makePart(
		"Body",
		Vector3.new(14, 7, 10),
		CFrame.new(position + Vector3.new(0, 3.5, 0)),
		Color3.fromRGB(255, 90, 200),
		basket
	)
	body.CanCollide = true
	CollectionService:AddTag(body, "Rainbow")

	local rim = makePart(
		"Rim",
		Vector3.new(15, 1.2, 11),
		CFrame.new(position + Vector3.new(0, 7.4, 0)),
		Color3.fromRGB(120, 255, 200),
		basket
	)
	CollectionService:AddTag(rim, "Rainbow")

	basket.PrimaryPart = body
	basket.Parent = parent
	CollectionService:AddTag(basket, GameConfig.stationTag)
end

-- Гриб психолеса: белая ножка и шляпка-диск, на которой крутится
-- спираль из двух цветов — чёрного и случайного яркого. Плюс свечение:
-- шляпка из Neon и точечный свет того же цвета.
--
-- Саму спираль крутит клиент (RainbowEffect) по тегу "Spiral": вращение
-- картинки незачем гонять по сети.
local function buildMushroom(position: Vector3, parent: Instance): (Model, Color3)
	local model = Instance.new("Model")
	model.Name = "Mushroom"

	-- Яркий случайный цвет: насыщенность и яркость на максимуме, чтобы
	-- контраст с чёрным был резким
	local capColor = Color3.fromHSV(math.random(), 1, 1)

	local stem = makePart(
		"Stem",
		Vector3.new(1.6, 0.5, 0.5),
		CFrame.new(position + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(250, 250, 240),
		model
	)
	stem.Shape = Enum.PartType.Cylinder
	stem.Material = Enum.Material.Neon

	-- Шляпка — плоский диск: на его верхнюю грань ложится спираль
	local cap = makePart(
		"Cap",
		Vector3.new(0.45, 2.6, 2.6),
		CFrame.new(position + Vector3.new(0, 1.75, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		capColor,
		model
	)
	cap.Shape = Enum.PartType.Cylinder
	cap.Material = Enum.Material.Neon
	CollectionService:AddTag(cap, "Spiral")

	local light = Instance.new("PointLight")
	light.Color = capColor
	light.Brightness = 3
	light.Range = 14
	light.Parent = cap

	-- Спираль рисуем на обеих круглых гранях диска: какая из них смотрит
	-- вверх, зависит от поворота, а лишняя просто не видна снизу.
	for _, face in { Enum.NormalId.Right, Enum.NormalId.Left } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 80
		gui.LightInfluence = 0
		gui.Parent = cap

		local holder = Instance.new("Frame")
		holder.Name = "Holder"
		holder.Size = UDim2.fromScale(1, 1)
		holder.BackgroundColor3 = capColor
		holder.BorderSizePixel = 0
		holder.Parent = gui

		-- Восемь лучей вразбег: вместе с вращением читаются как спираль
		for index = 1, 8 do
			local blade = Instance.new("Frame")
			blade.AnchorPoint = Vector2.new(0.5, 0.5)
			blade.Position = UDim2.fromScale(0.5, 0.5)
			blade.Size = UDim2.fromScale(0.17, 1.5)
			blade.Rotation = (index - 1) * 22.5
			blade.BackgroundColor3 = Color3.new(0, 0, 0)
			blade.BorderSizePixel = 0
			blade.Parent = holder
		end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Собрать"
	prompt.ObjectText = "Гриб"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = GameConfig.pickupRadius
	prompt.Parent = cap

	model.PrimaryPart = stem
	model.Parent = parent
	CollectionService:AddTag(model, "Mushroom")

	return model, capColor
end

-- Случайная точка на острове, но не у самой корзины
local function randomSpot(): Vector3
	local angle = math.random() * math.pi * 2
	local radius = 25 + math.random() * (CONFIG.islandRadius - 32)
	return CONFIG.islandOrigin + Vector3.new(math.cos(angle) * radius, 2, math.sin(angle) * radius)
end

-- Виды для психолеса: только съедобные и без радужного. Ядовитых тут
-- нет совсем — это подарок, а не проверка на внимательность.
local psychoTypes = {}
for _, data in MushroomTypes do
	if data.isEdible and data.id ~= "RAINBOW_CAP" then
		table.insert(psychoTypes, data)
	end
end

local function pickType()
	local total = 0
	for _, data in psychoTypes do
		total += data.rarity
	end
	local roll = math.random() * total
	local cumulative = 0
	for _, data in psychoTypes do
		cumulative += data.rarity
		if roll <= cumulative then
			return data
		end
	end
	return psychoTypes[1]
end

local function spawnMushroom(position: Vector3)
	local typeData = pickType()
	local model, capColor = buildMushroom(position, islandFolder :: Folder)

	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	local taken = false

	if prompt then
		prompt.Triggered:Connect(function(player: Player)
			if taken or model:GetAttribute("Consumed") then
				return
			end
			taken = true

			-- Порчи в психолесу нет: это подарок, а не испытание
			local added = PlayerData.AddMushroom(player, typeData.id, capColor, 0)
			if added then
				model:Destroy()
			else
				taken = false
				notify:FireClient(player, "Корзина полна. Разбери её у розовой корзины.")
			end
		end)
	end

	model.Destroying:Connect(function()
		task.delay(CONFIG.respawnTime, function()
			if islandFolder and islandFolder.Parent then
				spawnMushroom(position)
			end
		end)
	end)
end

local function buildIsland()
	local existing = workspace:FindFirstChild("PsychoIsland")
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "PsychoIsland"
	folder.Parent = workspace
	islandFolder = folder

	-- Площадка
	local ground = makePart(
		"Ground",
		Vector3.new(6, CONFIG.islandRadius * 2, CONFIG.islandRadius * 2),
		CFrame.new(CONFIG.islandOrigin) * CFrame.Angles(0, math.rad(90), math.rad(90)),
		Color3.fromRGB(70, 30, 110),
		folder
	)
	ground.Shape = Enum.PartType.Cylinder
	ground.CanCollide = true
	CollectionService:AddTag(ground, "Rainbow")

	-- Невидимая стена по краю, чтобы не свалиться в пустоту
	for index = 1, 24 do
		local angle = (index - 1) / 24 * math.pi * 2
		local point = CONFIG.islandOrigin
			+ Vector3.new(math.cos(angle) * CONFIG.islandRadius, 10, math.sin(angle) * CONFIG.islandRadius)
		local wall = makePart(
			"Wall",
			Vector3.new(CONFIG.islandRadius * 0.3, 20, 1),
			CFrame.lookAt(point, point + (point - CONFIG.islandOrigin).Unit),
			Color3.new(1, 1, 1),
			folder
		)
		wall.Transparency = 1
		wall.CanCollide = true
	end

	buildBasket(CONFIG.islandOrigin + Vector3.new(0, 3, 0), folder)

	for index = 1, CONFIG.treeCount do
		local angle = (index / CONFIG.treeCount) * math.pi * 2 + math.random() * 0.3
		local radius = 30 + math.random() * (CONFIG.islandRadius - 36)
		buildTree(
			CONFIG.islandOrigin + Vector3.new(math.cos(angle) * radius, 3, math.sin(angle) * radius),
			0.8 + math.random() * 0.7,
			folder
		)
	end

	for _ = 1, CONFIG.mushroomCount do
		spawnMushroom(randomSpot())
	end
end

-- === Вход и выход ===

function PsychoMap.IsActive(player: Player): boolean
	return visits[player] ~= nil
end

-- Множитель очков: в психолесу очки удваиваются
function PsychoMap.GetScoreMultiplier(player: Player): number
	return if visits[player] then CONFIG.scoreMultiplier else 1
end

local function teleport(player: Player, cframe: CFrame): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	character:PivotTo(cframe)
	return true
end

function PsychoMap.Exit(player: Player, reason: string?)
	local visit = visits[player]
	if not visit then
		return
	end
	visits[player] = nil

	psychoTransition:FireClient(player, "exit")
	teleport(player, visit.returnCFrame)

	notify:FireClient(
		player,
		reason or string.format("Психолес растаял. Заработано: %d очк.", visit.earned)
	)
end

function PsychoMap.Enter(player: Player)
	if visits[player] then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	visits[player] = {
		earned = 0,
		startedAt = os.clock(),
		-- Вернём ровно туда, откуда забрали, чуть приподняв над землёй
		returnCFrame = CFrame.new(root.Position + Vector3.new(0, 3, 0)),
	}

	psychoTransition:FireClient(player, "enter")
	-- Разворачиваем лицом к корзине, чтобы сразу было видно, куда нести
	teleport(player, CFrame.lookAt(islandSpawn, CONFIG.islandOrigin + Vector3.new(0, 8, 0)))

	notify:FireClient(
		player,
		string.format("Радужный гриб открыл психолес! Очки тут двойные, нужно %d.", CONFIG.targetScore)
	)

	-- Страховка по времени: даже если игрок стоит на месте, подарок
	-- закончится сам и не превратится в место, где он застрял.
	local startedAt = visits[player].startedAt
	task.delay(CONFIG.timeLimitSeconds, function()
		local current = visits[player]
		if current and current.startedAt == startedAt then
			PsychoMap.Exit(player, "Психолес растаял. Пора обратно в обычный лес.")
		end
	end)
end

-- Сколько очков игрок заработал за этот визит. Как только набрано
-- нужное количество — возвращаем его обратно.
function PsychoMap.AddEarned(player: Player, delta: number)
	local visit = visits[player]
	if not visit or delta <= 0 then
		return
	end

	visit.earned += delta

	if visit.earned >= CONFIG.targetScore then
		PsychoMap.Exit(
			player,
			string.format("Психолес закрылся: заработано %d очк. Возвращайся за новым радужным грибом!", visit.earned)
		)
	else
		notify:FireClient(
			player,
			string.format("В психолесу: %d из %d очк.", visit.earned, CONFIG.targetScore)
		)
	end
end

-- Если игрок умер или вышел — визит просто заканчивается, без телепорта
Players.PlayerRemoving:Connect(function(player: Player)
	visits[player] = nil
end)

Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function()
		if visits[player] then
			visits[player] = nil
		end
	end)
end)

buildIsland()

print(
	string.format(
		"PsychoMap v2 готов: остров в %s, появление в стороне от корзины (%s)",
		tostring(CONFIG.islandOrigin),
		tostring(islandSpawn)
	)
)

return PsychoMap
