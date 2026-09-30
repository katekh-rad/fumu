--[[
	Diagnostics.client.luau

	ВРЕМЕННЫЙ скрипт для поиска причины, почему персонаж не двигается
	в тесте "Clients and Servers". Печатает в Output клиента:
	  * есть ли персонаж и Humanoid, не заякорен ли он,
	  * WalkSpeed и состояние Humanoid,
	  * сколько кадров в секунду успевает клиент,
	  * какие клавиши доходят до игры.

	Если в Output нет строк "[Диагностика]" — клиентские скрипты вообще
	не запустились. Если строки есть, а нажатия не печатаются — ввод не
	доходит до окна (дело в фокусе, а не в игре).

	УДАЛИТЬ, когда разберёмся.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

print("[Диагностика] клиентские скрипты запустились")

-- Счётчик кадров: если FPS около нуля, клиент просто не успевает
-- считать кадры, и персонаж кажется застывшим.
local frames = 0
RunService.RenderStepped:Connect(function()
	frames += 1
end)

-- Нажатия клавиш. Если тут тишина при нажатии W — ввод в окно не идёт.
UserInputService.InputBegan:Connect(function(input, processedByUI)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		print(
			string.format(
				"[Диагностика] клавиша %s, перехвачена интерфейсом: %s",
				input.KeyCode.Name,
				tostring(processedByUI)
			)
		)
	end
end)

task.spawn(function()
	while true do
		task.wait(3)

		local fps = math.floor(frames / 3)
		frames = 0

		local character = player.Character
		if not character then
			print(string.format("[Диагностика] персонажа нет, FPS=%d", fps))
			continue
		end

		local humanoid = character:FindFirstChildWhichIsA("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?

		print(
			string.format(
				"[Диагностика] FPS=%d, Humanoid=%s, WalkSpeed=%s, состояние=%s, Anchored=%s, платформа=%s",
				fps,
				tostring(humanoid ~= nil),
				tostring(humanoid and humanoid.WalkSpeed),
				tostring(humanoid and humanoid:GetState().Name),
				tostring(root and root.Anchored),
				tostring(humanoid and humanoid.PlatformStand)
			)
		)
	end
end)
