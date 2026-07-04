--!strict
--!optimize 2

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Tween = require(script.Parent.Tween)
local Easing = require(script.Parent.Easing)
local RelativeValue = require(script.Parent.RelativeValue)

local isServer = RunService:IsServer()

local REMOTE_NAME = "RoMotionNet"
local DEFAULT_DURATION = 0.5

type Target = Instance
type PropertyMap = { [string]: any }

type Plan = { n: string, s: any, g: any }
type Options = {
	duration: number,
	ease: string,
	delay: number,
	repeatCount: number,
	repeatDelay: number,
	yoyo: boolean,
	stagger: number,
}
type CreatePacket = {
	kind: string, -- "create"
	id: number,
	targets: { Target },
	plans: { { Plan } }, -- per target, parallel to `targets`
	options: Options,
	startTime: number,
}

local Global = {}

local function readProperty(target: Target, name: string): any
	return (target :: any)[name]
end
local function writeProperty(target: Target, name: string, value: any)
	(target :: any)[name] = value
end
local function propertyExists(target: Target, name: string): boolean
	local ok, value = pcall(function()
		return (target :: any)[name]
	end)
	return ok and value ~= nil
end

local function resolveOptions(config: any): Options
	config = config or {}

	local duration = config.duration
	if type(duration) ~= "number" or duration <= 0 then
		duration = DEFAULT_DURATION
	end

	local ease = config.ease
	if ease == nil then
		ease = "Quad.InOut"
	elseif type(ease) ~= "string" then
		error("RoMotion.global: 'ease' must be a named easing string (custom functions can't be networked).", 3)
	end
	Easing.resolve(ease)

	if config.keyframes ~= nil then
		error("RoMotion.global: keyframes are not supported for global tweens.", 3)
	end

	local delay = config.delay
	if type(delay) ~= "number" or delay < 0 then
		delay = 0
	end

	local repeatCount = config["repeat"]
	if type(repeatCount) ~= "number" then
		repeatCount = 0
	end

	local repeatDelay = config.repeatDelay
	if type(repeatDelay) ~= "number" or repeatDelay < 0 then
		repeatDelay = 0
	end

	local stagger = config.stagger
	if type(stagger) ~= "number" or stagger < 0 then
		stagger = 0
	end

	return {
		duration = duration,
		ease = ease,
		delay = delay,
		repeatCount = repeatCount,
		repeatDelay = repeatDelay,
		yoyo = config.yoyo == true,
		stagger = stagger,
	}
end

local function restingValue(plan: Plan, options: Options): any
	if options.repeatCount == -1 then
		return plan.s
	end
	local totalIterations = options.repeatCount + 1
	if options.yoyo then
		return (totalIterations % 2 == 1) and plan.g or plan.s
	end
	return plan.g
end

local function toTargetList(target: any): { Target }
	if typeof(target) == "Instance" then
		return { target }
	end
	if type(target) == "table" then
		local list = {}
		for _, value in target do
			if typeof(value) ~= "Instance" then
				error("RoMotion.global: target list must contain only Instances.", 3)
			end
			table.insert(list, value)
		end
		if #list == 0 then
			error("RoMotion.global: the targets list must not be empty.", 3)
		end
		return list
	end
	error("RoMotion.global: target must be an Instance or a list of Instances.", 3)
end

local remote: RemoteEvent
if isServer then
	local existing = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		remote = existing
	else
		remote = Instance.new("RemoteEvent")
		remote.Name = REMOTE_NAME
		remote.Parent = ReplicatedStorage
	end
end

if isServer then
	local nextId = 0
	local activeGlobals: { [number]: CreatePacket } = {}
	local function buildPlans(mode: string, targets: { Target }, a: PropertyMap, b: PropertyMap?): { { Plan } }
		local perTarget: { { Plan } } = {}

		for i, target in targets do
			local plans: { Plan } = {}

			if mode == "to" then
				for name, dest in a do
					if not propertyExists(target, name) then
						error("RoMotion.global: '" .. name .. "' is not a property of " .. target:GetFullName(), 3)
					end
					local start = readProperty(target, name)
					local goal = if type(dest) == "string" then RelativeValue.resolve(start, dest, name) else dest
					table.insert(plans, { n = name, s = start, g = goal })
				end
			elseif mode == "from" then
				for name, source in a do
					if not propertyExists(target, name) then
						error("RoMotion.global: '" .. name .. "' is not a property of " .. target:GetFullName(), 3)
					end
					local current = readProperty(target, name)
					table.insert(plans, { n = name, s = source, g = current })
				end
			else -- fromTo
				for name, startValue in a do
					local endValue = (b :: PropertyMap)[name]
					if endValue == nil then
						error("RoMotion.global: fromTo start/end key mismatch for '" .. name .. "'.", 3)
					end
					if not propertyExists(target, name) then
						error("RoMotion.global: '" .. name .. "' is not a property of " .. target:GetFullName(), 3)
					end
					table.insert(plans, { n = name, s = startValue, g = endValue })
				end
			end

			perTarget[i] = plans
		end

		return perTarget
	end

	local function broadcast(mode: string, target: any, a: PropertyMap, b: PropertyMap?, config: any)
		if a == nil or next(a) == nil then
			error("RoMotion.global: the property map must contain at least one property.", 3)
		end

		local targets = toTargetList(target)
		local options = resolveOptions(config)
		local perTarget = buildPlans(mode, targets, a, b)

		for i, target in targets do
			for _, plan in perTarget[i] do
				writeProperty(target, plan.n, restingValue(plan, options))
			end
		end

		nextId += 1
		local id = nextId
		local packet: CreatePacket = {
			kind = "create",
			id = id,
			targets = targets,
			plans = perTarget,
			options = options,
			startTime = workspace:GetServerTimeNow(),
		}

		activeGlobals[id] = packet
		if options.repeatCount ~= -1 then
			local perTween = options.delay
				+ options.duration * (options.repeatCount + 1)
				+ options.repeatDelay * options.repeatCount
			local total = perTween + (#targets - 1) * options.stagger
			task.delay(total + 1, function()
				activeGlobals[id] = nil
			end)
		end

		remote:FireAllClients(packet)

		local handle = {}
		handle.Id = id
		function handle.Stop(_self)
			activeGlobals[id] = nil
			remote:FireAllClients({ kind = "stop", id = id })
		end
		handle.stop = handle.Stop
		return handle
	end

	Global.to = function(target: any, props: PropertyMap, config: any?)
		return broadcast("to", target, props, nil, config)
	end
	Global.from = function(target: any, props: PropertyMap, config: any?)
		return broadcast("from", target, props, nil, config)
	end
	Global.fromTo = function(target: any, fromProps: PropertyMap, toProps: PropertyMap, config: any?)
		if toProps == nil or next(toProps) == nil then
			error("RoMotion.global: the end property map must contain at least one property.", 3)
		end
		return broadcast("fromTo", target, fromProps, toProps, config)
	end

	Players.PlayerAdded:Connect(function(player)
		for _, packet in activeGlobals do
			remote:FireClient(player, packet)
		end
	end)
end

if not isServer then
	local clientGlobals: { [number]: { any } } = {}

	local function handleCreate(packet: CreatePacket)
		local existing = clientGlobals[packet.id]
		if existing then
			for _, tween in existing do
				pcall(function()
					tween:kill()
				end)
			end
		end

		local options = packet.options
		local handles = {}

		local elapsed = workspace:GetServerTimeNow() - packet.startTime
		if elapsed < 0 then
			elapsed = 0
		end

		for i, target in packet.targets do
			if typeof(target) ~= "Instance" then
				continue
			end

			local plans = packet.plans[i]
			local fromMap = {}
			local toMap = {}
			for _, plan in plans do
				fromMap[plan.n] = plan.s
				toMap[plan.n] = plan.g
				pcall(writeProperty, target, plan.n, plan.s)
			end

			local config = {
				duration = options.duration,
				ease = options.ease,
				delay = options.delay + (i - 1) * options.stagger,
				["repeat"] = options.repeatCount,
				repeatDelay = options.repeatDelay,
				yoyo = options.yoyo,
			}

			local ok, tween = pcall(function()
				return Tween.fromTo(target, fromMap, toMap, config)
			end)
			if ok and tween then
				tween:play()
				if elapsed > 0 then
					tween:seek(elapsed)
				end
				table.insert(handles, tween)
			end
		end

		clientGlobals[packet.id] = handles
	end

	local function handleStop(id: number)
		local handles = clientGlobals[id]
		if not handles then
			return
		end
		for _, tween in handles do
			pcall(function()
				tween:kill()
			end)
		end
		clientGlobals[id] = nil
	end

	local function onPacket(packet: any)
		if type(packet) ~= "table" then
			return
		end
		if packet.kind == "create" then
			handleCreate(packet)
		elseif packet.kind == "stop" then
			handleStop(packet.id)
		end
	end

	local function bind(r: Instance)
		if r:IsA("RemoteEvent") then
			(r :: RemoteEvent).OnClientEvent:Connect(onPacket)
		end
	end
	local existingRemote = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
	if existingRemote then
		bind(existingRemote)
	else
		ReplicatedStorage.ChildAdded:Connect(function(child)
			if child.Name == REMOTE_NAME then
				bind(child)
			end
		end)
	end

	local function serverOnly()
		error("RoMotion.global tweens can only be created on the server.", 2)
	end
	Global.to = serverOnly
	Global.from = serverOnly
	Global.fromTo = serverOnly
end

return Global
