--[[
	ZoneService.server.luau

	Сообщает игроку, когда он переходит из одной части леса в другую
	("Опушка" -> "Лес" -> "Чаща"). Сами правила зон лежат в
	ReplicatedStorage.Shared.Zones и используются ещё и спавнером.

	Почему на сервере, а не на клиенте: позиции игроков тут и так есть,
	а канал уведомлений (RemoteEvent "Notify") уже готов. Отдельная
	клиентская логика для этого не нужна.

	Опрос раз в секунду: зона меняется от ходьбы пешком, чаще смотреть
	незачем.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Zones = require(ReplicatedStorage.Shared.Zones)

local CHECK_INTERVAL = 1

local notify = ReplicatedStorage:FindFirstChild("Notify")
if not notify then
	notify = Instance.new("RemoteEvent")
	notify.Name = "Notify"
	notify.Parent = ReplicatedStorage
end

-- Зона, в которой игрок был на прошлой проверке
local lastZoneId: { [Player]: string } = {}

Players.PlayerRemoving:Connect(function(player: Player)
	lastZoneId[player] = nil
end)

-- Если игрок умер и возродился, пусть сообщение придёт заново
Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function()
		lastZoneId[player] = nil
	end)
end)

task.spawn(function()
	-- Ждём корзину: без неё зоны считались бы от начала координат
	local center = Zones.GetCenter()
	while center == Vector3.zero do
		task.wait(1)
		center = Zones.GetCenter()
	end

	while true do
		task.wait(CHECK_INTERVAL)

		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				continue
			end

			local zone = Zones.GetByPosition(root.Position, center)
			if lastZoneId[player] ~= zone.id then
				lastZoneId[player] = zone.id
				notify:FireClient(player, zone.enterMessage)
			end
		end
	end
end)
