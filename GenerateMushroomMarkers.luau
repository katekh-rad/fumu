--[[
	GenerateMushroomMarkers.luau (v2)

	ОДНОРАЗОВЫЙ скрипт, запускается через Command Bar ПОСЛЕ того, как
	деревья уже стоят в Workspace.Trees.

	Теперь у каждого маркера есть Attribute "GrowthType":
	  "Ground" — гриб на земле у корней (как раньше)
	  "Trunk"  — гриб растёт прямо на коре, торчит в сторону от ствола
	             (для Trunk-маркеров также записан Attribute "Normal" —
	             направление "наружу" от ствола, для правильной ориентации)

	КАК ЗАПУСТИТЬ:
	Если запускала v1 раньше — удали старую папку MushroomSpawns
	перед повторным запуском (Explorer -> ПКМ -> Delete), иначе
	получишь маркеры от обоих запусков сразу.
]]

local CONFIG = {
	minPerTree = 1,
	maxPerTree = 3,

	-- Шанс, что у дерева ВООБЩЕ будут грибы (1 = у каждого дерева,
	-- 0.5 = только у половины). Уменьши, если маркеров слишком много.
	treeHasSpawnsChance = 1,

	-- Из тех грибов, что есть у дерева — какая доля растёт на стволе,
	-- а не на земле
	trunkGrowthChance = 0.35,

	-- Наземные маркеры: расстояние от ствола (studs)
	groundMinRadius = 3,
	groundMaxRadius = 7,

	-- Маркеры на стволе: на какой высоте вдоль ствола (доля от общей
	-- высоты, 0 = у самой земли, 1 = у кроны)
	trunkMinHeightFraction = 0.1,
	trunkMaxHeightFraction = 0.65,
}

local treesFolder = workspace:FindFirstChild("Trees")
if not treesFolder then
	error("Workspace.Trees не найден — сначала запусти GenerateTrees.luau")
end

local markersFolder = workspace:FindFirstChild("MushroomSpawns")
if markersFolder then
	markersFolder:Destroy() -- чистим предыдущий запуск, чтобы не дублировалось
end
markersFolder = Instance.new("Folder")
markersFolder.Name = "MushroomSpawns"
markersFolder.Parent = workspace

local function raycastGround(x: number, z: number): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }

	local result = workspace:Raycast(Vector3.new(x, 1000, z), Vector3.new(0, -2000, 0), params)
	if result then
		return result.Position
	end
	return nil
end

local markerIndex = 0

local function createGroundMarker(treeBase: Vector3)
	local angle = math.random() * math.pi * 2
	local radius = CONFIG.groundMinRadius + math.random() * (CONFIG.groundMaxRadius - CONFIG.groundMinRadius)

	local targetX = treeBase.X + math.cos(angle) * radius
	local targetZ = treeBase.Z + math.sin(angle) * radius

	local groundPosition = raycastGround(targetX, targetZ)
	if not groundPosition then
		return
	end

	markerIndex += 1
	local marker = Instance.new("Part")
	marker.Name = "SpawnPoint_" .. markerIndex
	marker.Size = Vector3.new(1, 1, 1)
	marker.Position = groundPosition
	marker.Anchored = true
	marker.CanCollide = false
	marker.Transparency = 1
	marker:SetAttribute("GrowthType", "Ground")
	marker.Parent = markersFolder
end

local function createTrunkMarker(treeBase: Vector3, trunkHeight: number, trunkRadius: number)
	local angle = math.random() * math.pi * 2
	local heightFraction = CONFIG.trunkMinHeightFraction
		+ math.random() * (CONFIG.trunkMaxHeightFraction - CONFIG.trunkMinHeightFraction)

	local normal = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local surfacePosition = treeBase
		+ Vector3.new(0, trunkHeight * heightFraction, 0)
		+ normal * trunkRadius

	markerIndex += 1
	local marker = Instance.new("Part")
	marker.Name = "SpawnPoint_" .. markerIndex
	marker.Size = Vector3.new(1, 1, 1)
	marker.Position = surfacePosition
	marker.Anchored = true
	marker.CanCollide = false
	marker.Transparency = 1
	marker:SetAttribute("GrowthType", "Trunk")
	marker:SetAttribute("Normal", normal)
	marker.Parent = markersFolder
end

for _, tree in treesFolder:GetChildren() do
	if not (tree:IsA("Model") and tree.PrimaryPart) then
		continue
	end

	if math.random() > CONFIG.treeHasSpawnsChance then
		continue -- у этого дерева не будет грибов вообще
	end

	local trunk = tree.PrimaryPart
	local trunkHeight = trunk.Size.X -- см. GenerateTrees: Size.X = высота ствола
	local trunkRadius = trunk.Size.Y / 2 -- Size.Y = Size.Z = диаметр ствола
	local treeBase = trunk.Position - Vector3.new(0, trunkHeight / 2, 0)

	local count = math.random(CONFIG.minPerTree, CONFIG.maxPerTree)

	for _ = 1, count do
		if math.random() < CONFIG.trunkGrowthChance then
			createTrunkMarker(treeBase, trunkHeight, trunkRadius)
		else
			createGroundMarker(treeBase)
		end
	end
end

print(string.format("Готово: создано %d маркеров вокруг %d деревьев.", markerIndex, #treesFolder:GetChildren()))
