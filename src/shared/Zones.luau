--[[
	Zones.luau

	Участки леса. Зона определяется расстоянием от большой корзины:
	чем дальше уходишь, тем реже простые виды и тем больше риск.

	  Поляна — вокруг самой корзины грибы не растут совсем (clearRadius),
	           чтобы за каждой корзиной приходилось уходить в лес.
	  Опушка — ближайший к корзине лес, простые и частые виды, опасных мало,
	           грибы свежие. Место, где новичок зарабатывает первую лупу.
	  Лес    — обычный набор, как в справочнике MushroomTypes.
	  Чаща   — белые и лисички, но и бледная поганка с ложным опёнком;
	           грибы чаще испорчены, и растут медленнее.

	rarityMultipliers умножаются на rarity вида из MushroomTypes. Вид,
	которого нет в таблице зоны, сохраняет обычный вес (множитель 1).
]]

local CollectionService = game:GetService("CollectionService")

local GameConfig = require(script.Parent.GameConfig)
local MushroomTypes = require(script.Parent.MushroomTypes)

export type ZoneId = "EDGE" | "FOREST" | "DEEP"

export type ZoneData = {
	id: ZoneId,
	name: string,
	-- До какого расстояния от корзины (studs) действует зона.
	-- У последней зоны — math.huge.
	maxDistance: number,
	rarityMultipliers: { [MushroomTypes.MushroomTypeId]: number },
	-- Множитель к шансу порчи (GameConfig.spoilage)
	spoilageMultiplier: number,
	-- Множитель к времени респавна (GameConfig.mushroomRespawnTime)
	respawnMultiplier: number,
	-- Что показать игроку, когда он входит в зону
	enterMessage: string,
}

local Zones = {}

-- Вокруг большой корзины грибы не растут: пустая поляна радиусом в
-- studs. Смысл в том, чтобы с места разбора не было видно ни одного гриба и
-- за каждой корзиной приходилось уходить в лес.
Zones.clearRadius = 80

-- Тропа новичка.
--
-- Пустая поляна решает свою задачу, но у неё есть цена: игрок
-- появляется у корзины и не видит ни одного гриба — то есть ни одного
-- повода куда-то идти. Для рекомендаций Roblox это худший из возможных
-- первых кадров: уход в первые секунды (first play bounce rate) —
-- один из главных сигналов, по которым игру перестают показывать.
--
-- Поэтому в поляне прорезан узкий коридор в ту сторону, где стоит
-- площадка появления: от innerRadius и дальше грибы там растут. Игрок
-- с порога видит, куда идти, но грибы всё равно не у самой корзины и
-- набрать её не отходя не получится.
--
-- direction обязан совпадать со стороной, куда SortingBasket ставит
-- BasketSpawn (сейчас +X). Поменяешь одно — поменяй и другое.
-- Чтобы вернуть наглухо пустую поляну, хватит Zones.trail = nil.
-- Тропа отсчитывается от площадки появления (BasketSpawn) и уходит
-- прямо от корзины в лес. Раньше точки считались от центра корзины по
-- заданному направлению, и это было хрупко: направление приходилось
-- держать согласованным с тем, куда SortingBasket ставит площадку.
-- Теперь спавнер просто берёт площадку и шагает от неё.
--
-- Эти точки создаёт сам спавнер, а не ищет среди маркеров у деревьев, и
-- поляна их не отсеивает. Выключить тропу целиком: Zones.trail = nil.
Zones.trail = {
	-- Сколько грибов на тропе
	count = 6,
	-- На сколько studs перед игроком стоит первый гриб
	startOffset = 12,
	-- Шаг между грибами вдоль тропы
	spacing = 10,
	-- Насколько точки уходят влево-вправо от прямой: тропа петляет, а
	-- не вычерчена по линейке
	wobbleStuds = 5,
}

-- Порядок важен: зона выбирается первой подходящей по maxDistance.
Zones.Order = { "EDGE", "FOREST", "DEEP" } :: { ZoneId }

Zones.Data = {
	EDGE = {
		id = "EDGE",
		name = "Опушка",
		maxDistance = 200,
		rarityMultipliers = {
			RUSSULA = 1.6,
			MILK_CAP = 1.4,
			BIRCH_BOLETE = 1.3,
			HONEY_FUNGUS = 1.2,
			BOLETUS = 0.4,
			CHANTERELLE = 0.7,
			FLY_AGARIC = 0.7,
			DEATH_CAP = 0.2,
			FALSE_HONEY_FUNGUS = 0.6,
			EARTHBALL = 0.8,
		},
		spoilageMultiplier = 0.6,
		respawnMultiplier = 1,
		enterMessage = "Опушка: грибы простые, зато свежие.",
	},
	FOREST = {
		id = "FOREST",
		name = "Лес",
		maxDistance = 340,
		rarityMultipliers = {},
		spoilageMultiplier = 1,
		respawnMultiplier = 1,
		enterMessage = "Лес: встречается всё понемногу.",
	},
	DEEP = {
		id = "DEEP",
		name = "Чаща",
		maxDistance = math.huge,
		rarityMultipliers = {
			BOLETUS = 3,
			CHANTERELLE = 2,
			DEATH_CAP = 2.5,
			FALSE_HONEY_FUNGUS = 1.5,
			EARTHBALL = 1.2,
			RUSSULA = 0.3,
			MILK_CAP = 0.5,
		},
		spoilageMultiplier = 1.4,
		respawnMultiplier = 1.25,
		enterMessage = "Чаща: тут растут белые и лисички, но и поганок с порчей хватает.",
	},
} :: { [ZoneId]: ZoneData }

-- Центр зон — большая корзина. Если её ещё нет на карте, считаем от
-- начала координат, чтобы ничего не падало.
function Zones.GetCenter(): Vector3
	for _, station in CollectionService:GetTagged(GameConfig.stationTag) do
		-- Корзина психолеса тоже помечена этим тегом, но центр зон
		-- считается только от основной.
		if station.Name == "PsychoBasket" then
			continue
		end
		if station:IsA("Model") and station.Parent then
			return station:GetPivot().Position
		end
		if station:IsA("BasePart") and station.Parent then
			return station.Position
		end
	end
	return Vector3.zero
end

function Zones.GetByDistance(distance: number): ZoneData
	for _, zoneId in Zones.Order do
		local zone = Zones.Data[zoneId]
		if distance <= zone.maxDistance then
			return zone
		end
	end
	return Zones.Data.DEEP
end

-- Зона точки на карте. Высота не учитывается: грибы на стволе дерева
-- должны попадать в ту же зону, что и земля под ним.
function Zones.GetByPosition(position: Vector3, center: Vector3?): ZoneData
	local origin = center or Zones.GetCenter()
	local flat = Vector3.new(position.X - origin.X, 0, position.Z - origin.Z)
	return Zones.GetByDistance(flat.Magnitude)
end

return Zones
