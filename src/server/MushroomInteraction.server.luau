--[[
	MushroomInteraction.server.luau

	Одна механика: игрок нажал F рядом с грибом -> облачко дыма, гриб
	исчезает. В корзину не попадает, счётчик не меняется. Спавнер сам
	вырастит новый через респавн-таймер.

	Касание (Touched) намеренно НЕ используется: оно срабатывает от
	любого задевания при обычной ходьбе, из-за чего игрок вытаптывал
	грибы, просто проходя мимо. Теперь всё только по явному нажатию.

	ВАЖНО про баланс: цвет дыма намеренно ОДИНАКОВ для всех видов.
	Если сделать его зависящим от ядовитости, наступание превратится
	в бесплатный детектор и обесценит лупы.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local CONFIG = {
	-- Максимальное расстояние, с которого засчитывается наступание
	-- (studs). Сервер проверяет его сам — клиенту тут не доверяем.
	stompRange = 10,

	smokeColor = Color3.fromRGB(170, 220, 130), -- салатовый
	smokeDuration = 0.45, -- сколько эмиттер работает
}

-- RemoteEvent: создаём в коде, чтобы не заводить его руками в Studio
-- (иначе он не попал бы в git вместе с проектом).
local stompEvent = ReplicatedStorage:FindFirstChild("StompMushroom")
if not stompEvent then
	stompEvent = Instance.new("RemoteEvent")
	stompEvent.Name = "StompMushroom"
	stompEvent.Parent = ReplicatedStorage
end

local function emitSmoke(position: Vector3)
	local holder = Instance.new("Part")
	holder.Size = Vector3.new(0.1, 0.1, 0.1)
	holder.Position = position
	holder.Anchored = true
	holder.CanCollide = false
	holder.Transparency = 1
	holder.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(CONFIG.smokeColor)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 2.2),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Rate = 60
	emitter.Parent = holder

	task.delay(CONFIG.smokeDuration, function()
		emitter.Enabled = false
	end)

	Debris:AddItem(holder, 3) -- само уберётся, когда частицы догорят
end

local function stompMushroom(model: Model)
	if model:GetAttribute("Consumed") then
		return
	end
	model:SetAttribute("Consumed", true)

	local cap = model:FindFirstChild("Cap") :: BasePart?
	emitSmoke(cap and cap.Position or model:GetPivot().Position)
	model:Destroy()
end

-- Клиент нажал F: находим ближайший гриб к игроку и топчем.
-- Сам выбор гриба делает СЕРВЕР — клиент только сообщает "я нажал F",
-- иначе можно было бы прислать любую модель с любой дистанции.
stompEvent.OnServerEvent:Connect(function(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local closest: Model? = nil
	local closestDistance = CONFIG.stompRange

	for _, model in CollectionService:GetTagged("Mushroom") do
		if not model:IsA("Model") or not model.Parent then
			continue
		end
		if model:GetAttribute("Consumed") then
			continue
		end
		local distance = (model:GetPivot().Position - root.Position).Magnitude
		if distance < closestDistance then
			closest = model
			closestDistance = distance
		end
	end

	if closest then
		stompMushroom(closest)
	end
end)
