--[[
	GenerateTrees.luau

	ОДНОРАЗОВЫЙ скрипт для построения леса. Это НЕ игровая логика и не
	часть Rojo-синка — запускается один раз прямо в Studio через
	Command Bar (View -> Command Bar), создаёт деревья в Workspace,
	и они остаются там навсегда как часть карты (сохранятся в .rbxl).

	КАК ЗАПУСТИТЬ:
	1. View -> Command Bar (если не открыт)
	2. Вставь весь этот код туда
	3. Нажми Enter
	4. Подожди — при 150 деревьях это пара секунд
	5. В Explorer появится папка Workspace -> Trees с деревьями

	Если результат не понравился — выдели папку "Trees" в Explorer,
	Delete, поменяй настройки ниже (CONFIG) и запусти заново.
]]

local CONFIG = {
	-- Скрипт ДОБАВЛЯЕТ деревья к тем, что уже стоят в Workspace.Trees,
	-- и ничего не удаляет. Сейчас стоит 100 — это примерно +20% к лесу
	-- из 500 деревьев, чтобы он стал гуще.
	-- Чтобы построить лес с нуля: удали папку Trees в Explorer и
	-- поставь здесь 500-600.
	treeCount = 100,

	-- Радиус вокруг большой корзины, куда деревья не ставим, чтобы
	-- не загородить её. Корзина ищется по тегу SortingBasket.
	stationClearRadius = 22,

	-- Область, где раскидываем деревья (studs, мировые координаты).
	-- Подставь размеры своего сгенерированного травяного поля.
	regionCenter = Vector3.new(0, 0, 0),
	regionSizeX = 800,
	regionSizeZ = 800,

	-- Разброс размера дерева: 1 = обычный, 0.5 = маленькое, 2 = большое.
	minScale = 0.5,
	maxScale = 2.2,

	trunkColor = Color3.fromRGB(92, 64, 45),
	leafColors = {
		Color3.fromRGB(58, 102, 45),
		Color3.fromRGB(70, 120, 55),
		Color3.fromRGB(45, 90, 40),
	},
}

local function raycastGround(x: number, z: number): Vector3?
	local origin = Vector3.new(x, 1000, z)
	local direction = Vector3.new(0, -2000, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }

	local result = workspace:Raycast(origin, direction, params)
	if result then
		return result.Position
	end
	return nil
end

local function createTree(position: Vector3, scale: number): Model
	local tree = Instance.new("Model")
	tree.Name = "Tree"

	-- Ствол
	local trunkHeight = 12 * scale
	local trunkRadius = 1.2 * scale

	local trunk = Instance.new("Part")
	trunk.Name = "Trunk"
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Size = Vector3.new(trunkHeight, trunkRadius * 2, trunkRadius * 2)
	trunk.CFrame = CFrame.new(position + Vector3.new(0, trunkHeight / 2, 0))
		* CFrame.Angles(0, 0, math.rad(90)) -- цилиндр по умолчанию лежит на боку
	trunk.Color = CONFIG.trunkColor
	trunk.Material = Enum.Material.Wood
	trunk.Anchored = true
	trunk.CanCollide = true
	trunk.Parent = tree

	-- Крона — несколько сфер вперемешку, чтобы не было идеальным шаром
	local leafColor = CONFIG.leafColors[math.random(1, #CONFIG.leafColors)]
	local crownRadius = 8 * scale

	for i = 1, 3 do
		local leaf = Instance.new("Part")
		leaf.Name = "Leaves"
		leaf.Shape = Enum.PartType.Ball
		local jitter = crownRadius * 0.4
		local size = crownRadius * (0.75 + math.random() * 0.5)
		leaf.Size = Vector3.new(size, size, size)
		leaf.CFrame = CFrame.new(
			position
				+ Vector3.new(
					(math.random() - 0.5) * jitter,
					trunkHeight + crownRadius * 0.5 + (math.random() - 0.5) * jitter,
					(math.random() - 0.5) * jitter
				)
		)
		leaf.Color = leafColor
		leaf.Material = Enum.Material.Grass
		leaf.Anchored = true
		leaf.CanCollide = false
		leaf.Parent = tree
	end

	tree.PrimaryPart = trunk
	return tree
end

-- Основная генерация
local treesFolder = workspace:FindFirstChild("Trees")
if not treesFolder then
	treesFolder = Instance.new("Folder")
	treesFolder.Name = "Trees"
	treesFolder.Parent = workspace
end

-- Где стоит большая корзина: рядом с ней деревья не ставим
local CollectionService = game:GetService("CollectionService")
local stationPosition = nil
for _, station in CollectionService:GetTagged("SortingBasket") do
	if station:IsA("Model") and station.Parent then
		stationPosition = station:GetPivot().Position
		break
	elseif station:IsA("BasePart") and station.Parent then
		stationPosition = station.Position
		break
	end
end

local function tooCloseToStation(x: number, z: number): boolean
	if not stationPosition then
		return false
	end
	local dx = x - stationPosition.X
	local dz = z - stationPosition.Z
	return math.sqrt(dx * dx + dz * dz) < CONFIG.stationClearRadius
end

local halfX = CONFIG.regionSizeX / 2
local halfZ = CONFIG.regionSizeZ / 2
local placed = 0

for i = 1, CONFIG.treeCount do
	local x = CONFIG.regionCenter.X + (math.random() * 2 - 1) * halfX
	local z = CONFIG.regionCenter.Z + (math.random() * 2 - 1) * halfZ

	if tooCloseToStation(x, z) then
		continue
	end

	local groundPosition = raycastGround(x, z)
	if groundPosition then
		local scale = CONFIG.minScale + math.random() * (CONFIG.maxScale - CONFIG.minScale)
		local tree = createTree(groundPosition, scale)
		tree.Parent = treesFolder
		placed += 1
	end
end

print(
	string.format(
		"Готово: добавлено %d из %d деревьев, всего в лесу %d.",
		placed,
		CONFIG.treeCount,
		#treesFolder:GetChildren()
	)
)

