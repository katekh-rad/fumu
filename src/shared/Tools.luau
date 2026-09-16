--[[
	Tools.luau

	Лупы — единственный инструмент игрока. Лупа НЕ врёт: если она
	показала плесень или червоточины, они там точно есть. Разница между
	лупами только в увеличении: слабая лупа не различает мелкие следы.

	Как это связано с порчей (см. GameConfig.spoilage):
	  у испорченного гриба след имеет размер 1 (крупный), 2 (средний)
	  или 3 (мелкий). Лупа уровня N видит все следы размером <= N.
	  При распределении размеров 60/25/15 получается:
	    x5  -> находит ~60% порчи
	    x10 -> ~85%
	    x20 -> 100%

	Пока у игрока нет ни одной лупы, названия грибов в корзине скрыты.
]]

export type ToolId = "MAGNIFIER" | "MAGNIFIER_X10" | "MAGNIFIER_X20"

export type ToolData = {
	id: ToolId,
	name: string,
	price: number,
	-- Какие следы порчи видны: размер следа <= level.
	level: number,
	-- Кратность — только для подписи на кнопке.
	zoom: number,
	-- Размер пиктограммы при осмотре (пиксели): чем сильнее лупа,
	-- тем крупнее гриб на экране.
	iconSize: number,
	-- true = одно нажатие осматривает всю корзину, а не один гриб.
	inspectAll: boolean,
	-- Какую лупу нужно иметь, чтобы купить эту (покупка по порядку).
	previous: ToolId?,
	description: string,
}

local Tools: { [ToolId]: ToolData } = {
	-- id "MAGNIFIER" оставлен прежним, чтобы не сломать сохранения
	MAGNIFIER = {
		id = "MAGNIFIER",
		name = "Лупа x5",
		price = 10,
		level = 1,
		zoom = 5,
		iconSize = 110,
		inspectAll = false,
		previous = nil,
		description = "Открывает названия грибов. Видны крупные пятна плесени.",
	},
	MAGNIFIER_X10 = {
		id = "MAGNIFIER_X10",
		name = "Лупа x10",
		price = 40,
		level = 2,
		zoom = 10,
		iconSize = 140,
		inspectAll = false,
		previous = "MAGNIFIER",
		description = "Видны средние следы: пятна плесени и ходы червей.",
	},
	MAGNIFIER_X20 = {
		id = "MAGNIFIER_X20",
		name = "Лупа x20",
		price = 100,
		level = 3,
		zoom = 20,
		iconSize = 170,
		inspectAll = true,
		previous = "MAGNIFIER_X10",
		description = "Видна любая порча. Осматривает всю корзину за одно нажатие.",
	},
}

return Tools
