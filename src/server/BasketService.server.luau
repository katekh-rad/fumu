--[[
	BasketService.server.luau

	Вся серверная логика корзины. Клиент только показывает UI и шлёт
	намерения ("выбросить этот гриб", "подтвердить") — все решения и
	подсчёт очков происходят ЗДЕСЬ. Клиенту нельзя доверять: иначе
	можно было бы прислать "я угадал всё верно, дай 100 очков".

	Правила подсчёта при подтверждении:
	  * съедобный вид БЕЗ порчи                -> +1 очко
	  * ядовитый вид или гриб с плесенью/червями -> -1 очко
	  * итоговый счёт не может уйти ниже нуля
	  * название вида видно только с лупой и только когда вид выучен
	    (прошёл разбор GameConfig.namesAfterConfirms раз); оставил
	    ядовитый гриб с уже известным названием — вид забывается
	  * съедобность вида клиенту не сообщается никогда — её игрок
	    запоминает сам
	  * разобранные грибы уходят из корзины, неотмеченные остаются
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local MushroomTypes = require(ReplicatedStorage.Shared.MushroomTypes)
local Tools = require(ReplicatedStorage.Shared.Tools)
local Baskets = require(ReplicatedStorage.Shared.Baskets)
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

-- Насколько близко к столу надо стоять, чтобы подтвердить разбор (studs)
local STATION_RANGE = 18

-- Проверяет, стоит ли игрок у стола для разбора. Инструменты работают
-- где угодно, а вот подтверждение — только здесь: именно ходьба
-- туда-обратно делает большую корзину ценной.
local function isNearStation(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end

	for _, station in CollectionService:GetTagged("SortingStation") do
		if not station:IsA("Model") or not station.Parent then
			continue
		end
		if (station:GetPivot().Position - root.Position).Magnitude <= STATION_RANGE then
			return true
		end
	end
	return false
end

-- Remotes создаём в коде, чтобы не заводить их руками в Studio.
local function ensureRemote(className: string, name: string): Instance
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then
		return existing
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = ReplicatedStorage
	return remote
end

local getBasketState = ensureRemote("RemoteFunction", "GetBasketState") :: RemoteFunction
local discardMushroom = ensureRemote("RemoteEvent", "DiscardMushroom") :: RemoteEvent
local confirmBasket = ensureRemote("RemoteEvent", "ConfirmBasket") :: RemoteEvent
local useToolOnSlot = ensureRemote("RemoteEvent", "UseToolOnSlot") :: RemoteEvent
local markMushroom = ensureRemote("RemoteEvent", "MarkMushroom") :: RemoteEvent
local buyItem = ensureRemote("RemoteEvent", "BuyItem") :: RemoteEvent
local purchaseResult = ensureRemote("RemoteEvent", "PurchaseResult") :: RemoteEvent
local basketUpdated = ensureRemote("RemoteEvent", "BasketUpdated") :: RemoteEvent
local confirmResult = ensureRemote("RemoteEvent", "BasketConfirmResult") :: RemoteEvent

-- Готовит безопасный для клиента снимок корзины. Клиенту уходит
-- только то, что игрок "видит":
--   * название вида — если вид выучен И у игрока есть лупа. Без лупы
--     названий нет вообще, только цвет шляпки. Съедобность — никогда.
--   * порча — только если её разглядели лупой достаточной силы.
-- Остальное остаётся на сервере, иначе через эксплойт можно было бы
-- прочитать ответ до разбора.
local function buildClientState(player: Player)
	local data = PlayerData.Get(player)
	if not data then
		return nil
	end

	local bestTool = PlayerData.GetBestTool(player)

	local slots = {}
	for _, slot in data.slots do
		local typeData = MushroomTypes[slot.typeId]
		local known = bestTool ~= nil and PlayerData.IsSpeciesKnown(player, slot.typeId)
		local defectVisible = slot.defect ~= nil
			and slot.defectSize ~= nil
			and slot.defectSize <= slot.inspectedLevel

		table.insert(slots, {
			instanceId = slot.instanceId,
			-- вид известен игроку: есть лупа и вид выучен
			discovered = known,
			name = if known then typeData.name else nil,
			-- цвет виден всегда: это то, что игрок и так видит глазами
			color = slot.color or typeData.modelColor,
			-- каким уровнем лупы уже осматривали (0 = не осматривали)
			inspectedLevel = slot.inspectedLevel,
			-- найденная порча (nil = не видно или её нет)
			-- Размер следа клиенту не нужен: картинку определяет лупа.
			defect = if defectVisible then slot.defect else nil,
			-- решение игрока: отмечен ли гриб как "беру"
			kept = slot.kept,
		})
	end

	return {
		slots = slots,
		capacity = PlayerData.GetCapacity(player),
		basketId = data.basketId,
		basketName = Baskets[data.basketId].name,
		score = data.score,
		ownedTools = data.ownedTools,
		bestToolId = if bestTool then bestTool.id else nil,
		nearStation = isNearStation(player),
	}
end

local function pushUpdate(player: Player)
	basketUpdated:FireClient(player, buildClientState(player))
end

getBasketState.OnServerInvoke = function(player: Player)
	return buildClientState(player)
end

discardMushroom.OnServerEvent:Connect(function(player: Player, instanceId: string)
	local data = PlayerData.Get(player)
	if not data or type(instanceId) ~= "string" then
		return
	end

	for index, slot in data.slots do
		if slot.instanceId == instanceId then
			table.remove(data.slots, index)
			break
		end
	end

	PlayerData.RefreshLeaderstats(player)
	pushUpdate(player)
end)

markMushroom.OnServerEvent:Connect(function(player: Player, instanceId: string, kept: boolean)
	local data = PlayerData.Get(player)
	if not data or type(instanceId) ~= "string" or type(kept) ~= "boolean" then
		return
	end

	for _, slot in data.slots do
		if slot.instanceId == instanceId then
			slot.kept = kept
			break
		end
	end

	pushUpdate(player)
end)

useToolOnSlot.OnServerEvent:Connect(function(player: Player, instanceId: string, toolId: string)
	local data = PlayerData.Get(player)
	if not data or type(instanceId) ~= "string" or type(toolId) ~= "string" then
		return
	end

	local toolData = Tools[toolId]
	if not toolData then
		return
	end
	if not table.find(data.ownedTools, toolId) then
		return -- лупа не куплена
	end

	-- Лупа не врёт и не бросает кубик: она просто запоминает, насколько
	-- внимательно гриб рассмотрели. Что именно видно, решает
	-- buildClientState по размеру следа.
	for _, slot in data.slots do
		if toolData.inspectAll or slot.instanceId == instanceId then
			slot.inspectedLevel = math.max(slot.inspectedLevel, toolData.level)
		end
	end

	pushUpdate(player)
end)

confirmBasket.OnServerEvent:Connect(function(player: Player)
	local data = PlayerData.Get(player)
	if not data then
		return
	end

	-- Авторитетная проверка: клиент тоже блокирует кнопку вдали от
	-- стола, но полагаться на это нельзя.
	if not isNearStation(player) then
		return
	end

	local correct = 0
	local wrong = 0
	local spoiled = 0 -- съедобные виды, испорченные плесенью/червями
	local foundNames = {}
	local newlyDiscovered = {}
	local remaining = {}

	for _, slot in data.slots do
		-- Считаем только то, что игрок сам отметил галочкой. Остальное
		-- он ещё не разобрал — пусть лежит до следующего раза.
		if slot.kept ~= true then
			table.insert(remaining, slot)
			continue
		end

		local typeData = MushroomTypes[slot.typeId]

		if not table.find(foundNames, typeData.name) then
			table.insert(foundNames, typeData.name)
		end
		if data.discoveredTypes[slot.typeId] ~= true then
			table.insert(newlyDiscovered, typeData.name)
		end
		PlayerData.DiscoverType(player, slot.typeId)
		PlayerData.LearnSpecies(player, slot.typeId, typeData.isEdible)

		-- Порча перечёркивает вид: заплесневелый белый гриб — всё
		-- равно плохой гриб.
		if typeData.isEdible and slot.defect == nil then
			correct += 1
		else
			wrong += 1
			if typeData.isEdible then
				spoiled += 1
			end
		end
	end

	if correct == 0 and wrong == 0 then
		return -- игрок ничего не отметил, подтверждать нечего
	end

	data.mushroomsSorted += correct + wrong

	local scoreBefore = data.score
	PlayerData.AddScore(player, correct - wrong)
	local scoreAfter = data.score

	data.slots = remaining
	PlayerData.RefreshLeaderstats(player)

	confirmResult:FireClient(player, {
		correct = correct,
		wrong = wrong,
		spoiled = spoiled,
		foundNames = foundNames,
		scoreDelta = scoreAfter - scoreBefore,
		newScore = scoreAfter,
		newlyDiscovered = newlyDiscovered,
	})

	pushUpdate(player)
end)

-- Обновляем UI ровно тогда, когда состояние игрока реально изменилось
-- (собрал гриб, выбросил, подтвердил) — без опроса по таймеру.
PlayerData.Changed:Connect(function(player: Player)
	pushUpdate(player)
end)

-- === Магазин ===

-- Порядок улучшения корзин: купить можно только следующую по счёту,
-- чтобы прогрессия была ступенчатой, а не "накопил и сразу взял топ".
local BASKET_ORDER = { "SMALL", "MEDIUM", "LARGE", "HUGE" }

local function nextBasketId(currentId: string): string?
	local currentIndex = table.find(BASKET_ORDER, currentId)
	if not currentIndex then
		return nil
	end
	return BASKET_ORDER[currentIndex + 1]
end

buyItem.OnServerEvent:Connect(function(player: Player, kind: string, itemId: string)
	local data = PlayerData.Get(player)
	if not data or type(kind) ~= "string" or type(itemId) ~= "string" then
		return
	end

	-- Покупка только у стола: сервер проверяет сам, на клиентскую
	-- блокировку кнопки полагаться нельзя.
	if not isNearStation(player) then
		purchaseResult:FireClient(player, { ok = false, reason = "Нужно быть у стола для разбора" })
		return
	end

	if kind == "tool" then
		local toolData = Tools[itemId]
		if not toolData then
			return
		end
		if table.find(data.ownedTools, itemId) then
			purchaseResult:FireClient(player, { ok = false, reason = "Эта лупа уже куплена" })
			return
		end
		if toolData.previous and not table.find(data.ownedTools, toolData.previous) then
			purchaseResult:FireClient(player, { ok = false, reason = "Сначала нужна предыдущая лупа" })
			return
		end
		if data.score < toolData.price then
			purchaseResult:FireClient(player, { ok = false, reason = "Не хватает очков" })
			return
		end

		PlayerData.AddScore(player, -toolData.price)
		table.insert(data.ownedTools, itemId)
		purchaseResult:FireClient(player, { ok = true, name = toolData.name })
		pushUpdate(player)
	elseif kind == "basket" then
		local expected = nextBasketId(data.basketId)
		if not expected or itemId ~= expected then
			purchaseResult:FireClient(player, { ok = false, reason = "Сначала нужна предыдущая корзина" })
			return
		end

		local basketData = Baskets[itemId]
		if not basketData then
			return
		end
		if data.score < basketData.price then
			purchaseResult:FireClient(player, { ok = false, reason = "Не хватает очков" })
			return
		end

		PlayerData.AddScore(player, -basketData.price)
		data.basketId = itemId
		purchaseResult:FireClient(player, { ok = true, name = basketData.name })
		PlayerData.RefreshLeaderstats(player)
		pushUpdate(player)
	end
end)
