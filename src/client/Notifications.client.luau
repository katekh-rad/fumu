--[[
	Notifications.client.luau

	Короткие всплывающие сообщения внизу экрана ("Корзина полна" и
	подобные). Сервер шлёт текст через RemoteEvent Notify, клиент
	показывает его на пару секунд и плавно убирает.

	Отдельным скриптом, а не внутри BasketUI: уведомления нужны и когда
	корзина закрыта, и не должны зависеть от её состояния.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local notify = ReplicatedStorage:WaitForChild("Notify") :: RemoteEvent

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "Notifications"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local toast = Instance.new("TextLabel")
toast.Size = UDim2.new(0, 320, 0, 44)
toast.Position = UDim2.new(0.5, 0, 1, -110)
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.BackgroundColor3 = Color3.fromRGB(46, 40, 34)
toast.BackgroundTransparency = 1
toast.BorderSizePixel = 0
toast.Font = Enum.Font.GothamMedium
toast.TextSize = 15
toast.TextColor3 = Color3.fromRGB(240, 235, 225)
toast.TextTransparency = 1
toast.Text = ""
toast.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = toast

local currentToken = 0

local function show(message: string)
	currentToken += 1
	local token = currentToken

	toast.Text = message

	local fadeIn = TweenInfo.new(0.15, Enum.EasingStyle.Quad)
	TweenService:Create(toast, fadeIn, { BackgroundTransparency = 0.1, TextTransparency = 0 }):Play()

	task.delay(2, function()
		-- Если за это время пришло новое сообщение, гасить не нужно:
		-- иначе свежий текст исчезнет раньше времени.
		if token ~= currentToken then
			return
		end
		local fadeOut = TweenInfo.new(0.35, Enum.EasingStyle.Quad)
		TweenService:Create(toast, fadeOut, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
	end)
end

notify.OnClientEvent:Connect(function(message: string)
	if type(message) == "string" then
		show(message)
	end
end)
