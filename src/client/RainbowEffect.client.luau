--[[
	RainbowEffect.client.luau

	Переливание цвета для всего, что помечено тегом "Rainbow": шляпка
	радужного гриба в обычном лесу и весь психолес целиком.

	Считается на клиенте, а не на сервере: цвет — чистая картинка, и
	гонять его по сети каждый кадр незачем. Сервер только ставит тег.

	Переход плавный и медленный (полный круг за RainbowEffect.period
	секунд), без резких вспышек: быстрое мигание неприятно глазам и
	опасно для людей с светочувствительностью.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local player = Players.LocalPlayer

local CONFIG = {
	-- За сколько секунд цвет проходит полный круг
	period = 6,
	-- Насколько сдвинут оттенок у соседних частей: из-за этого лес
	-- переливается волной, а не мигает целиком
	spatialShift = 0.006,
	-- За сколько секунд круг спирали доходит от края до центра
	spiralPeriod = 2.5,
	saturation = 0.85,
	brightness = 1,
}

-- Подкрашиваем весь экран, пока игрок на психоострове. Эффект локальный:
-- другие игроки его не видят.
local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.Name = "PsychoVision"
colorCorrection.Enabled = false
colorCorrection.Saturation = 0
colorCorrection.Contrast = 0
colorCorrection.Parent = Lighting

local islandOrigin = GameConfig.psycho.islandOrigin
local islandRadius = GameConfig.psycho.islandRadius + 20

local function isOnIsland(): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local flat = Vector3.new(root.Position.X - islandOrigin.X, 0, root.Position.Z - islandOrigin.Z)
	return flat.Magnitude < islandRadius and math.abs(root.Position.Y - islandOrigin.Y) < 200
end

RunService.RenderStepped:Connect(function(_deltaTime: number)
	local time = os.clock() / CONFIG.period

	for _, part in CollectionService:GetTagged("Rainbow") do
		if not part:IsA("BasePart") or not part.Parent then
			continue
		end

		-- Оттенок зависит от времени и от положения части в мире —
		-- получается бегущая волна цвета.
		local phase = (part.Position.X + part.Position.Z * 0.7) * CONFIG.spatialShift
		part.Color = Color3.fromHSV((time + phase) % 1, CONFIG.saturation, CONFIG.brightness)
	end

	-- Спирали на шляпках грибов психолеса: круги постоянно сжимаются к
	-- центру, и шляпка выглядит как воронка, уходящая внутрь. Один
	-- цикл за CONFIG.spiralPeriod секунд — медленно, без ряби.
	local funnel = (os.clock() / CONFIG.spiralPeriod) % 1
	for _, part in CollectionService:GetTagged("Spiral") do
		if not part:IsA("BasePart") or not part.Parent then
			continue
		end
		for _, gui in part:GetChildren() do
			if not gui:IsA("SurfaceGui") then
				continue
			end
			local holder = gui:FindFirstChild("Holder")
			if not holder then
				continue
			end

			local rings = {}
			for _, child in holder:GetChildren() do
				if child:IsA("Frame") and child.Name:match("^Ring") then
					table.insert(rings, child)
				end
			end
			table.sort(rings, function(a, b)
				return a.Name < b.Name
			end)

			for index, ring in rings do
				-- У каждого круга своя фаза: пока один исчезает в
				-- центре, снаружи уже появляется следующий
				local phase = ((index - 1) / #rings + funnel) % 1
				-- Максимум меньше единицы: полотно спирали теперь
				-- прозрачное, и круг шире шляпки торчал бы чёрной дугой
				-- за её краем.
				local scale = 0.9 * (1 - phase)
				ring.Size = UDim2.fromScale(scale, scale)
				ring.Visible = scale > 0.04

				local stroke = ring:FindFirstChildWhichIsA("UIStroke")
				if stroke then
					-- Чёрная линия толстая: так спираль читается с
					-- расстояния и контраст с ярким цветом резче.
					-- Ближе к центру тоньше — это и даёт глубину.
					stroke.Thickness = math.max(2, 16 * scale)
				end
			end
		end
	end

	-- Плавно включаем и выключаем подкраску экрана
	local target = if isOnIsland() then 0.45 else 0
	colorCorrection.Saturation += (target - colorCorrection.Saturation) * 0.05
	colorCorrection.Enabled = colorCorrection.Saturation > 0.01

	if colorCorrection.Enabled then
		-- Очень медленный сдвиг оттенка всей картинки: «кружится
		-- голова», но без мельтешения
		local tint = Color3.fromHSV((time * 0.25) % 1, 0.25, 1)
		colorCorrection.TintColor = tint:Lerp(Color3.new(1, 1, 1), 0.7)
	end
end)
