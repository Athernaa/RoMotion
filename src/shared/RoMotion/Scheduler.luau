--!strict
--!optimize 2
--!native
-- RoMotion singleton Scheduler.
--
-- Owns the single shared update loop that advances every active root
-- Animation each frame. See design.md "Scheduler.luau (Singleton)" and
-- "Data Models" -> "Scheduler state (module upvalues)" for the authoritative
-- shape of this module.
--
-- Only root Animations are ever registered here: a Timeline advances its own
-- children internally, so nested Animations never call `add`/`remove`
-- directly (see design.md "Singleton and lifecycle").
--
-- This module intentionally depends only on `Types.luau` for the `Animation`
-- type annotation. It must NOT require Animation.luau, Tween.luau, or
-- Timeline.luau: those modules depend on the Scheduler, not the reverse.

local RunService = game:GetService("RunService")

local Types = require(script.Parent.Types)

type Animation = Types.Animation

local Scheduler = {}

-- ---------------------------------------------------------------------------
-- Scheduler state (module upvalues). These persist across `require` calls
-- within a single Luau VM, giving RoMotion its process-wide singleton
-- behavior (Requirement 1.5).
--
-- Active roots are kept in a DENSE ARRAY (`active`, length `activeCount`)
-- rather than a `{[Animation]=true}` hash set. Iterating a dense array each
-- frame is markedly more cache-friendly at high active counts, and removal
-- is O(1) via swap-with-last (`indexOf` maps each animation to its slot).
-- The array is preallocated with `table.create` to avoid rehashing/resizing
-- as animations are added.
-- ---------------------------------------------------------------------------
local PREALLOCATION = 256

local active: { Animation } = table.create(PREALLOCATION)
local activeCount: number = 0
local indexOf: { [Animation]: number } = {}
local connection: RBXScriptConnection? = nil

-- While `step` is iterating the dense array, removals are DEFERRED (queued
-- here) instead of swap-removing immediately -- otherwise a swap during
-- iteration would shift slots and could skip or double-process an animation.
-- `_advance` legitimately triggers removals mid-iteration (natural
-- completion, kill, target-less detach), so this deferral keeps slot indices
-- stable for the whole frame; the queue is flushed once the loop finishes.
local stepping = false
local deferredRemovals: { Animation } = {}

-- Maximum frame delta (in seconds) fed to any single Animation per update.
-- Requirement 14.7.
local MAX_DT = 1

--- O(1) swap-with-last removal from the dense array. Disconnects the shared
--- loop when the count reaches 0 (Requirements 14.1, 14.2).
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

--- Advances every currently active root Animation by `dt` seconds, then
--- reaps any Animation that finished, was killed, or lost its last live
--- target during that advancement.
---
--- Only animations that opt in via `needsIsolation` (those running user
--- lifecycle callbacks) are advanced inside a `pcall`, so a callback error
--- never halts the others and the raising animation keeps its state
--- (Requirements 13.7, 15.5). Callback-free tweens are advanced directly for
--- speed -- pure interpolation of pre-validated values cannot raise.
function Scheduler.step(_self: any, dt: number)
	local clampedDt = math.min(dt, MAX_DT)

	-- Snapshot the count so animations added mid-frame (e.g. from a
	-- callback that plays a new tween) are appended past `count` and simply
	-- picked up next frame rather than this one.
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

	-- Flush deferred removals collected during the loop (natural completion,
	-- kill, target-less detach). `rawRemove` is idempotent, so an animation
	-- queued more than once is fine.
	if #deferredRemovals > 0 then
		for _, anim in deferredRemovals do
			rawRemove(anim)
		end
		table.clear(deferredRemovals)
	end
end

--- Registers `anim` as an active root Animation. Connects the shared
--- `RunService.Heartbeat` loop when the active count transitions from 0 to 1
--- (Requirements 14.1, 14.3).
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

--- Unregisters `anim` from the active set. During a `step` the removal is
--- deferred (see `stepping`); otherwise it is applied immediately. Removal
--- disconnects the shared loop when the active count transitions to 0
--- (Requirements 14.1, 14.2).
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

--- Returns whether `anim` is currently registered as an active root
--- Animation.
function Scheduler.isActive(_self: any, anim: Animation): boolean
	return indexOf[anim] ~= nil
end

--- Returns the current number of active root Animations.
function Scheduler.activeCount(_self: any): number
	return activeCount
end

return Scheduler
