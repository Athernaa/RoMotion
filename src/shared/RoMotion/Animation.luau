--!strict
--!optimize 2
--!native
-- RoMotion shared Animation base state machine and control surface.
--
-- Defines the common control surface and state machine shared by Tween and
-- Timeline. See design.md "Animation.luau (Shared base)" and
-- requirements.md Requirement 12 (Playback Control) and Requirement 15
-- (Cleanup and Lifecycle Safety) for the authoritative contract.
--
-- `Tween.luau` and `Timeline.luau` (later tasks) extend this module using
-- the standard Luau metatable-inheritance pattern:
--
--     local Tween = setmetatable({}, { __index = Animation })
--     Tween.__index = Tween
--
--     function Tween.new(...): Tween
--         local self = Animation.new(duration)
--         return setmetatable(self :: any, Tween) :: Tween
--     end
--
-- A subclass that defines its own `_advance`/`_render` (or overrides any
-- other control method) takes priority over this module's implementation,
-- because Lua/Luau method lookup checks the instance's own metatable
-- (`Tween`) before walking up to `Tween`'s `__index` (`Animation`).
--
-- `Animation.luau` has no factory of its own and creates no
-- independently-useful instances: `Animation.new` exists so subclasses have
-- a base constructor to call into, not for direct use by library callers.
-- It must nonetheless remain independently loadable/requirable and
-- internally consistent with no subclasses defined yet, which is why
-- `_advance`/`_render` have real (if minimal) default implementations
-- below rather than stubs that error.
--
-- CONVENTION (internal-only helpers):
-- `_advancePosition` and `_complete` are internal helpers for subclasses to
-- reuse, but they are NOT part of the public `Types.Animation` type surface
-- (see Types.luau -- only `_advance` and `_render` are declared there).
-- Because of that, code that holds a value strictly typed as `Types.Animation`
-- (e.g. this module's own methods, or a future Tween/Timeline method whose
-- `self` is typed as `Types.Tween`/`Types.Timeline`) cannot call
-- `self:_advancePosition(...)` or `self:_complete()` directly under
-- `--!strict` -- the field doesn't exist on the type. Call them
-- module-qualified instead, passing `self` positionally:
--
--     Animation._advancePosition(self, dt)
--     Animation._complete(self)
--
-- This keeps the public `Animation` type in Types.luau exactly matching
-- design.md while still letting the halt-at-zero and detach-and-complete
-- logic live in one reusable place instead of being duplicated in every
-- subclass.

local Types = require(script.Parent.Types)
local Scheduler = require(script.Parent.Scheduler)

type Animation = Types.Animation
type PlaybackState = Types.PlaybackState
type Direction = Types.Direction

local Animation = {}
Animation.__index = Animation

--- Constructs the shared base state for a new Animation: `position = 0`,
--- forward direction, normal time scale, `"idle"` state, and `started =
--- false`. Subclasses call this from their own constructor and then
--- `setmetatable` the result onto their own metatable (see module header).
function Animation.new(duration: number): Animation
	local self = {
		position = 0,
		duration = duration,
		direction = 1,
		timeScale = 1,
		state = "idle",
		started = false,
		-- Default to isolated; subclasses (Tween) may lower this to false
		-- when they have no user callbacks. Timelines keep it true.
		needsIsolation = true,
	}

	return (setmetatable(self, Animation) :: any) :: Animation
end

-- ---------------------------------------------------------------------------
-- Requirement 12.1, 12.12: play
-- ---------------------------------------------------------------------------
--- On a paused or unstarted Animation, sets the playback direction forward
--- and registers with the Scheduler so the Animation advances on
--- subsequent Scheduler updates. No-op when killed.
function Animation.play(self: Animation): Animation
	if self.state == "killed" then
		return self
	end

	self.direction = 1
	self.state = "playing"
	Scheduler.add(Scheduler, self)

	return self
end

-- ---------------------------------------------------------------------------
-- Requirement 12.2, 12.12: pause
-- ---------------------------------------------------------------------------
--- Stops advancing while retaining the current position and direction.
--- Does not unregister from the Scheduler: `_advance` implementations are
--- expected to no-op while `state ~= "playing"` (see `_advancePosition`
--- below). No-op when killed.
function Animation.pause(self: Animation): Animation
	if self.state == "killed" then
		return self
	end

	self.state = "paused"

	return self
end

-- ---------------------------------------------------------------------------
-- Requirement 12.3, 12.12: resume
-- ---------------------------------------------------------------------------
--- Continues advancing from the retained position and direction.
--- No-op when killed.
function Animation.resume(self: Animation): Animation
	if self.state == "killed" then
		return self
	end

	self.state = "playing"
	Scheduler.add(Scheduler, self)

	return self
end

-- ---------------------------------------------------------------------------
-- Requirement 12.4, 12.12: restart
-- ---------------------------------------------------------------------------
--- Resets position to 0, direction to forward, and `started` to false (so
--- an active-phase lifecycle such as `onStart` can refire), then advances
--- forward on the next Scheduler update. No-op when killed.
function Animation.restart(self: Animation): Animation
	if self.state == "killed" then
		return self
	end

	self.position = 0
	self.direction = 1
	self.started = false
	self.state = "playing"
	Scheduler.add(Scheduler, self)

	return self
end

-- ---------------------------------------------------------------------------
-- Requirement 12.5, 12.12: reverse
-- ---------------------------------------------------------------------------
--- Sets the playback direction backward and advances toward the beginning
--- on subsequent Scheduler updates. No-op when killed.
function Animation.reverse(self: Animation): Animation
	if self.state == "killed" then
		return self
	end

	self.direction = -1
	self.state = "playing"
	Scheduler.add(Scheduler, self)

	return self
end

-- ---------------------------------------------------------------------------
-- Requirements 12.6, 12.9, 12.12: seek
-- ---------------------------------------------------------------------------
--- Sets the current position to `seconds`, clamped to `[0, duration]`,
--- re-renders at that position, and preserves the current playing/paused
--- state. No-op when killed.
function Animation.seek(self: Animation, seconds: number): Animation
	if self.state == "killed" then
		return self
	end

	self.position = math.clamp(seconds, 0, self.duration)
	self:_render()

	return self
end

-- ---------------------------------------------------------------------------
-- Requirements 12.8, 12.10, 12.12: progress
-- ---------------------------------------------------------------------------
--- With `fraction` supplied: sets position to `fraction * duration`
--- (`fraction` clamped to `[0, 1]`), re-renders, and preserves the current
--- playing/paused state; no-op when killed. With no argument: returns the
--- current fraction (`position / duration`, or 0 when `duration` is 0).
--- The no-argument query form never mutates state, so it is not gated on
--- `killed` -- there is no action to withhold.
function Animation.progress(self: Animation, fraction: number?): number | Animation
	if fraction == nil then
		if self.duration == 0 then
			return 0
		end
		return self.position / self.duration
	end

	if self.state == "killed" then
		return self
	end

	local clamped = math.clamp(fraction, 0, 1)
	self.position = clamped * self.duration
	self:_render()

	return self
end

-- ---------------------------------------------------------------------------
-- setTimeScale
-- ---------------------------------------------------------------------------
--- Stores the Animation's time scale multiplier. Requirement 12 does not
--- specify validation of `scale` at the base Animation level (unlike
--- Timeline's `setTimeScale`, Requirement 9.5, which rejects values <= 0
--- and retains the previous scale) -- this base implementation simply
--- stores the value. No-op when killed, consistent with every other
--- control method.
function Animation.setTimeScale(self: Animation, scale: number): Animation
	if self.state == "killed" then
		return self
	end

	self.timeScale = scale

	return self
end

-- ---------------------------------------------------------------------------
-- Requirements 12.7, 15.2: kill
-- ---------------------------------------------------------------------------
--- Stops advancing, detaches from the Scheduler, and marks the Animation as
--- killed so every other control method becomes a no-op (Requirement
--- 12.12). Idempotent: killing an already-killed Animation does nothing.
--- Releasing Target references is a subclass responsibility (Animation.luau
--- holds no Target references of its own).
function Animation.kill(self: Animation): ()
	if self.state == "killed" then
		return
	end

	self.state = "killed"
	Scheduler.remove(Scheduler, self)
end

-- ---------------------------------------------------------------------------
-- Internal helper -- Requirement 12.11: backward advancement halts at 0.
--
-- Not part of the public Types.Animation surface; call module-qualified as
-- `Animation._advancePosition(self, dt)` (see module header CONVENTION).
-- Advances `position` by `dt` seconds scaled by `direction` and
-- `timeScale`. Does nothing unless `state == "playing"`. When moving
-- backward and the new position would be at or below 0, clamps to exactly
-- 0 and transitions to `"paused"` so the Animation stops advancing and
-- holds at 0 rather than continuing to attempt (and clamp) negative
-- advancement every subsequent update.
-- ---------------------------------------------------------------------------
function Animation._advancePosition(self: Animation, dt: number): ()
	if self.state ~= "playing" then
		return
	end

	local delta = dt * self.direction * self.timeScale
	local newPosition = self.position + delta

	if self.direction == -1 and newPosition <= 0 then
		self.position = 0
		self.state = "paused"
	else
		self.position = newPosition
	end
end

-- ---------------------------------------------------------------------------
-- Internal helper -- Requirements 15.2, 15.3, 15.4: detach-and-complete.
--
-- Not part of the public Types.Animation surface; call module-qualified as
-- `Animation._complete(self)` (see module header CONVENTION). Subclasses
-- call this when their active phase finishes naturally with no further
-- repeat (Requirement 15.3) or when their last live Target is removed
-- (Requirement 15.4): it marks the Animation `"completed"` and unregisters
-- it from the Scheduler. Already-killed Animations are left untouched --
-- `kill` (Requirement 15.2) is the authoritative terminal transition.
-- ---------------------------------------------------------------------------
function Animation._complete(self: Animation): ()
	if self.state == "killed" then
		return
	end

	self.state = "completed"
	Scheduler.remove(Scheduler, self)
end

-- ---------------------------------------------------------------------------
-- Default `_advance`/`_render`.
--
-- Tween.luau and Timeline.luau are expected to override both by defining
-- their own `_advance`/`_render` on their own metatable (see module
-- header): Lua/Luau method lookup checks the subclass's own table first, so
-- a subclass override always takes priority over these defaults. These
-- defaults exist so a bare Animation instance -- and this module in
-- isolation, with no subclasses defined yet -- never errors: `_advance`
-- performs the shared halt-at-zero position advancement and re-renders;
-- `_render` has nothing to render at the base Animation level, since
-- Animation.luau holds no Target/property state of its own.
-- ---------------------------------------------------------------------------
function Animation._advance(self: Animation, dt: number): ()
	Animation._advancePosition(self, dt)
	self:_render()
end

function Animation._render(self: Animation): ()
	-- no-op: nothing to render at the base Animation level.
end

return Animation
