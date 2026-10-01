--[[
	Tutorial.server.luau

	Первая подсказка новичку. Остальные привязаны к его действиям и
	живут там, где эти действия происходят:
	  * поднял первый гриб   — MushroomSpawner
	  * открыл корзину       — BasketService (GetBasketState)
	  * разобрал корзину     — BasketService (ConfirmBasket)
	  * купил первую лупу    — BasketService (BuyItem)

	Каждая подсказка показывается один раз за всё время игры:
	PlayerData.TryHint хранит показанные в сохранении игрока.
]]

local Players = game:GetService("Players")

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

-- Пауза перед приветствием: пусть игрок сначала увидит лес, а не
-- сообщение поверх экрана загрузки.
local WELCOME_DELAY = 3

local function onCharacterAdded(player: Player)
	-- Подсказка называет направление, а не только действие. Игрок стоит
	-- на пустой поляне, и «ищи грибы» без «куда идти» оставляет его в
	-- растерянности. Лицом он развёрнут к тропе новичка (площадку
	-- разворачивает SortingBasket), так что «впереди» — правда.
	PlayerData.TryHint(player, "welcome", "Грибы растут впереди, в лесу. Иди туда и собирай их на E.", WELCOME_DELAY)
end

local function onPlayerAdded(player: Player)
	if player.Character then
		onCharacterAdded(player)
	end
	player.CharacterAdded:Connect(function()
		onCharacterAdded(player)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
