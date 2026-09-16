--[[
	MushroomSpawner.server.luau

	Раскладывает грибы по точкам-маркерам (Workspace.MushroomSpawns.*)
	и респавнит их через время после сбора.

	ВАЖНО про честность игры: настоящий вид гриба (typeId) хранится
	ТОЛЬКО в серверной таблице activeMushrooms, а не как Attribute на
	самой модели. Attributes реплицируются клиенту и их легко прочитать
	через эксплойт — если положить typeId туда, лупа/угадывание теряют
	смысл, потому что можно скриптом мгновенно узнать все ответы.
	Клиенту видно только цвет модели (визуальный признак вида) — сам
	факт "съедобно/ядовито" не хранится на клиенте вообще.
]]

local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MushroomTypes = require(ReplicatedStorage.Shared.MushroomTypes)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
-- script.Parent, а не ServerScriptService напрямую: Rojo кладёт скрипты
-- во вложенную папку (ServerScriptService.Server), поэтому PlayerData
-- лежит рядом с этим скриптом, а не в корне сервиса.
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

-- Канал коротких сообщений игроку (см. Notifications.client.luau)
local notify = ReplicatedStorage:FindFirstChild("Notify")
if not notify then
	notify = Instance.new("RemoteEvent")
	notify.Name = "Notify"
	notify.Parent = ReplicatedStorage
end

-- Модель -> реальный typeId. Только сервер имеет доступ к этому скрипту,
-- так что эта таблица никогда не покидает сервер.
local activeMushrooms: { [Model]: string } = {}

local spawnsFolder = workspace:WaitForChild("MushroomSpawns")

-- Взвешенный случайный выбор вида по полю rarity
local totalRarity = 0
local typeList = {}
for _, data in MushroomTypes do
	table.insert(typeList, data)
	totalRarity += data.rarity
end

local function pickWeightedType()
	local roll = math.random() * totalRarity
	local cumulative = 0
	for _, data in typeList do
		cumulative += data.rarity
		if roll <= cumulative then
			return data
		end
	end
	return typeList[1] -- на случай погрешности округления
end

-- Строит CFrame-поворот (без позиции) так, чтобы локальная ось Y
-- совпадала с направлением direction. Используется и для ножек, и
-- для шляпок — везде, где нужно "развернуть цилиндр/шляпку вдоль оси".
local function orientationAlong(direction: Vector3): CFrame
	local up = direction.Unit
	local reference = if math.abs(up:Dot(Vector3.new(0, 1, 0))) > 0.95
		then Vector3.new(1, 0, 0)
		else Vector3.new(0, 1, 0)
	local right = reference:Cross(up).Unit
	return CFrame.fromMatrix(Vector3.zero, right, up)
end

-- Создаёт один "гриб" (ножка + шляпка) в точке basePosition, растущий
-- в направлении growDirection. Используется и для одиночных грибов на
-- земле (growDirection = вверх), и для каждого гриба в кластере на
-- стволе (growDirection = веером наружу от коры).
local function createSingleMushroomPart(
	color: Color3,
	basePosition: Vector3,
	growDirection: Vector3,
	stemLength: number,
	capSize: Vector3
): (BasePart, BasePart)
	local rotation = orientationAlong(growDirection)

	local stem = Instance.new("Part")
	stem.Name = "Stem"
	stem.Shape = Enum.PartType.Cylinder
	stem.Size = Vector3.new(stemLength, 0.35, 0.35)
	stem.Color = Color3.fromRGB(235, 220, 195)
	stem.Material = Enum.Material.SmoothPlastic
	stem.Anchored = true
	stem.CanCollide = false
	-- цилиндр по умолчанию лежит вдоль своей локальной X — разворачиваем
	-- ту же ориентацию, что и для Y-выровненных частей, но с поворотом
	-- на 90 градусов, чтобы длина (Size.X) совпала с growDirection
	stem.CFrame = CFrame.new(basePosition + growDirection.Unit * (stemLength / 2))
		* rotation.Rotation
		* CFrame.Angles(0, 0, math.rad(90))

	local cap = Instance.new("Part")
	cap.Name = "Cap"
	cap.Shape = Enum.PartType.Ball
	cap.Size = capSize
	cap.Color = color
	cap.Material = Enum.Material.SmoothPlastic
	cap.Anchored = true
	cap.CanCollide = false
	cap.CFrame = CFrame.new(basePosition + growDirection.Unit * (stemLength + capSize.Y * 0.3))
		* rotation.Rotation

	return stem, cap
end

-- Одиночный гриб на земле, с явно видимой ножкой.
-- Случайный оттенок вокруг базового цвета вида (GameConfig.colorVariation).
-- Цвет — не секрет: игрок и так видит модель, поэтому его можно
-- спокойно хранить на самой модели и отправлять клиенту.
local function varyColor(base: Color3): Color3
	local variation = GameConfig.colorVariation
	local function jitter(amount: number): number
		return (math.random() * 2 - 1) * amount
	end
	local hue, saturation, value = base:ToHSV()
	return Color3.fromHSV(
		(hue + jitter(variation.hue)) % 1,
		math.clamp(saturation + jitter(variation.saturation), 0, 1),
		math.clamp(value + jitter(variation.value), 0, 1)
	)
end

local function createGroundMushroomModel(color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "Mushroom"

	local stem, cap = createSingleMushroomPart(
		color,
		Vector3.zero, -- позицию проставим через PivotTo при спавне
		Vector3.new(0, 1, 0),
		1.1, -- длина ножки
		Vector3.new(1.4, 0.9, 1.4)
	)

	model.PrimaryPart = stem
	stem.Parent = model
	cap.Parent = model

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Собрать"
	prompt.ObjectText = "Гриб" -- специально общее название, не выдаём вид
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = GameConfig.pickupRadius
	prompt.Parent = cap

	return model
end

-- Кластер 2-3 грибов на стволе, растущих веером из одной точки коры —
-- как вешенки на референсе: у каждого своя ножка и шляпка, все сходятся
-- в одном основании.
local function createTrunkMushroomCluster(color: Color3, normal: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Mushroom"

	local up = normal.Unit
	local worldUp = Vector3.new(0, 1, 0)
	local tangentUp = (worldUp - up * up:Dot(worldUp))
	if tangentUp.Magnitude < 0.05 then
		tangentUp = Vector3.new(1, 0, 0) -- если normal почти вертикален
	end
	tangentUp = tangentUp.Unit
	local tangentRight = up:Cross(tangentUp).Unit

	local count = math.random(2, 3)
	local firstCap: BasePart? = nil

	for i = 1, count do
		-- веер: чуть разный наклон вверх и в стороны у каждого гриба
		local tiltUp = math.rad(15 + math.random() * 25)
		local spreadAngle = (i - (count + 1) / 2) * math.rad(35) + (math.random() - 0.5) * math.rad(10)

		local growDirection = (
			up * math.cos(tiltUp)
			+ tangentUp * math.sin(tiltUp) * math.cos(spreadAngle)
			+ tangentRight * math.sin(tiltUp) * math.sin(spreadAngle)
		).Unit

		local stemLength = 0.5 + math.random() * 0.4
		local capScale = 0.85 + math.random() * 0.3

		local stem, cap = createSingleMushroomPart(
			color,
			Vector3.zero,
			growDirection,
			stemLength,
			Vector3.new(1.3 * capScale, 0.6 * capScale, 1.0 * capScale)
		)

		stem.Parent = model
		cap.Parent = model

		if not firstCap then
			firstCap = cap
			model.PrimaryPart = stem
		end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Собрать"
	prompt.ObjectText = "Гриб"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = GameConfig.pickupRadius
	prompt.Parent = firstCap :: BasePart

	return model
end

local function spawnAt(marker: BasePart)
	local typeData = pickWeightedType()
	local color = varyColor(typeData.modelColor)
	local growthType = marker:GetAttribute("GrowthType") or "Ground"

	local model
	if growthType == "Trunk" then
		local normal = marker:GetAttribute("Normal") or Vector3.new(0, 0, 1)
		model = createTrunkMushroomCluster(color, normal)
		-- сдвигаем чуть глубже в кору, чтобы основание кластера выглядело
		-- вросшим, а не висящим в воздухе рядом со стволом
		local embedOffset = -normal.Unit * 0.3
		model:PivotTo(model:GetPivot() + marker.Position + embedOffset)
	else
		model = createGroundMushroomModel(color)
		model:PivotTo(model:GetPivot() + marker.Position)
	end

	model.Parent = workspace

	activeMushrooms[model] = typeData.id

	-- Тег для MushroomInteraction.server.luau — он по нему вешает
	-- обработку наступания и находит цель для пинка.
	CollectionService:AddTag(model, "Mushroom")

	-- Пикап: находим ProximityPrompt (у кластера на стволе их может
	-- быть несколько частей, но prompt всегда один, на первой шляпке)
	-- и вешаем на него обработку сбора гриба.
	local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then
		prompt.Triggered:Connect(function(playerWhoTriggered: Player)
			if not activeMushrooms[model] then
				return -- гриб уже собран кем-то другим ровно в этот момент
			end
			if model:GetAttribute("Consumed") then
				return -- гриб затоптан или пнут, собирать уже нечего
			end

			local added = PlayerData.AddMushroom(playerWhoTriggered, typeData.id, color)
			if added then
				model:Destroy() -- запустит респавн через .Destroying ниже
			else
				notify:FireClient(
					playerWhoTriggered,
					string.format("Корзина полна (%d). Разбери её у стола.", PlayerData.GetCapacity(playerWhoTriggered))
				)
			end
		end)
	end

	-- Когда модель уничтожат (пикап-скрипт вызовет Destroy), запускаем
	-- респавн на этом же маркере через GameConfig.mushroomRespawnTime.
	model.Destroying:Connect(function()
		activeMushrooms[model] = nil
		task.delay(GameConfig.mushroomRespawnTime, function()
			if marker.Parent then -- маркер всё ещё существует
				spawnAt(marker)
			end
		end)
	end)
end

-- Публичная функция для будущего скрипта пикапа — по модели вернуть
-- настоящий вид гриба. Кладём в _G временно; когда появится ModuleScript
-- уровня "MushroomService", перенесём туда нормально.
_G.GetMushroomTypeId = function(model: Model): string?
	return activeMushrooms[model]
end

-- Начальный спавн по всем маркерам
for _, marker in spawnsFolder:GetChildren() do
	if marker:IsA("BasePart") then
		spawnAt(marker)
	end
end

print(string.format("Спавнер запущен: %d точек, %d видов грибов.", #spawnsFolder:GetChildren(), #typeList))
