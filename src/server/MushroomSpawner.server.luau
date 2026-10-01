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
local Zones = require(ReplicatedStorage.Shared.Zones)
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

local typeList = {}
for _, data in MushroomTypes do
	table.insert(typeList, data)
end

-- Центр зон (большая корзина) считаем один раз при старте: во время
-- игры она не переезжает.
--
-- Но корзину строит другой серверный скрипт (SortingBasket), а порядок
-- запуска серверных скриптов Roblox не гарантирует. Если мы оказались
-- первыми, GetCenter вернёт ноль — и поляна, и тропа посчитаются вокруг
-- начала координат, то есть неизвестно где. Поэтому ждём корзину.
local zoneCenter = Zones.GetCenter()
if zoneCenter == Vector3.zero then
	for _ = 1, 100 do
		task.wait(0.1)
		zoneCenter = Zones.GetCenter()
		if zoneCenter ~= Vector3.zero then
			break
		end
	end
	if zoneCenter == Vector3.zero then
		warn("MushroomSpawner: корзина не нашлась за 10 секунд, зоны считаются от начала координат")
	end
end

-- Веса видов внутри одной зоны: rarity вида, умноженная на множитель
-- зоны. Считаем по одному разу на зону, а не на каждый гриб.
local zoneWeights: { [string]: { total: number, weights: { number } } } = {}
for _, zoneId in Zones.Order do
	local zone = Zones.Data[zoneId]
	local weights = {}
	local total = 0
	for index, data in typeList do
		local weight = data.rarity * (zone.rarityMultipliers[data.id] or 1)
		weights[index] = weight
		total += weight
	end
	zoneWeights[zoneId] = { total = total, weights = weights }
end

-- Взвешенный случайный выбор вида с учётом зоны
local function pickWeightedType(zone)
	local prepared = zoneWeights[zone.id]
	local roll = math.random() * prepared.total
	local cumulative = 0
	for index, weight in prepared.weights do
		cumulative += weight
		if roll <= cumulative then
			return typeList[index]
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

-- Далеко ли маркер от большой корзины (по горизонтали)
local function distanceFromStation(position: Vector3): number
	return (Vector3.new(position.X, 0, position.Z) - Vector3.new(zoneCenter.X, 0, zoneCenter.Z)).Magnitude
end

-- Точки тропы новичка спавнер ставит сам (см. createTrailMarkers), и
-- узнаёт их по имени.
local TRAIL_PREFIX = "TrailPoint_"

local function isTrailMarker(marker: Instance): boolean
	return string.sub(marker.Name, 1, #TRAIL_PREFIX) == TRAIL_PREFIX
end

-- Маркеры на поляне у корзины игнорируем: там грибы не растут, иначе
-- корзину можно было бы набрать, не отходя от места разбора.
--
-- Точки тропы — исключение: их мы поставили осознанно, чтобы игрок с
-- первого кадра видел, куда идти. Раньше здесь была геометрия с углом
-- и радиусом, но она отсеивала и сами точки тропы, если те попадали не
-- туда, куда ожидалось. Проверка по имени надёжнее.
local function isOnClearing(marker: BasePart): boolean
	if isTrailMarker(marker) then
		return false
	end
	return distanceFromStation(marker.Position) < Zones.clearRadius
end

local function spawnAt(marker: BasePart)
	if isOnClearing(marker) then
		return
	end

	-- Зону берём по маркеру: она не меняется, пока маркер стоит на месте
	local zone = Zones.GetByPosition(marker.Position, zoneCenter)

	-- Раз в сотню грибов вместо обычного вырастает радужный: он всегда
	-- съедобный, а при разборе открывает психолес (см. PsychoMap).
	local isRainbow = math.random() < GameConfig.psycho.rainbowChance
	local typeData = if isRainbow then MushroomTypes.RAINBOW_CAP else pickWeightedType(zone)
	-- Радужному оттенок не разбрасываем: его цвет перебирает клиент
	local color = if isRainbow then typeData.modelColor else varyColor(typeData.modelColor)
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

	if isRainbow then
		-- Тег ловит клиентский RainbowEffect и переливает шляпку
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Name == "Cap" then
				part.Material = Enum.Material.Neon
				CollectionService:AddTag(part, "Rainbow")
			end
		end
	end

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

			-- Радужный гриб никогда не бывает испорченным
			local spoilage = if isRainbow then 0 else zone.spoilageMultiplier
			local added = PlayerData.AddMushroom(playerWhoTriggered, typeData.id, color, spoilage)
			if added then
				-- Первый в жизни гриб: подсказываем, что с ним делать
				PlayerData.TryHint(
					playerWhoTriggered,
					"first_pickup",
					"Разбирать грибы носи к большой корзине на поляне.",
					1.5
				)
				model:Destroy() -- запустит респавн через .Destroying ниже
			else
				notify:FireClient(
					playerWhoTriggered,
					string.format("Корзина полна (%d). Разбери её у большой корзины.", PlayerData.GetCapacity(playerWhoTriggered))
				)
			end
		end)
	end

	-- Когда модель уничтожат (пикап-скрипт вызовет Destroy), запускаем
	-- респавн на этом же маркере через GameConfig.mushroomRespawnTime.
	model.Destroying:Connect(function()
		activeMushrooms[model] = nil
		task.delay(GameConfig.mushroomRespawnTime * zone.respawnMultiplier, function()
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

-- Тропа новичка: дорожка грибов от площадки появления в лес.
--
-- Точки спавнер создаёт сам, а не ищет среди маркеров у деревьев:
-- маркеры стоят только вокруг стволов, и в нужное место дерево может
-- вообще не попасть.
--
-- Отсчёт идёт от самой площадки появления, а не от центра корзины по
-- заданному направлению. Так тропа гарантированно начинается там, где
-- реально стоит игрок, и её не надо согласовывать с тем, куда
-- SortingBasket поставил площадку.
--
-- Точки живут только в памяти сервера: в файл места не попадают и при
-- каждом запуске создаются заново.
local function createTrailMarkers(): number
	local trail = Zones.trail
	if not trail or (trail.count or 0) <= 0 then
		return 0
	end

	-- Площадку ставит SortingBasket, и он может запуститься позже нас
	local pad = workspace:WaitForChild("BasketSpawn", 10)
	if not pad or not pad:IsA("BasePart") then
		warn("MushroomSpawner: BasketSpawn не найден, тропа новичка не построена")
		return 0
	end

	-- От корзины наружу: туда же развёрнута площадка, туда и смотрит игрок
	local outward = Vector3.new(pad.Position.X - zoneCenter.X, 0, pad.Position.Z - zoneCenter.Z)
	if outward.Magnitude < 0.01 then
		warn("MushroomSpawner: площадка появления совпала с корзиной, тропа новичка не построена")
		return 0
	end
	outward = outward.Unit
	-- Поперечное направление для петляния
	local sideways = Vector3.new(-outward.Z, 0, outward.X)

	-- Перезапуск сервера не должен плодить тропу
	for _, child in spawnsFolder:GetChildren() do
		if isTrailMarker(child) then
			child:Destroy()
		end
	end

	-- Целимся в рельеф, как это делает генератор маркеров: деревья и
	-- шляпки грибов луч должен игнорировать, иначе гриб повиснет в
	-- воздухе на кроне.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }

	local created = 0

	for index = 1, trail.count do
		local along = trail.startOffset + (index - 1) * trail.spacing
		-- Точки уходят то влево, то вправо: тропа петляет
		local side = if index % 2 == 0 then 1 else -1
		local wobble = trail.wobbleStuds * side * (0.3 + math.random() * 0.7)

		local point = pad.Position + outward * along + sideways * wobble
		local hit = workspace:Raycast(Vector3.new(point.X, point.Y + 500, point.Z), Vector3.new(0, -2000, 0), params)
		-- Без рельефа под точкой ставим гриб на уровень площадки: лучше
		-- чуть выше травы, чем отсутствие тропы.
		local position = if hit then hit.Position else Vector3.new(point.X, pad.Position.Y, point.Z)

		local marker = Instance.new("Part")
		marker.Name = TRAIL_PREFIX .. index
		marker.Size = Vector3.new(1, 1, 1)
		marker.Position = position
		marker.Anchored = true
		marker.CanCollide = false
		marker.Transparency = 1
		marker:SetAttribute("GrowthType", "Ground")
		marker.Parent = spawnsFolder
		created += 1
	end

	return created
end

local trailCount = createTrailMarkers()

-- Начальный спавн по всем маркерам
for _, marker in spawnsFolder:GetChildren() do
	if marker:IsA("BasePart") then
		spawnAt(marker)
	end
end

-- Сколько маркеров попало в каждую зону — удобно проверять после
-- перегенерации леса, не бегая по карте.
local zoneCounts = {}
local skipped = 0
for _, marker in spawnsFolder:GetChildren() do
	if marker:IsA("BasePart") then
		if isOnClearing(marker) then
			skipped += 1
		else
			local zone = Zones.GetByPosition(marker.Position, zoneCenter)
			zoneCounts[zone.name] = (zoneCounts[zone.name] or 0) + 1
		end
	end
end

local zoneReport = {
	string.format("поляна у корзины пропущена: %d", skipped),
	-- По этой цифре видно, появилась тропа или нет: если 0, значит
	-- Zones.trail выключен или count = 0.
	string.format("тропа новичка: %d", trailCount),
}
for _, zoneId in Zones.Order do
	local zone = Zones.Data[zoneId]
	table.insert(zoneReport, string.format("%s: %d", zone.name, zoneCounts[zone.name] or 0))
end

print(
	string.format(
		"Спавнер запущен: %d точек (%s), %d видов грибов.",
		#spawnsFolder:GetChildren(),
		table.concat(zoneReport, ", "),
		#typeList
	)
)
