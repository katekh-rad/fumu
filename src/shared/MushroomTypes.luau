--[[
	MushroomTypes.luau

	Справочник видов грибов. Один и тот же вид ВСЕГДА одной и той же
	съедобности (isEdible фиксирован для вида) — случайность не в том,
	"какой сегодня этот гриб", а в том, узнал ли игрок вид верно.

	Если позже захочешь "обманки" (два похожих вида — один съедобный,
	один ядовитый) — просто дай им близкий looksLikeId, см. ниже.
]]

export type MushroomTypeId =
	"BOLETUS"
	| "BIRCH_BOLETE"
	| "CHANTERELLE"
	| "HONEY_FUNGUS"
	| "RUSSULA"
	| "FLY_AGARIC"
	| "DEATH_CAP"
	| "FALSE_HONEY_FUNGUS"
	| "MILK_CAP"
	| "EARTHBALL"

export type MushroomTypeData = {
	id: MushroomTypeId,
	name: string, -- отображаемое имя
	isEdible: boolean,
	basePoints: number, -- очки при верном разборе (съедобный -> +, ядовитый -> -)
	rarity: number, -- вес для спавна, больше = чаще
	-- насколько убедительно выглядит "на глаз" без инструментов:
	-- 1 = почти всегда угадывается верно, 3 = легко спутать с другим видом
	visualDifficulty: number,
	-- id вида, с которым этот гриб визуально путают (для описаний/подсказок лупы)
	looksLikeId: MushroomTypeId?,
	modelColor: Color3, -- временный цвет placeholder-меша, пока нет моделей
}

local MushroomTypes: { [MushroomTypeId]: MushroomTypeData } = {
	BOLETUS = {
		id = "BOLETUS",
		name = "Белый гриб",
		isEdible = true,
		basePoints = 15,
		rarity = 5,
		visualDifficulty = 1,
		modelColor = Color3.fromRGB(200, 165, 110),
	},
	BIRCH_BOLETE = {
		id = "BIRCH_BOLETE",
		name = "Подберёзовик",
		isEdible = true,
		basePoints = 10,
		rarity = 8,
		visualDifficulty = 1,
		modelColor = Color3.fromRGB(170, 140, 100),
	},
	CHANTERELLE = {
		id = "CHANTERELLE",
		name = "Лисичка",
		isEdible = true,
		basePoints = 8,
		rarity = 10,
		visualDifficulty = 1,
		modelColor = Color3.fromRGB(240, 180, 40),
	},
	HONEY_FUNGUS = {
		id = "HONEY_FUNGUS",
		name = "Опёнок",
		isEdible = true,
		basePoints = 6,
		rarity = 9,
		visualDifficulty = 3, -- легко спутать с ложным опёнком
		looksLikeId = "FALSE_HONEY_FUNGUS",
		modelColor = Color3.fromRGB(190, 150, 90),
	},
	RUSSULA = {
		id = "RUSSULA",
		name = "Сыроежка",
		isEdible = true,
		basePoints = 5,
		rarity = 12,
		visualDifficulty = 2,
		modelColor = Color3.fromRGB(160, 90, 130),
	},
	FLY_AGARIC = {
		id = "FLY_AGARIC",
		name = "Мухомор красный",
		isEdible = false,
		basePoints = -10,
		rarity = 7,
		visualDifficulty = 1, -- узнаётся легко, зато опасен
		modelColor = Color3.fromRGB(210, 30, 30),
	},
	DEATH_CAP = {
		id = "DEATH_CAP",
		name = "Бледная поганка",
		isEdible = false,
		basePoints = -25, -- самый опасный вид, максимальный штраф
		rarity = 4,
		visualDifficulty = 2,
		modelColor = Color3.fromRGB(230, 225, 200),
	},
	FALSE_HONEY_FUNGUS = {
		id = "FALSE_HONEY_FUNGUS",
		name = "Ложный опёнок",
		isEdible = false,
		basePoints = -12,
		rarity = 8,
		visualDifficulty = 3,
		looksLikeId = "HONEY_FUNGUS",
		modelColor = Color3.fromRGB(200, 160, 80),
	},
	MILK_CAP = {
		id = "MILK_CAP",
		name = "Волнушка",
		isEdible = true,
		basePoints = 7,
		rarity = 9,
		visualDifficulty = 2,
		modelColor = Color3.fromRGB(220, 190, 200),
	},
	EARTHBALL = {
		id = "EARTHBALL",
		name = "Ложнодождевик",
		isEdible = false,
		basePoints = -8,
		rarity = 6,
		visualDifficulty = 2,
		modelColor = Color3.fromRGB(140, 130, 100),
	},
}

return MushroomTypes
