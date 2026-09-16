--[[
	HideCoreGui.client.luau

	Прячет стандартные элементы интерфейса Roblox, которые мешают
	собственному UI игры.

	Чат убран целиком: в одиночной игре про сбор грибов он не нужен,
	а его поле ввода перехватывает клики в левом нижнем углу экрана.

	Если позже захочешь вернуть чат (например, для совместной игры) —
	просто удали или закомментируй строку с Chat ниже.
]]

local StarterGui = game:GetService("StarterGui")

-- CoreGui может быть ещё не готов в первые кадры после входа игрока,
-- поэтому повторяем попытку, пока не получится.
local function setCoreGuiEnabled(coreGuiType: Enum.CoreGuiType, enabled: boolean)
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(coreGuiType, enabled)
		end)
		if ok then
			return
		end
		task.wait(0.1)
	end
end

setCoreGuiEnabled(Enum.CoreGuiType.Chat, false)

-- Список игроков (Tab) пока оставляем: по нему видно счётчики
-- "В корзине" и "Очки". Когда появится собственный HUD, эту строку
-- можно раскомментировать.
-- setCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
