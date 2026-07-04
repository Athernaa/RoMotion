--!strict
--!optimize 2
--!native
local RunService = game:GetService("RunService")
local Types = require(script.Parent.Types)
type Animation = Types.Animation
local Scheduler = {}

local PREALLOCATION = 256

local active: { Animation } = table.create(PREALLOCATION)
local activeCount: number = 0
local indexOf: { [Animation]: number } = {}
local connection: RBXScriptConnection? = nil
local stepping = false
local deferredRemovals: { Animation } = {}
local MAX_DT = 1

local function rawRemove(anim: Animation)
	local index = indexOf[anim]
	if index == nil then
		return
	end

	local last = active[activeCount]
	if index ~= activeCount then
		active[index] = last
		indexOf[last] = index
	end
	active[activeCount] = nil
	indexOf[anim] = nil
	activeCount -= 1

	if activeCount == 0 and connection ~= nil then
		connection:Disconnect()
		connection = nil
	end
end

function Scheduler.step(_self: any, dt: number)
	local clampedDt = math.min(dt, MAX_DT)
	local count = activeCount
	stepping = true

	for i = 1, count do
		local anim = active[i]
		if anim == nil then
			continue
		end

		if anim.needsIsolation then
			pcall(anim._advance, anim, clampedDt)
		else
			anim:_advance(clampedDt)
		end
	end

	stepping = false

	if #deferredRemovals > 0 then
		for _, anim in deferredRemovals do
			rawRemove(anim)
		end
		table.clear(deferredRemovals)
	end
end

function Scheduler.add(_self: any, anim: Animation)
	if indexOf[anim] ~= nil then
		return
	end

	activeCount += 1
	active[activeCount] = anim
	indexOf[anim] = activeCount

	if activeCount == 1 and connection == nil then
		connection = RunService.Heartbeat:Connect(function(dt: number)
			Scheduler.step(Scheduler, dt)
		end)
	end
end

function Scheduler.remove(_self: any, anim: Animation)
	if indexOf[anim] == nil then
		return
	end

	if stepping then
		table.insert(deferredRemovals, anim)
	else
		rawRemove(anim)
	end
end

function Scheduler.isActive(_self: any, anim: Animation): boolean
	return indexOf[anim] ~= nil
end
function Scheduler.activeCount(_self: any): number
	return activeCount
end

return Scheduler
