--[[
	FindStationLabels.luau (v5)

	ОДНОРАЗОВЫЙ скрипт для Command Bar. Ставит у корзины надпись из двух
	строк:

	    Место для разбора
	    Нажми B чтобы открыть корзину

	Почему так: в прошлый раз замена переписала весь текст надписи
	целиком, и вторая строка («Открой…») пропала вместе со старой
	первой. Теперь текст задаётся сразу двумя строками.

	Ищем по куску «есто разбора» — то, что стоит там сейчас, — и на
	всякий случай ещё по «тол для» и «ткрой», если где-то остался старый
	вариант. Куски слов без первой буквы взяты специально: string.lower
	в Roblox не переводит русские буквы в строчные, поэтому от регистра
	надо уходить именно так.

	КАК ПОЛЬЗОВАТЬСЯ:
	1. Режим редактирования, без Play. Скопировать файл целиком в
	   Command Bar (View → Command Bar), Enter.
	2. Посмотреть строки «!!! НАЙДЕНО» в Output.
	3. Сохранить место: Ctrl+S. Без этого замена потеряется.
	4. Play → проверить надпись у корзины.
]]

local REPLACE = true

local TOP = "Место для разбора"
local BOTTOM = "Нажми B чтобы открыть корзину"

-- Куски слов без первой буквы: регистр не важен
local NEEDLES = { "есто разбора", "тол для", "ткрой" }

-- Полные варианты для замены внутри текста старых скриптов
local PHRASES = {
	{ "Место разбора", TOP },
	{ "Стол для разбора", TOP },
	{ "стол для разбора", TOP },
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local Lighting = game:GetService("Lighting")

local function matches(text: string?): boolean
	if not text or text == "" then
		return false
	end
	for _, needle in NEEDLES do
		if string.find(text, needle, 1, true) then
			return true
		end
	end
	return false
end

local found, replaced = 0, 0

local function scan(root: Instance, rootName: string)
	local ok, descendants = pcall(function()
		return root:GetDescendants()
	end)
	if not ok then
		print(string.format("(%s пропущен: нет доступа)", rootName))
		return
	end

	for _, instance in descendants do
		-- Надпись-табличка: две строки в одном тексте
		if instance:IsA("TextLabel") or instance:IsA("TextButton") then
			if matches(instance.Text) then
				found += 1
				print(string.format("!!! НАЙДЕНО надпись: %s = %q", instance:GetFullName(), instance.Text))
				if REPLACE then
					instance.Text = TOP .. "\n" .. BOTTOM
					instance.TextWrapped = true
					replaced += 1
					print("    -> поставлено две строки")
				end
			end
		end

		-- Подсказка взаимодействия: верхняя строка ObjectText, нижняя ActionText
		if instance:IsA("ProximityPrompt") then
			if matches(instance.ObjectText) or matches(instance.ActionText) then
				found += 1
				print(
					string.format(
						"!!! НАЙДЕНО подсказка: %s (сверху=%q, снизу=%q)",
						instance:GetFullName(),
						instance.ObjectText,
						instance.ActionText
					)
				)
				if REPLACE then
					instance.ObjectText = TOP
					instance.ActionText = BOTTOM
					replaced += 1
					print("    -> обе строки обновлены")
				end
			end
		end

		-- Старые скрипты внутри места: там надпись может задаваться кодом
		if instance:IsA("LuaSourceContainer") then
			local okSource, source = pcall(function()
				return (instance :: any).Source
			end)
			if okSource and type(source) == "string" and matches(source) then
				found += 1
				print(string.format("!!! НАЙДЕНО в скрипте: %s", instance:GetFullName()))

				local lineNumber = 0
				for line in string.gmatch(source, "[^\n]*") do
					lineNumber += 1
					if matches(line) then
						print(string.format("    строка %d: %s", lineNumber, line))
					end
				end

				if REPLACE then
					local updated = source
					for _, pair in PHRASES do
						updated = string.gsub(updated, pair[1], pair[2])
					end
					if updated ~= source then
						local okWrite = pcall(function()
							(instance :: any).Source = updated
						end)
						if okWrite then
							replaced += 1
							print("    -> текст в скрипте заменён")
						else
							print("    -> скрипт защищён от записи, поправь его вручную")
						end
					end
				end
			end
		end
	end
end

print("=== Надпись у корзины (v5) ===")
scan(workspace, "Workspace")
scan(ReplicatedStorage, "ReplicatedStorage")
scan(ServerScriptService, "ServerScriptService")
scan(ServerStorage, "ServerStorage")
scan(StarterGui, "StarterGui")
scan(StarterPlayer, "StarterPlayer")
scan(Lighting, "Lighting")

for _, player in Players:GetPlayers() do
	scan(player, "Player " .. player.Name)
end

print(string.format("=== Готово. Совпадений: %d, изменено: %d ===", found, replaced))
if replaced > 0 then
	print("НЕ ЗАБУДЬ СОХРАНИТЬ МЕСТО: Ctrl+S")
else
	print("Ничего не изменено — пришли, что напечатано выше.")
end
