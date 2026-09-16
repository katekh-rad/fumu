--[[
	MushroomStomp.client.luau

	Ловит нажатие F и говорит серверу "игрок наступил". Какой именно
	гриб топчется и с какого расстояния — решает СЕРВЕР (см.
	MushroomInteraction.server.luau), клиент тут ничего не выбирает.

	ContextActionService, а не UserInputService: он сам показывает кнопку
	на мобильных/консолях и корректно уживается с другими биндами.
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local stompEvent = ReplicatedStorage:WaitForChild("StompMushroom")

local ACTION_NAME = "StompMushroom"

local function onStompAction(_actionName: string, inputState: Enum.UserInputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	stompEvent:FireServer()
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction(ACTION_NAME, onStompAction, true, Enum.KeyCode.F)
ContextActionService:SetTitle(ACTION_NAME, "Наступить")
