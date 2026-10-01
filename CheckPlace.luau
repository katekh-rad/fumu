--[[
	CheckPlace.luau

	ОДНОРАЗОВЫЙ скрипт для Command Bar. Ничего не меняет, только
	рассказывает, что за место сейчас открыто и всё ли в нём на месте.

	Зачем: место, открытое через «Edit in Studio» с сайта, привязано к
	игре, но в нём может не быть леса и точек роста грибов — они
	создавались одноразовыми скриптами прямо в Place1.rbxl и живут
	внутри файла места, а не в коде. Если их нет, публиковать рано.

	КАК ПОЛЬЗОВАТЬСЯ: скопировать целиком в Command Bar, Enter,
	прислать то, что напечатало.
]]

print("================ ПРОВЕРКА МЕСТА ================")
print("Название файла:", game.Name)
print("PlaceId:", game.PlaceId, "(должен быть 113125116007892)")
print("GameId:", game.GameId, "(должен быть 10767712944)")

if game.PlaceId == 0 then
	print(">>> Это локальный файл, к игре не привязан.")
else
	print(">>> Место привязано к игре: работает File -> Publish to Roblox, без 'As'.")
end

print("---------------- содержимое мира ----------------")

local function report(name: string)
	local folder = workspace:FindFirstChild(name)
	if not folder then
		print(string.format("%s: НЕТ ПАПКИ", name))
		return 0
	end
	local count = #folder:GetChildren()
	print(string.format("%s: есть, объектов %d", name, count))
	return count
end

local trees = report("Trees")
local spawns = report("MushroomSpawns")
print("BasketSpawn:", workspace:FindFirstChild("BasketSpawn") and "есть" or "нет (создастся кодом)")

print("---------------- надписи в мире ----------------")
local labels = 0
for _, item in workspace:GetDescendants() do
	if (item:IsA("TextLabel") or item:IsA("TextButton")) and item.Text ~= "" then
		labels += 1
		print(string.format("   %s = %q", item:GetFullName(), item.Text))
	end
end
print("всего надписей:", labels)

print("---------------- код от Rojo ----------------")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local shared = ReplicatedStorage:FindFirstChild("Shared")
local server = ServerScriptService:FindFirstChild("Server")
print("ReplicatedStorage.Shared:", shared and "есть" or "НЕТ — Rojo не подключён")
print("ServerScriptService.Server:", server and "есть" or "НЕТ — Rojo не подключён")

-- Читаем пару значений из конфига: так видно, свежий код или запёкшийся
-- в месте старый слепок
if shared then
	local module = shared:FindFirstChild("GameConfig")
	if module and module:IsA("ModuleScript") then
		local ok, config = pcall(require, module)
		if ok and type(config) == "table" then
			local psycho = config.psycho
			print(
				string.format(
					"GameConfig: psycho.targetScore = %s (ждём 24), namesAfterConfirms = %s (ждём 2)",
					tostring(psycho and psycho.targetScore),
					tostring(config.namesAfterConfirms)
				)
			)
		else
			print("GameConfig не прочитался:", tostring(config))
		end
	else
		print("GameConfig: нет модуля в Shared")
	end
end

print("---------------- итог ----------------")
if game.PlaceId == 0 then
	print("Публиковать отсюда нельзя: сначала нужна привязка к игре.")
elseif trees == 0 or spawns == 0 then
	print("НЕ ПУБЛИКОВАТЬ: нет леса или точек роста, грибы не появятся.")
	print("Сначала надо перенести папки Trees и MushroomSpawns из Place1.rbxl.")
else
	print("Всё на месте. Можно File -> Publish to Roblox.")
end
print("===============================================")
