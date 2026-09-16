--[[
	PlayerData.luau

	Серверное состояние игрока: корзина, очки, открытые виды грибов.

	СОХРАНЕНИЕ: используется DataStore, но он работает только если
	  1) плейс опубликован на Roblox, И
	  2) включено Game Settings -> Security -> Enable Studio Access
	     to API Services

	Пока это не сделано, все обращения к DataStore завёрнуты в pcall и
	молча игнорируются — игра работает, просто прогресс не переживает
	перезапуск. Как только опубликуешь плейс и включишь галочку,
	сохранение заработает само, менять код не нужно.
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Baskets = require(ReplicatedStorage.Shared.Baskets)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Tools = require(ReplicatedStorage.Shared.Tools)

export type PlayerState = {
	-- score — это одновременно счёт и валюта: разделять их не за чем,
	-- источник дохода и предмет трат у нас один и тот же.
	score: number,
	basketId: string,
	slots: { GameConfig.BasketSlot },
	ownedTools: { string },
	-- Виды, которые игрок уже разобрал хотя бы раз (верно или ошибочно —
	-- открывается в обоих случаях). Ключ = typeId, значение = true.
	discoveredTypes: { [string]: boolean },
	-- Сколько грибов игрок уже разобрал за всё время. От этого числа
	-- растёт шанс порчи (GameConfig.spoilage).
	mushroomsSorted: number,
	-- Насколько игрок "выучил" каждый вид: сколько раз вид прошёл
	-- через разбор. Название видно при >= GameConfig.namesAfterConfirms.
	speciesKnowledge: { [string]: number },
}

local PlayerData = {}

-- Сигнал "состояние игрока изменилось" — на него подписывается
-- BasketService, чтобы обновлять UI ровно тогда, когда что-то реально
-- поменялось, а не опрашивать всех игроков по таймеру.
local changedEvent = Instance.new("BindableEvent")
PlayerData.Changed = changedEvent.Event

local dataByPlayer: { [Player]: PlayerState } = {}

-- pcall: если API Services выключены, GetDataStore сам по себе не падает,
-- но любые Get/Set падают. Держим store в переменной и проверяем перед
-- использованием.
local store
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("MushroomGamePlayerData_v1")
	end)
	store = if ok then result else nil
end

local function makeDefaultState(): PlayerState
	return {
		score = 0,
		basketId = GameConfig.startingBasketId,
		slots = {},
		ownedTools = {},
		discoveredTypes = {},
		mushroomsSorted = 0,
		speciesKnowledge = {},
	}
end

-- Старые сохранения могли содержать анализаторы, которых больше нет.
-- Меняем их на лупы того же уровня и добавляем пропущенные "ступеньки",
-- чтобы магазин не показывал x20 купленной, а x10 — нет.
local LEGACY_TOOLS = {
	ANALYZER_MK1 = "MAGNIFIER_X10",
	ANALYZER_MK2 = "MAGNIFIER_X20",
}

local function migrateTools(saved: { any }): { string }
	local result = {}
	local function add(toolId: string)
		local tool = Tools[toolId]
		if not tool or table.find(result, toolId) then
			return
		end
		if tool.previous then
			add(tool.previous)
		end
		table.insert(result, toolId)
	end
	for _, toolId in saved do
		if type(toolId) == "string" then
			add(LEGACY_TOOLS[toolId] or toolId)
		end
	end
	return result
end

local function setupLeaderstats(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local mushroomCount = Instance.new("IntValue")
	mushroomCount.Name = "В корзине"
	mushroomCount.Value = 0
	mushroomCount.Parent = leaderstats

	local score = Instance.new("IntValue")
	score.Name = "Очки"
	score.Value = 0
	score.Parent = leaderstats
end

local function refreshLeaderstats(player: Player)
	local data = dataByPlayer[player]
	local leaderstats = player:FindFirstChild("leaderstats")
	if not data then
		return
	end
	if leaderstats then
		leaderstats["В корзине"].Value = #data.slots
		leaderstats["Очки"].Value = data.score
	end
	changedEvent:Fire(player)
end

PlayerData.RefreshLeaderstats = refreshLeaderstats

local function loadFromStore(player: Player): PlayerState
	if not store then
		return makeDefaultState()
	end

	local ok, saved = pcall(function()
		return store:GetAsync("player_" .. player.UserId)
	end)

	if not ok or type(saved) ~= "table" then
		-- Либо API Services выключены (локальный тест), либо игрок новый.
		-- В обоих случаях просто стартуем с чистого состояния.
		return makeDefaultState()
	end

	local state = makeDefaultState()
	-- Сохраняем только долгоживущие поля. Корзина (slots) намеренно НЕ
	-- сохраняется: собранные, но не разобранные грибы пропадают при
	-- выходе — так проще и не создаёт эксплойтов с дублированием.
	state.score = tonumber(saved.score) or 0
	state.basketId = if Baskets[saved.basketId] then saved.basketId else GameConfig.startingBasketId
	if type(saved.ownedTools) == "table" then
		state.ownedTools = migrateTools(saved.ownedTools)
	end
	state.mushroomsSorted = tonumber(saved.mushroomsSorted) or 0
	if type(saved.speciesKnowledge) == "table" then
		for typeId, value in saved.speciesKnowledge do
			if type(typeId) == "string" and type(value) == "number" then
				state.speciesKnowledge[typeId] = value
			end
		end
	end
	if type(saved.discoveredTypes) == "table" then
		state.discoveredTypes = saved.discoveredTypes
	end
	return state
end

local function saveToStore(player: Player)
	if not store then
		return
	end
	local data = dataByPlayer[player]
	if not data then
		return
	end

	pcall(function()
		store:SetAsync("player_" .. player.UserId, {
			score = data.score,
			basketId = data.basketId,
			ownedTools = data.ownedTools,
			discoveredTypes = data.discoveredTypes,
			mushroomsSorted = data.mushroomsSorted,
			speciesKnowledge = data.speciesKnowledge,
		})
	end)
end

function PlayerData.Init(player: Player)
	setupLeaderstats(player)
	dataByPlayer[player] = loadFromStore(player)
	refreshLeaderstats(player)
end

function PlayerData.Remove(player: Player)
	saveToStore(player)
	dataByPlayer[player] = nil
end

function PlayerData.Get(player: Player): PlayerState?
	return dataByPlayer[player]
end

function PlayerData.GetCapacity(player: Player): number
	local data = dataByPlayer[player]
	if not data then
		return 0
	end
	local basket = Baskets[data.basketId]
	return basket and basket.capacity or 0
end

-- Текущий шанс, что подобранный гриб окажется испорченным (0..1).
function PlayerData.GetSpoilageChance(player: Player): number
	local data = dataByPlayer[player]
	if not data then
		return 0
	end
	local cfg = GameConfig.spoilage
	local steps = math.floor(data.mushroomsSorted / cfg.mushroomsPerStep)
	if steps < cfg.graceSteps then
		return 0
	end
	return math.min(cfg.maxChance, (steps - cfg.graceSteps + 1) * cfg.chancePerStep)
end

-- Лучшая купленная лупа (или nil, если лупы нет).
function PlayerData.GetBestTool(player: Player): Tools.ToolData?
	local data = dataByPlayer[player]
	if not data then
		return nil
	end
	local best = nil
	for _, toolId in data.ownedTools do
		local tool = Tools[toolId]
		if tool and (best == nil or tool.level > best.level) then
			best = tool
		end
	end
	return best
end

-- Случайный размер следа по весам GameConfig.spoilage.sizeWeights
local function pickDefectSize(): number
	local weights = GameConfig.spoilage.sizeWeights
	local total = 0
	for _, weight in weights do
		total += weight
	end
	local roll = math.random() * total
	for size, weight in weights do
		roll -= weight
		if roll <= 0 then
			return size
		end
	end
	return #weights
end

function PlayerData.AddMushroom(player: Player, typeId: string, color: Color3): boolean
	local data = dataByPlayer[player]
	if not data then
		return false
	end

	if #data.slots >= PlayerData.GetCapacity(player) then
		return false
	end

	-- Порча решается в момент подбора и только на сервере: один и тот
	-- же гриб в лесу для разных игроков может оказаться разным, и
	-- заранее узнать это из модели в мире нельзя.
	local defect, defectSize = nil, nil
	if math.random() < PlayerData.GetSpoilageChance(player) then
		defect = if math.random() < 0.5 then "mold" else "worms"
		defectSize = pickDefectSize()
	end

	local slot: GameConfig.BasketSlot = {
		instanceId = HttpService:GenerateGUID(false),
		typeId = typeId,
		pickedUpAt = os.clock(),
		color = color,
		defect = defect,
		defectSize = defectSize,
		inspectedLevel = 0,
		kept = nil,
	}
	table.insert(data.slots, slot)

	refreshLeaderstats(player)
	return true
end

-- Изменение очков с полом на нуле: счёт никогда не уходит в минус.
function PlayerData.AddScore(player: Player, delta: number)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	data.score = math.max(0, data.score + delta)
	refreshLeaderstats(player)
end

-- Выучен ли вид настолько, чтобы лупа показывала его название
function PlayerData.IsSpeciesKnown(player: Player, typeId: string): boolean
	local data = dataByPlayer[player]
	if not data then
		return false
	end
	return (data.speciesKnowledge[typeId] or 0) >= GameConfig.namesAfterConfirms
end

-- Вызывается для каждого гриба, прошедшего разбор.
--   * обычно: +1 к знанию вида (и съедобного, и ядовитого — на ошибках
--     тоже учатся);
--   * но если игрок оставил ядовитый гриб, название которого уже было
--     видно, — значит, не запомнил: вид забывается.
function PlayerData.LearnSpecies(player: Player, typeId: string, isEdible: boolean)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	if not isEdible and PlayerData.IsSpeciesKnown(player, typeId) then
		data.speciesKnowledge[typeId] = 0
	else
		data.speciesKnowledge[typeId] = (data.speciesKnowledge[typeId] or 0) + 1
	end
end

function PlayerData.DiscoverType(player: Player, typeId: string)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	data.discoveredTypes[typeId] = true
end

Players.PlayerAdded:Connect(PlayerData.Init)
Players.PlayerRemoving:Connect(PlayerData.Remove)

-- Последний шанс сохраниться, если сервер выключается (например, все
-- игроки вышли одновременно и BindToClose обгоняет PlayerRemoving).
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		saveToStore(player)
	end
end)

for _, player in Players:GetPlayers() do
	if not dataByPlayer[player] then
		PlayerData.Init(player)
	end
end

return PlayerData
