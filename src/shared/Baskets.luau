--[[
	Baskets.luau

	Корзины — отдельная экономика от очков за грибы. Игрок покупает
	корзину большего размера за накопленные монеты/очки, а старую можно
	продать за часть цены (sellValue).
]]

export type BasketId = "SMALL" | "MEDIUM" | "LARGE" | "HUGE"

export type BasketData = {
	id: BasketId,
	name: string,
	capacity: number, -- сколько грибов помещается одновременно
	price: number, -- цена покупки
	sellValue: number, -- сколько вернёт продажа этой корзины
}

local Baskets: { [BasketId]: BasketData } = {
	SMALL = {
		id = "SMALL",
		name = "Маленькая корзина",
		capacity = 8,
		price = 0, -- стартовая, бесплатная
		sellValue = 0,
	},
	MEDIUM = {
		id = "MEDIUM",
		name = "Средняя корзина",
		capacity = 16,
		price = 60,
		sellValue = 25,
	},
	LARGE = {
		id = "LARGE",
		name = "Большая корзина",
		capacity = 28,
		price = 180,
		sellValue = 70,
	},
	HUGE = {
		id = "HUGE",
		name = "Огромная корзина",
		capacity = 45,
		price = 420,
		sellValue = 180,
	},
}

return Baskets
