--!strict
--!optimize 2
--!native
-- RoMotion Tween: an Animation that interpolates target properties.
--
-- Implements the `to`/`from`/`fromTo` factories (Requirements 2, 3) on top
-- of the shared `Animation` base state machine. See design.md "Tween.luau"
-- and requirements.md Requirements 2 and 3 for the authoritative contract
-- for this task; later tasks extend this same module (see the TODO markers
-- below) rather than rewriting it:
--
--   - Requirement 6 (delay/repeat/yoyo/repeatDelay)                      -- task 8.8
--   - Requirement 8 (keyframes)                                          -- task 8.15
--   - Requirement 13 (lifecycle callbacks)                               -- task 8.18
--   - Requirements 15.1, 15.4 (destroyed-target detection/detach)        -- task 8.23 (done)
--   - Requirement 11 (stagger across multiple targets)                   -- task 10.1 (done)
--
-- Extends `Animation.luau` using the documented subclassing convention
-- (see Animation.luau's module header): `Tween` is its own metatable with
-- `__index = Animation`, so unset methods fall back to the shared control
-- surface (play/pause/resume/restart/reverse/seek/progress/setTimeScale/
-- kill), while `_advance`/`_render` are overridden here.
--
-- CONVENTION (delay / repeat / yoyo / repeatDelay timeline, Requirement 6,
-- task 8.8):
-- `self.duration` (the base `Animation` field) represents the Tween's
-- **full timeline length**: `delay + iterationDuration * (repeatCount + 1)
-- + repeatDelay * repeatCount` for a finite `repeatCount`, or `math.huge`
-- when `repeatCount == -1` (infinite repeat has no finite total length,
-- but the field must stay a `number` under `--!strict`; `math.huge` is a
-- valid `number`). `self.position` (also inherited from `Animation`) is
-- therefore the Tween's total elapsed time since it started playing,
-- counting through the initial delay and every iteration/repeatDelay
-- window -- exactly the same "local clock" role `position` already plays
-- for a plain undelayed/unrepeated Tween, just measured against a longer
-- timeline. `Animation.seek`/`Animation.progress` (Requirement 12) keep
-- working unmodified against this convention: `seek` clamps into
-- `[0, duration]` and `progress` maps a 0..1 fraction onto it exactly as
-- before. (Caveat: `progress()` with no fraction, and `progress(0)`, on an
-- infinite-repeat Tween divide/multiply against `math.huge` and are not a
-- meaningful operation for that case -- Requirement 6 does not require
-- `progress`/`seek` to be meaningful for infinite-repeat Tweens, and nothing
-- in this task exercises that combination.)
--
-- The per-iteration interpolation length itself (what Requirement 2.3's
-- `duration`/`Errors.invalidDuration` validation is about) is kept as a
-- separate internal field, `self.iterationDuration`, distinct from the
-- timeline-length `self.duration` described above. `_render` derives, from
-- `self.position`, which iteration (0-based) is current and the local
-- interpolation fraction `t` (0..1) within that iteration via
-- `computeIteration` (see below): the delay is subtracted first (Property
-- 17: `computeIteration` returns `nil`, and `_render` does nothing, while
-- elapsed time is still within the delay window); then elapsed time is
-- divided into `iterationDuration + repeatDelay`-sized cycles, with the
-- iteration index clamped to `repeatCount` (finite case only) and the
-- local fraction clamped to `iterationDuration` so a completed cycle's
-- trailing `repeatDelay` window holds at that iteration's final rendered
-- value rather than continuing to interpolate (Property 16: no interpolated
-- change occurs during a `repeatDelay` window, and it is never applied
-- after the final iteration since the index clamp prevents ever entering a
-- "cycle" beyond `repeatCount`). `yoyo` (Requirement 6.4) does not alter
-- any captured `startValue`/`endValue` -- it only flips, for odd iteration
-- indices, which side of the pair is passed to the Interpolator first (see
-- `_render`), so odd iterations visually play end -> start while even
-- iterations play start -> end.
--
-- CONVENTION (lifecycle callbacks, Requirement 13, task 8.18):
-- The iteration-boundary crossings `computeIterationState` computes above
-- are exactly the moments `onRepeat`/`onComplete` fire from: `_advance`
-- (see below) compares `computeIterationState`'s `completedIterations`
-- return against the previous update's value (`self.lastCompletedIterations`)
-- to find every boundary newly crossed since the last update, and fires
-- `onRepeat` (non-final boundary) or `onComplete` (final boundary, only
-- when `repeatCount ~= -1`, Requirement 13.5) for each one in ascending
-- order -- this handles a caller `seek`ing/`progress`ing across more than
-- one boundary in a single call the same way a normal `_advance` would.
-- `onStart` fires once, exactly where `self.started` flips `false` ->
-- `true` (already gated on the configured `delay`, task 8.8). `onUpdate`
-- fires on every update that actually renders (i.e. once `elapsed >= 0`),
-- passing the same un-eased per-iteration local fraction `_render` itself
-- uses (`effectiveT`) rather than the eased value, since eased progress
-- can overshoot outside `[0, 1]` for overshoot easing (Property 32
-- requires `onUpdate`'s progress stay within `[0, 1]`). Requirement 13.6
-- fixes the firing order as onStart, then onUpdate, then onRepeat/
-- onComplete; `_advance` below invokes them in exactly that order every
-- update. Natural-completion detachment via `Animation._complete`
-- (Requirements 15.2-15.4) is not wired up here for the finite-repeat
-- case; a Tween that
-- reaches the end of its final iteration simply holds its final rendered
-- value indefinitely rather than detaching from the Scheduler (see
-- `computeIteration`'s index/fraction clamping) until a later task adds
-- that detachment.
--
-- CONVENTION (Relative_Value resolution, Requirement 7.3, task 8.6):
-- A PropertyPlan's `endValue` (for `to`/`fromTo`) may be a Relative_Value
-- string such as `"+=100"` instead of a concrete value; Requirement 7.3
-- requires resolving it against the start value captured for that property
-- "at the moment the Tween begins its active phase". Where that moment
-- falls differs by mode, matching the mode/active-phase capture convention
-- above:
--   - `to`:     startValue isn't known until `captureActivePhase` runs, so
--               `endValue` is resolved there too, immediately after
--               `startValue` is captured for that same plan -- both steps
--               happen exactly once, guarded by the same `self.started`
--               check `_advance` already uses.
--   - `fromTo`: startValue is already fully known at construction time (an
--               explicit start Property_Map value, nothing deferred), so
--               `endValue` is resolved eagerly in `Tween.fromTo` itself,
--               before `Tween.new` is ever called. This keeps "resolve
--               against the known startValue as soon as it's known" a
--               single consistent rule across both modes, rather than
--               special-casing fromTo inside `captureActivePhase`.
--   - `from`:   the Property_Map value here is the *source* (`startValue`),
--               not a destination -- Requirement 7.3 (and Requirement 7
--               generally) is about resolving *destination* values against
--               a captured start, which doesn't apply to `from`'s source
--               value the same way (there is no "captured start" for it to
--               resolve against; it IS the start). A relative-value string
--               used this way is passed through unresolved rather than
--               guessed-at, since Requirement 7 does not specify behavior
--               for it and misinterpreting it silently would be worse than
--               leaving it alone.
-- Only string-typed raw values are ever passed to `RelativeValue.resolve`
-- (see `resolveEndValue` below) -- concrete values (numbers, Vector3, etc.)
-- pass through unchanged, per the design's "only attempt resolution when
-- the raw value is a string" rule.
--
-- CONVENTION (keyframe waypoints, Requirement 8, task 8.15):
-- `config.keyframes` composes with whichever mode (`to`/`from`/`fromTo`)
-- created the Tween rather than being a fourth mode of its own: the
-- Property_Map argument passed to the factory still determines *which*
-- properties are animated (existence-checked exactly as before) and still
-- supplies the mode's usual position-0/position-1 endpoints (`startValue`/
-- `endValue` on each `PropertyPlan`, populated by the same capture rules
-- described above -- for `to` this is "current value captured at active
-- phase" at position 0, per Requirement 8.6). `config.keyframes` then
-- supplies zero or more *intermediate* waypoints strictly between those
-- two endpoints, keyed by each Keyframe's own `position`/`values`.
--
-- At construction time (`resolveKeyframes`), the configured list is
-- validated (Requirements 8.2, 8.4, 8.7) and sorted ascending by
-- `position` (Requirement 8.1 describes ascending playback order, not an
-- input-ordering requirement -- see that function), and each Keyframe's
-- `ease` is resolved to a concrete `Easing_Function` via `Easing.resolve`
-- (which already defaults to Quad.InOut when omitted, satisfying
-- Requirement 8.5 for free) into the parallel `self.keyframeEase` array.
-- `buildKeyframeWaypoints` then turns that sorted list into an ordered
-- `self.keyframeWaypoints` array covering the full 0..1 range: a synthetic
-- bookend `{position = 0, keyframeIndex = nil}` is prepended only when the
-- earliest real Keyframe's position is greater than 0 (Requirement 8.6),
-- and a synthetic bookend `{position = 1, keyframeIndex = nil}` is
-- appended only when the latest real Keyframe's position is less than 1
-- (so the mode's usual `endValue` remains reachable at position 1 when no
-- Keyframe already claims that position). A `keyframeIndex` of `nil` on a
-- waypoint means "use the PropertyPlan's own startValue/endValue for this
-- boundary" (`waypointValue` below) rather than a Keyframe's `values`.
-- Because both bookends are static/positional, this whole waypoint list is
-- computed once at construction time -- only the *values* a synthetic
-- bookend resolves to at render time depend on capture having run.
--
-- `_render` (see below) locates, for the current per-iteration fraction,
-- which two consecutive waypoints bracket it (`findKeyframeSegment`),
-- computes the local fraction within that bracket, and eases it with
-- *that segment's own* easing function: a segment ending at a real
-- Keyframe uses that Keyframe's resolved ease (Requirement 8.3); a segment
-- ending at the synthetic position-1 bookend (i.e. the portion of the
-- timeline after the last configured Keyframe, if any) falls back to the
-- Tween's own overall `self.ease` instead, since no Keyframe governs that
-- stretch. Every waypoint's position is strictly greater than the
-- previous one (duplicates are rejected at validation time and the
-- bookends are only added when strictly outside the real Keyframes'
-- range), so segment lengths are always positive and each waypoint's
-- exact position is always reached at local fraction exactly 0 or 1 --
-- which, combined with `Easing.resolve`'s exact-endpoint guarantee and
-- `Interpolator.interpolate`'s exact-endpoint guarantee (Requirements 4.5,
-- 4.6), is what makes Property 12 ("seeking to each Keyframe's position
-- yields that Keyframe's value") hold exactly rather than approximately.
--
-- CONVENTION (mode / active-phase capture):
-- `to`, `from`, and `fromTo` differ only in *which* side of each
-- PropertyPlan is known eagerly at factory-call time versus captured from
-- the Target when the Tween's active phase begins (Requirements 2.2, 3.1,
-- 3.2, 3.3):
--   - `to`:      endValue known now (destination); startValue captured later.
--   - `from`:    startValue known now (source); endValue captured later.
--   - `fromTo`:  both known now; nothing captured.
-- The Tween instance records which factory created it as an internal
-- `mode` field (not part of the public `Types.Tween` surface, mirroring the
-- `Animation._advancePosition`/`_complete` internal-helper convention) so
-- `_advance` knows which side to capture on first entering the active
-- phase. A `PropertyPlan.startValue`/`endValue` of `nil` means "not yet
-- captured"; `_render` skips a plan until both sides are populated, which
-- only matters if a caller seeks/reads progress on a `to`/`from` Tween
-- before it has ever been played.
--
-- As of task 8.8 (Requirement 6.1, Property 17), "first entering the active
-- phase" is gated on the configured `delay` having elapsed (`self.position
-- >= self.delay`, the internal field resolved from `config.delay`, see
-- `resolveDelayField` below), not merely on `_advance` having been called
-- once -- `self.started` still flips `false` -> `true` exactly once per
-- play-through (or per `restart`, which resets it back to `false`), it
-- just now flips on the update where the delay elapses rather than on the
-- very first update after `play`/`restart`. See `_advance` below.
--
-- CONVENTION (property existence check):
-- Requirements 2.7 and 3.6 require raising when a named property does not
-- exist on the Target, checked eagerly at factory-call time. For an
-- `Instance` Target, reading an undefined property raises a Lua error, so
-- existence is checked by reading the property inside `pcall`. For a plain
-- table Target, indexing never raises (missing keys simply read as `nil`),
-- so there is no way to distinguish "key absent" from "key present with a
-- value of `nil`" -- but every type the Interpolator supports is a non-nil
-- Roblox value (Requirement 4.1), so a legitimate current property value is
-- never `nil` anyway. Treating a `nil` read as "missing" is therefore safe
-- for both Target shapes, which lets a single `pcall`-wrapped read serve
-- both cases below (see `propertyExists`).

-- CONVENTION (stagger across multiple targets, Requirement 11, task 10.1):
-- `to`/`from`/`fromTo` each accept either a single Target or an ordered
-- list of Targets (`Types.Target | { Types.Target }`, matching design.md's
-- `init.luau` factory signature). A plain-table Target (see `Types.Target`)
-- and an ordered list of Targets are both Luau tables, so they must be told
-- apart by shape rather than by `typeof`: `isTargetList` (below) treats the
-- argument as a Target list only when it is a non-Instance table whose
-- *every* value is itself a Target-shaped value (an `Instance`, or a plain
-- table) -- i.e. a dense array of Targets -- while any other table (no
-- entries, or any non-Target-shaped value) is treated as a single
-- plain-table Target instead, preserving every existing single-Target
-- call site's behavior unchanged. `Instance` Targets are never ambiguous
-- (`typeof(target) == "Instance"` short-circuits to "single Target"
-- immediately).
--
-- Once a call is identified as multi-Target, `resolveTargetList` produces
-- the ordered `{ Types.Target }` array the rest of this module already
-- expects (a bare list of one for the single-Target case), and validates
-- Requirement 11.5 (empty Targets list) via `Errors.emptyTargetsList`
-- before anything else runs. `resolveStagger` (above) validates and
-- resolves `config.stagger` -- Requirement 11.4 -- once per factory call,
-- shared across every target in the list.
--
-- `Tween.new` (below) is the single shared constructor for both the
-- single- and multi-Target cases: it builds one `PerTargetPlan` per
-- Target (see `Types.PerTargetPlan`) with `startOffset = (i - 1) * S`
-- (`i` 1-based -> 0-based per Requirement 11.1, `S` the resolved stagger
-- value; `S = 0`, the default, collapses every offset to 0 per
-- Requirement 11.3) and computes the returned single Animation's
-- `duration` as `(n - 1) * S + iterationDuration` (Requirement 11.2) --
-- `n = 1` (the single-Target case) collapses this to exactly
-- `iterationDuration`, i.e. unchanged from before this task. Because a
-- staggered Tween is still exactly one `Animation` instance whose control
-- methods (`play`/`pause`/`resume`/etc.) are inherited unmodified from
-- `Animation.luau`, every control operates on all staggered per-target
-- plans as a single unit automatically (Requirement 11.2's "controls act
-- on all staggered Tweens as one unit") -- no separate wiring is needed.
--
-- Each target's local interpolation window is `[startOffset, startOffset +
-- iterationDuration]` (plus that target's own delay/repeat/repeatDelay
-- expansion, Requirement 6) measured against the *shared* Animation
-- timeline (`self.position`). `captureActivePhase`/`_render` (below) both
-- already loop over every entry of `self.resolved`; they are extended to
-- subtract each `targetPlan.startOffset` from `self.position` before
-- computing that target's own elapsed/iteration/render state, so a target
-- whose window has not yet opened (elapsed < 0) is simply skipped for that
-- update (holding at nothing yet -- no property write occurs, mirroring
-- the existing pre-delay behavior), and a target whose window has already
-- closed keeps rendering at its own final iteration state exactly as a
-- single-Target Tween already holds at its end value (see module header
-- CONVENTION (delay/repeat/yoyo/repeatDelay timeline)) -- there is no
-- separate "trailing hold" mechanism to add; the existing per-iteration
-- clamping in `computeIterationState` already produces it once each
-- target's own elapsed time is offset correctly.
--
-- `captureActivePhase` also moves from a single Tween-wide `self.started`
-- gate to a per-target `targetPlan.captured` gate (`Types.PerTargetPlan`),
-- since each target's active phase now begins at a different moment
-- (its own `startOffset`) rather than all at once; `self.started`/
-- `onStart` still fire exactly once for the whole Animation, at the
-- moment the *first* target's window opens (i.e. `startOffset == 0`,
-- always true for at least the first target per Requirement 11.1),
-- unchanged from before this task.

local Types = require(script.Parent.Types)
local Animation = require(script.Parent.Animation)
local Interpolator = require(script.Parent.Interpolator)
local Easing = require(script.Parent.Easing)
local Errors = require(script.Parent.Errors)
local RelativeValue = require(script.Parent.RelativeValue)

local DEFAULT_DURATION = 0.5

-- Which factory created a given Tween; governs active-phase capture in
-- `_advance` (see module header CONVENTION above). Not part of the public
-- `Types.Tween` surface.
type Mode = "to" | "from" | "fromTo"

-- Requirement 11 (task 10.1): the public factory argument shape -- a
-- single Target, or an ordered list of Targets to stagger across (see
-- module header CONVENTION (stagger)). Matches design.md's `init.luau`
-- factory signature (`Target | { Target }`).
type TargetOrTargets = Types.Target | { Types.Target }

-- Internal fields beyond the public `Types.Tween` surface (see module
-- header CONVENTION for delay/repeat/yoyo/repeatDelay, task 8.8):
--   - iterationDuration: per-iteration interpolation length in seconds
--     (what Requirement 2.3/2.4's `duration` config field actually
--     configures -- `self.duration`, inherited from `Animation`, holds the
--     full timeline length instead, see module header).
--   - delay: Requirement 6.1, seconds to wait before the first iteration.
--   - repeatCount: Requirement 6.2/6.3, -1 (infinite) or 0..1_000_000.
--   - repeatDelay: Requirement 6.5, seconds between iterations only.
--   - yoyo: Requirement 6.4, alternate iteration direction when true.
type InternalTween = Types.Tween & {
	mode: Mode,
	iterationDuration: number,
	-- Precomputed reciprocals so the per-frame iteration math uses multiply
	-- instead of divide: invIterationDuration = 1/iterationDuration,
	-- invCycleLength = 1/(iterationDuration + repeatDelay).
	invIterationDuration: number,
	invCycleLength: number,
	delay: number,
	repeatCount: number,
	repeatDelay: number,
	yoyo: boolean,
	-- Requirement 8 (task 8.15): resolved Easing_Function for each entry of
	-- `self.keyframes`, in the same sorted order -- kept as a parallel
	-- internal array rather than mutating the public `Types.Keyframe`
	-- values stored in `self.keyframes` (see module header CONVENTION
	-- (keyframe waypoints)). `nil` when no `keyframes` were configured.
	keyframeEase: { Types.Easing_Function }?,
	-- Requirement 8 (task 8.15): the full ordered list of waypoint
	-- positions (0..1) a keyframed Tween interpolates through, including
	-- synthetic position-0/position-1 bookends when needed (see
	-- `buildKeyframeWaypoints`/module header CONVENTION). `nil` when no
	-- `keyframes` were configured.
	keyframeWaypoints: { KeyframeWaypoint }?,
	-- Requirement 13 (task 8.18): iteration-boundary bookkeeping for
	-- onRepeat/onComplete (Requirements 13.3-13.6). `lastCompletedIterations`
	-- is the number of iterations that had fully completed as of the most
	-- recent `_advance` call (see `computeCompletedIterations` below);
	-- comparing it against the freshly computed count on the next
	-- `_advance` call is how a boundary crossing is detected and each
	-- newly-completed iteration's callback is fired exactly once, rather
	-- than being recomputed/re-fired from scratch every frame.
	-- `completeFired` guards `onComplete` firing more than once per
	-- play-through (Property 31), since -- unlike `started` -- a
	-- finite-repeat Tween's `state` never transitions to `"completed"` on
	-- its own (see module header CONVENTION (delay/repeat/yoyo/repeatDelay
	-- timeline): detachment is a later task). Both fields are reset by the
	-- `Tween.restart` override below so a restarted Tween's lifecycle
	-- callbacks can fire again for its new play-through, mirroring
	-- `started`'s own reset-on-restart behavior (Requirement 13.1's "since
	-- it was created or restarted").
	lastCompletedIterations: number,
	completeFired: boolean,
	-- Performance fast-path flags (not part of the public surface):
	--   hasCallbacks: true when at least one of onStart/onUpdate/onComplete/
	--     onRepeat was configured. When false, `_advance` skips the entire
	--     per-frame iteration-boundary computation (Requirement 13) and uses
	--     a cheap `position >= duration` check for finite-repeat completion
	--     detachment instead -- the common "fire-and-forget" tween pays no
	--     per-frame callback-bookkeeping cost.
	--   fullyCaptured: set once every alive target has captured its active
	--     phase, so `captureActivePhase` can early-out instead of re-scanning
	--     every target every frame for the entire life of the tween.
	hasCallbacks: boolean,
	fullyCaptured: boolean,
}

-- Requirement 8 (task 8.15): one entry of `InternalTween.keyframeWaypoints`.
-- `keyframeIndex` is a 1-based index into `self.keyframes`/`self.keyframeEase`
-- identifying a real configured Keyframe, or `nil` for a synthetic bookend
-- whose value/ease instead come from the PropertyPlan's own startValue/
-- endValue and the Tween's own overall `self.ease` (see module header
-- CONVENTION (keyframe waypoints)).
type KeyframeWaypoint = {
	position: number,
	keyframeIndex: number?,
}

local Tween = setmetatable({}, { __index = Animation })
Tween.__index = Tween

-- ---------------------------------------------------------------------------
-- Small internal helpers
-- ---------------------------------------------------------------------------

--- Reads `target[propertyName]` directly. Callers are expected to have
--- already validated the property exists (via `propertyExists`) before this
--- is used to capture a start/end value.
local function readProperty(target: Types.Target, propertyName: string): any
	return (target :: any)[propertyName]
end

--- Writes `value` onto `target[propertyName]` directly.
local function writeProperty(target: Types.Target, propertyName: string, value: any): ()
	(target :: any)[propertyName] = value
end

--- Requirements 2.7, 3.6: reports whether `propertyName` exists on `target`.
--- See module header CONVENTION for why a single `pcall`-wrapped read
--- suffices for both Instance and plain-table Targets.
local function propertyExists(target: Types.Target, propertyName: string): boolean
	local ok, value = pcall(function()
		return (target :: any)[propertyName]
	end)
	return ok and value ~= nil
end

--- Requirement 7.3: resolves `rawValue` against `startValue` if `rawValue`
--- is a Relative_Value string (e.g. `"+=100"`), returning the resolved
--- number. Concrete values (numbers, Vector3, etc.) are not strings and
--- pass through unchanged. `propertyName` is forwarded to
--- `RelativeValue.resolve` so `Errors.nonNumericRelativeStart` (Req 7.6)
--- names the offending property.
local function resolveEndValue(rawValue: any, startValue: any, propertyName: string): any
	if typeof(rawValue) ~= "string" then
		return rawValue
	end

	return RelativeValue.resolve(startValue, rawValue, propertyName)
end

-- ---------------------------------------------------------------------------
-- Requirements 15.1, 15.4: destroyed-target detection (task 8.23)
-- ---------------------------------------------------------------------------

--- Requirement 15.1: reports whether `target` should still be treated as
--- alive. A plain-table Target (see `Types.Target`/module header
--- CONVENTION (property existence check)) has no "destroyed"/"parent"
--- concept, so it is always alive. An `Instance` Target is alive as long
--- as its `Parent` is non-nil: `:Destroy()` explicitly sets `Parent` to
--- `nil` and locks it there, so checking `Parent == nil` each render is
--- the standard destroyed-instance check -- and matches Requirement 15.1's
--- own wording ("destroyed OR its parent becomes nil") exactly, since a
--- reparented-to-nil-but-not-destroyed Instance is dropped by this check
--- too.
local function isTargetAlive(target: Types.Target): boolean
	if typeof(target) ~= "Instance" then
		return true
	end

	-- Reading `.Parent` on a normal Instance never errors, so this is done
	-- directly (no pcall/closure) -- this runs once per live target every
	-- frame, so avoiding a per-call closure allocation here matters a lot at
	-- high target counts.
	return (target :: Instance).Parent ~= nil
end

--- Requirements 15.1, 15.4: checks every currently-alive `targetPlan` in
--- `self.resolved` via `isTargetAlive`, flipping `alive` to `false` for
--- any target found destroyed/parent-nil. From that point on, every
--- existing `if not targetPlan.alive then continue end` guard already
--- present in `captureActivePhase`/`_render` skips it, which is sufficient
--- to satisfy "stops applying property changes to that target and removes
--- it from the Animation's active target set" (Requirement 15.1) --
--- physically removing the entry from `self.resolved` is unnecessary and
--- more error-prone, per the module header CONVENTION for this field.
--- Written as a plain loop over `self.resolved` (rather than assuming
--- exactly one entry) so it composes unmodified once task 10 adds
--- multiple targets.
---
--- When every targetPlan in `self.resolved` is (now) dead, detaches the
--- Tween from the Scheduler by calling `Animation._complete`
--- (Requirement 15.4) -- module-qualified, per Animation.luau's
--- documented internal-helper convention (see this module's own header).
--- Guarded on the Tween not already being `"killed"`/`"completed"`:
--- `Animation._complete` is itself safe to call more than once, but this
--- avoids redundant work on every subsequent render of an
--- already-detached Tween.
--- Requirements 12.7, 15.2, 15.4 (task 12.1): releases this Tween's
--- references to its Targets so they become eligible for garbage collection
--- once the Tween no longer needs them. Called on `kill` (Requirements
--- 12.7, 15.2 -- terminal; controls no-op afterward) and when the last live
--- Target is removed (Requirement 15.4, from `dropDeadTargets` below -- the
--- Targets are already dead/gone at that point). Replaces the
--- Target-holding tables with empty ones (rather than `nil`) so the fields
--- stay type-consistent with `Types.Tween` under `--!strict`; after this
--- runs, `_render`/`captureActivePhase` simply iterate an empty
--- `self.resolved` and do nothing.
---
--- Deliberately NOT called on natural completion (Requirement 15.3): a
--- naturally-completed Tween detaches from the Scheduler (releasing the
--- Scheduler's reference to it and halting all per-frame work and Target
--- writes) but retains its resolved plans so it can still be `restart`ed
--- and continues to hold its final rendered value -- standard GSAP-style
--- behavior.
local function releaseTargets(self: InternalTween): ()
	self.targets = {}
	self.resolved = {}
	self.staggerOffset = {}
end

local function dropDeadTargets(self: InternalTween): ()
	local anyAlive = false

	for _, targetPlan in self.resolved do
		if targetPlan.alive and not isTargetAlive(targetPlan.target) then
			targetPlan.alive = false
		end

		if targetPlan.alive then
			anyAlive = true
		end
	end

	if not anyAlive and self.state ~= "killed" and self.state ~= "completed" then
		Animation._complete(self)
		-- Requirement 15.4 (task 12.1): the last live Target has been
		-- removed, so release references to the (now all dead) Targets.
		releaseTargets(self)
	end
end

--- Requirements 2.6, 3.5: reports whether `map` is non-nil and has at least
--- one entry.
local function hasAtLeastOneProperty(map: Types.PropertyMap?): boolean
	if map == nil then
		return false
	end
	for _ in map do
		return true
	end
	return false
end

--- Requirements 2.7, 3.6: raises via `Errors.missingProperty` for the first
--- property named in `map` that does not exist on `target`.
local function validatePropertiesExist(target: Types.Target, map: Types.PropertyMap): ()
	for propertyName in map do
		if not propertyExists(target, propertyName) then
			Errors.missingProperty(propertyName, target)
		end
	end
end

--- Requirement 3.4: raises via `Errors.fromToKeyMismatch` when `startMap`
--- and `endMap` do not contain exactly the same set of property names.
local function validateKeySets(startMap: Types.PropertyMap, endMap: Types.PropertyMap): ()
	local startKeys: { string } = {}
	local endKeys: { string } = {}
	local endSet: { [string]: boolean } = {}

	for propertyName in endMap do
		table.insert(endKeys, propertyName)
		endSet[propertyName] = true
	end

	local mismatch = false
	local startCount = 0
	for propertyName in startMap do
		table.insert(startKeys, propertyName)
		startCount += 1
		if not endSet[propertyName] then
			mismatch = true
		end
	end

	if startCount ~= #endKeys then
		mismatch = true
	end

	if mismatch then
		table.sort(startKeys)
		table.sort(endKeys)
		Errors.fromToKeyMismatch(startKeys, endKeys)
	end
end

--- Requirement 2.4: validates and resolves `config.duration`, defaulting to
--- 0.5 seconds when omitted (Requirement 2.3).
local function resolveDuration(config: Types.Tween_Config): number
	local duration = config.duration

	if duration == nil then
		return DEFAULT_DURATION
	end

	if typeof(duration) ~= "number" or duration <= 0 then
		Errors.invalidDuration(duration)
		return 0 -- unreachable: Errors.invalidDuration always raises
	end

	return duration
end

local MAX_DELAY = 86400
local MAX_REPEAT = 1000000

--- Requirement 6.7: validates `config["repeat"]` (`repeat` is a Luau
--- reserved word, so it is read via bracket syntax throughout this module,
--- per design.md "Tween_Config"), defaulting to 0 when omitted (Requirement
--- 6.6). Valid values are exactly -1 (infinite), or a non-negative integer
--- up to `MAX_REPEAT` inclusive.
local function resolveRepeat(config: Types.Tween_Config): number
	local repeatCount = config["repeat"]

	if repeatCount == nil then
		return 0
	end

	if typeof(repeatCount) ~= "number" then
		Errors.invalidRepeat(repeatCount)
		return 0 -- unreachable: Errors.invalidRepeat always raises
	end

	if repeatCount == -1 then
		return -1
	end

	if repeatCount < 0 or repeatCount ~= math.floor(repeatCount) or repeatCount > MAX_REPEAT then
		Errors.invalidRepeat(repeatCount)
		return 0 -- unreachable: Errors.invalidRepeat always raises
	end

	return repeatCount
end

--- Requirement 6.8: validates `config[fieldName]` (`delay` or
--- `repeatDelay`) is either omitted (defaulting to 0, Requirement 6.6) or a
--- number in the closed interval `[0, MAX_DELAY]`.
local function resolveDelayField(config: Types.Tween_Config, fieldName: "delay" | "repeatDelay"): number
	local value = (config :: any)[fieldName]

	if value == nil then
		return 0
	end

	if typeof(value) ~= "number" or value < 0 or value > MAX_DELAY then
		Errors.invalidDelay(fieldName, value)
		return 0 -- unreachable: Errors.invalidDelay always raises
	end

	return value
end

--- Requirement 6.6: resolves `config.yoyo`, defaulting to `false` when
--- omitted. Requirement 6 does not specify a validation error for a
--- non-boolean `yoyo` -- only `repeat`/`delay`/`repeatDelay` have dedicated
--- `Errors.*` builders (6.7, 6.8) -- so this simply reads the configured
--- value through.
local function resolveYoyo(config: Types.Tween_Config): boolean
	return config.yoyo == true
end

local MAX_STAGGER = 3600

--- Requirement 11.4: validates `config.stagger`, defaulting to 0 when
--- omitted (Requirement 11.3, "0 or omitted starts all targets
--- simultaneously"). Valid values are a number in the closed interval
--- `[0, MAX_STAGGER]`.
local function resolveStagger(config: Types.Tween_Config): number
	local stagger = config.stagger

	if stagger == nil then
		return 0
	end

	if typeof(stagger) ~= "number" or stagger < 0 or stagger > MAX_STAGGER then
		Errors.invalidStagger(stagger)
		return 0 -- unreachable: Errors.invalidStagger always raises
	end

	return stagger
end

-- ---------------------------------------------------------------------------
-- Requirement 11: Target vs ordered Target list detection (task 10.1)
-- ---------------------------------------------------------------------------

--- Reports whether `value` is shaped like a single Target (an `Instance`,
--- or a plain table) -- used by `isTargetList` below to decide whether
--- each array-part entry of a candidate list looks like a Target.
local function isTargetShaped(value: any): boolean
	local ty = typeof(value)
	return ty == "Instance" or ty == "table"
end

--- Requirement 11 (see module header CONVENTION (stagger)): reports
--- whether `value` should be treated as an ordered list of Targets rather
--- than a single plain-table Target. An `Instance` is never ambiguous
--- (never a list). A table is treated as a Target list when it is either
--- completely empty (the empty-Targets-list case, Requirement 11.5 --
--- `resolveTargetList` below raises for this case) or a dense 1..#value
--- array whose every entry is itself Target-shaped, with no extra
--- non-array keys; any other table (e.g. a property-keyed plain-table
--- Target such as `{ Position = ... }`) is treated as a single Target.
local function isTargetList(value: any): boolean
	if typeof(value) ~= "table" then
		return false
	end

	local arrayLength = #(value :: { any })

	local totalKeys = 0
	for _ in (value :: any) do
		totalKeys += 1
	end

	if totalKeys == 0 then
		-- Completely empty table: ambiguous between "empty Targets list"
		-- and "single empty plain-table Target" -- resolved in favor of
		-- "empty Targets list" so Requirement 11.5 has a way to trigger.
		return true
	end

	if arrayLength == 0 or arrayLength ~= totalKeys then
		-- No array part, or extra non-array keys present (e.g. a
		-- property-keyed plain-table Target) -- not a Target list.
		return false
	end

	for i = 1, arrayLength do
		if not isTargetShaped((value :: any)[i]) then
			return false
		end
	end

	return true
end

--- Requirement 11.5: normalizes the factory `target` argument into an
--- ordered `{ Types.Target }` list. A single Target (Instance or
--- property-keyed plain table) becomes a one-element list, preserving
--- every existing single-Target call site's behavior unchanged
--- (Requirement 11's "S = 0 or omitted" default collapses this case to
--- the pre-stagger behavior, see module header CONVENTION (stagger)).
--- Raises via `Errors.emptyTargetsList` when `target` is list-shaped
--- (`isTargetList`) but empty.
local function resolveTargetList(target: any): { Types.Target }
	if isTargetList(target) then
		local list = target :: { Types.Target }
		if #list == 0 then
			Errors.emptyTargetsList()
			return {} -- unreachable: Errors.emptyTargetsList always raises
		end
		return list
	end

	return { target :: Types.Target }
end

-- ---------------------------------------------------------------------------
-- Requirement 8: keyframe validation/resolution (task 8.15)
-- ---------------------------------------------------------------------------

--- Requirement 8.4: validates a single Keyframe's `position` is a number in
--- the closed interval [0, 1]; `index` (1-based, matching the caller-
--- supplied `keyframes` list order) is forwarded to `Errors` so the message
--- names which Keyframe was invalid.
local function validateKeyframePosition(position: any, index: number): ()
	if typeof(position) ~= "number" or position < 0 or position > 1 then
		Errors.invalidKeyframePosition(position, index)
	end
end

--- Requirements 8.2, 8.4, 8.7: eagerly validates and resolves
--- `config.keyframes`, returning `nil, nil` when the field is omitted (no
--- keyframes configured -- the Tween behaves exactly as it did before this
--- task). Otherwise returns two same-length, same-order arrays: the
--- configured Keyframes sorted ascending by `position` (Requirement 8.1
--- describes ascending *playback* order, not an input-ordering
--- requirement, so callers may supply `keyframes` in any order -- see
--- module header CONVENTION (keyframe waypoints)), and each Keyframe's
--- resolved `Easing_Function` (via `Easing.resolve`, which already
--- defaults to Quad.InOut when `ease` is omitted, satisfying Requirement
--- 8.5).
local function resolveKeyframes(config: Types.Tween_Config): ({ Types.Keyframe }?, { Types.Easing_Function }?)
	local rawKeyframes = config.keyframes

	if rawKeyframes == nil then
		return nil, nil
	end

	if #rawKeyframes == 0 then
		Errors.invalidKeyframesList("the keyframes list must not be empty")
		return nil, nil -- unreachable: Errors.invalidKeyframesList always raises
	end

	for index, keyframe in rawKeyframes do
		validateKeyframePosition(keyframe.position, index)
	end

	-- Copy before sorting so the caller's own `config.keyframes` table (and
	-- any list they hold a reference to) is never mutated.
	local sorted: { Types.Keyframe } = table.clone(rawKeyframes)
	table.sort(sorted, function(a, b)
		return a.position < b.position
	end)

	-- Requirement 8.7: two or more Keyframes sharing the same fractional
	-- position -- checked after sorting so any pair of equal positions is
	-- always adjacent.
	for i = 2, #sorted do
		if sorted[i].position == sorted[i - 1].position then
			Errors.invalidKeyframesList(
				string.format(
					"two or more Keyframes share the fractional position %s",
					tostring(sorted[i].position)
				)
			)
			return nil, nil -- unreachable: Errors.invalidKeyframesList always raises
		end
	end

	local eases: { Types.Easing_Function } = {}
	for i, keyframe in sorted do
		eases[i] = Easing.resolve(keyframe.ease)
	end

	return sorted, eases
end

--- Requirement 8.6: given the sorted `keyframes` list (already validated by
--- `resolveKeyframes`), builds the full ordered waypoint list a keyframed
--- Tween interpolates through, prepending a synthetic position-0 bookend
--- when the earliest real Keyframe's position is greater than 0, and
--- appending a synthetic position-1 bookend when the latest real
--- Keyframe's position is less than 1 -- see module header CONVENTION
--- (keyframe waypoints) for why both bookends are static/positional and
--- safe to compute once here, at construction time. Returns `nil` when
--- `keyframes` is `nil`.
local function buildKeyframeWaypoints(keyframes: { Types.Keyframe }?): { KeyframeWaypoint }?
	if keyframes == nil then
		return nil
	end

	local waypoints: { KeyframeWaypoint } = {}

	if keyframes[1].position > 0 then
		table.insert(waypoints, { position = 0, keyframeIndex = nil })
	end

	for i in keyframes do
		table.insert(waypoints, { position = keyframes[i].position, keyframeIndex = i })
	end

	if keyframes[#keyframes].position < 1 then
		table.insert(waypoints, { position = 1, keyframeIndex = nil })
	end

	return waypoints
end

-- ---------------------------------------------------------------------------
-- Internal constructor
-- ---------------------------------------------------------------------------

--- Constructs a (possibly staggered, Requirement 11, task 10.1) Tween from
--- already-validated per-target `plansPerTarget`. Not part of the public
--- factory surface -- `to`/`from`/`fromTo` below build one plans array per
--- entry of `targets` (per their differing capture semantics, see module
--- header) and call into this shared constructor once all eager
--- validation has passed. `targets`/`plansPerTarget` are same-length,
--- same-order arrays; a single-Target call (the common case) is simply
--- `#targets == 1`, which collapses every formula below to its pre-stagger
--- value (see module header CONVENTION (stagger)).
function Tween.new(
	targets: { Types.Target },
	mode: Mode,
	plansPerTarget: { { Types.PropertyPlan } },
	config: Types.Tween_Config
): Types.Tween
	local iterationDuration = resolveDuration(config)
	local ease = Easing.resolve(config.ease)

	-- Requirement 6: eager validation, defaults applied per Requirement 6.6.
	local delay = resolveDelayField(config, "delay")
	local repeatCount = resolveRepeat(config)
	local repeatDelay = resolveDelayField(config, "repeatDelay")
	local yoyo = resolveYoyo(config)

	-- Requirement 11.4: eager validation/resolution, task 10.1. Defaults
	-- to 0 when omitted (Requirement 11.3).
	local stagger = resolveStagger(config)

	-- Requirement 8: eager validation/resolution, task 8.15.
	local keyframes, keyframeEase = resolveKeyframes(config)
	local keyframeWaypoints = buildKeyframeWaypoints(keyframes)

	-- See module header CONVENTION (delay/repeat/yoyo/repeatDelay timeline,
	-- task 8.8): `perTweenDuration` (the per-target "D" of Requirement
	-- 11.2's `(n-1)*S + D` formula) is one target's full timeline length,
	-- not the per-iteration interpolation length (`iterationDuration`,
	-- kept separately below).
	local perTweenDuration: number
	if repeatCount == -1 then
		perTweenDuration = math.huge
	else
		perTweenDuration = delay + iterationDuration * (repeatCount + 1) + repeatDelay * repeatCount
	end

	-- Requirement 11.1, 11.2: startOffset = (i - 1) * S per target
	-- (0-based); total duration = (n - 1) * S + D. `n == 1` (the
	-- single-Target case) collapses `startOffset` to 0 and `duration` to
	-- exactly `perTweenDuration`, unchanged from before this task.
	-- `math.huge + finite` stays `math.huge`, so an infinite-repeat
	-- staggered Tween's `duration` remains `math.huge` too.
	local n = #targets
	local duration = perTweenDuration + (n - 1) * stagger

	local base = Animation.new(duration)

	local resolved: { Types.PerTargetPlan } = {}
	local staggerOffset: { [Types.Target]: number } = {}
	for i, target in targets do
		local startOffset = (i - 1) * stagger
		table.insert(resolved, {
			target = target,
			startOffset = startOffset,
			plans = plansPerTarget[i],
			alive = true,
			captured = false,
		})
		staggerOffset[target] = startOffset
	end

	local self = base :: any
	self.targets = targets
	self.resolved = resolved
	self.config = config
	self.ease = ease
	self.keyframes = keyframes
	self.staggerOffset = staggerOffset
	self.mode = mode :: Mode
	self.iterationDuration = iterationDuration
	self.invIterationDuration = 1 / iterationDuration
	self.invCycleLength = 1 / (iterationDuration + repeatDelay)
	self.delay = delay
	self.repeatCount = repeatCount
	self.repeatDelay = repeatDelay
	self.yoyo = yoyo
	self.keyframeEase = keyframeEase
	self.keyframeWaypoints = keyframeWaypoints
	-- Requirement 13 (task 8.18): no iterations completed yet, onComplete
	-- not yet fired -- see `InternalTween.lastCompletedIterations`/
	-- `completeFired` doc comment above.
	self.lastCompletedIterations = 0
	self.completeFired = false
	-- Performance fast-path flags (see InternalTween). `hasCallbacks` is
	-- computed once here from the config so the per-frame path never has to
	-- re-check four fields.
	self.hasCallbacks = config.onStart ~= nil
		or config.onUpdate ~= nil
		or config.onComplete ~= nil
		or config.onRepeat ~= nil
	self.fullyCaptured = false
	-- Only isolate (per-frame pcall in the Scheduler) when user callbacks
	-- may run. A callback-free Tween is pure interpolation and is advanced
	-- directly for speed (see Scheduler.step).
	self.needsIsolation = self.hasCallbacks

	return (setmetatable(self, Tween) :: any) :: Types.Tween
end

-- ---------------------------------------------------------------------------
-- Requirement 2: `to` factory
-- ---------------------------------------------------------------------------

--- WHEN called with a non-nil Target (or an ordered, non-empty list of
--- Targets to stagger across, Requirement 11), a Property_Map with at
--- least one property, and a Tween_Config, returns a Tween that
--- interpolates each named property from each Target's current value
--- (captured when that Target's own active phase begins, Requirement 2.2)
--- to the corresponding Property_Map value (Requirement 2.1).
function Tween.to(target: TargetOrTargets?, propertyMap: Types.PropertyMap?, config: Types.Tween_Config?): Types.Tween
	if target == nil then
		Errors.nilTarget()
		return (nil :: any) :: Types.Tween -- unreachable: Errors.nilTarget always raises
	end

	if not hasAtLeastOneProperty(propertyMap) then
		Errors.emptyPropertyMap(propertyMap)
		return (nil :: any) :: Types.Tween -- unreachable: Errors.emptyPropertyMap always raises
	end

	local map = propertyMap :: Types.PropertyMap
	local targets = resolveTargetList(target)

	local plansPerTarget: { { Types.PropertyPlan } } = {}
	for i, singleTarget in targets do
		validatePropertiesExist(singleTarget, map)

		local plans: { Types.PropertyPlan } = {}
		for propertyName, destinationValue in map do
			table.insert(plans, {
				property = propertyName,
				startValue = nil, -- captured when the active phase begins (Req 2.2)
				endValue = destinationValue,
				valueType = typeof(destinationValue),
			})
		end
		plansPerTarget[i] = plans
	end

	return Tween.new(targets, "to", plansPerTarget, config or {})
end

-- ---------------------------------------------------------------------------
-- Requirement 3: `from` factory
-- ---------------------------------------------------------------------------

--- WHEN called with a non-nil Target (or an ordered, non-empty list of
--- Targets to stagger across, Requirement 11), a non-empty Property_Map,
--- and a Tween_Config, returns a Tween that interpolates each named
--- property from the Property_Map value (the source, set on each Target
--- within the same update that Target's own active phase begins,
--- Requirement 3.2) to that Target's value captured at that same moment
--- (Requirement 3.1).
function Tween.from(target: TargetOrTargets?, propertyMap: Types.PropertyMap?, config: Types.Tween_Config?): Types.Tween
	if target == nil then
		Errors.nilTarget()
		return (nil :: any) :: Types.Tween -- unreachable: Errors.nilTarget always raises
	end

	if not hasAtLeastOneProperty(propertyMap) then
		Errors.emptyPropertyMap(propertyMap)
		return (nil :: any) :: Types.Tween -- unreachable: Errors.emptyPropertyMap always raises
	end

	local map = propertyMap :: Types.PropertyMap
	local targets = resolveTargetList(target)

	local plansPerTarget: { { Types.PropertyPlan } } = {}
	for i, singleTarget in targets do
		validatePropertiesExist(singleTarget, map)

		local plans: { Types.PropertyPlan } = {}
		for propertyName, sourceValue in map do
			table.insert(plans, {
				property = propertyName,
				startValue = sourceValue,
				endValue = nil, -- captured when the active phase begins (Req 3.1)
				valueType = typeof(sourceValue),
			})
		end
		plansPerTarget[i] = plans
	end

	return Tween.new(targets, "from", plansPerTarget, config or {})
end

-- ---------------------------------------------------------------------------
-- Requirement 3: `fromTo` factory
-- ---------------------------------------------------------------------------

--- WHEN called with a non-nil Target (or an ordered, non-empty list of
--- Targets to stagger across, Requirement 11), a non-empty start
--- Property_Map, a non-empty end Property_Map (with the same set of
--- property names, Requirement 3.4), and a Tween_Config, returns a Tween
--- that interpolates each named property from the start Property_Map
--- value to the end Property_Map value (Requirement 3.3). No
--- current-value capture occurs.
function Tween.fromTo(
	target: TargetOrTargets?,
	startPropertyMap: Types.PropertyMap?,
	endPropertyMap: Types.PropertyMap?,
	config: Types.Tween_Config?
): Types.Tween
	if target == nil then
		Errors.nilTarget()
		return (nil :: any) :: Types.Tween -- unreachable: Errors.nilTarget always raises
	end

	if not hasAtLeastOneProperty(startPropertyMap) then
		Errors.emptyPropertyMap(startPropertyMap)
		return (nil :: any) :: Types.Tween -- unreachable: Errors.emptyPropertyMap always raises
	end

	if not hasAtLeastOneProperty(endPropertyMap) then
		Errors.emptyPropertyMap(endPropertyMap)
		return (nil :: any) :: Types.Tween -- unreachable: Errors.emptyPropertyMap always raises
	end

	local startMap = startPropertyMap :: Types.PropertyMap
	local endMap = endPropertyMap :: Types.PropertyMap

	validateKeySets(startMap, endMap)

	local targets = resolveTargetList(target)

	local plansPerTarget: { { Types.PropertyPlan } } = {}
	for i, singleTarget in targets do
		validatePropertiesExist(singleTarget, startMap)
		validatePropertiesExist(singleTarget, endMap)

		local plans: { Types.PropertyPlan } = {}
		for propertyName, startValue in startMap do
			-- Requirement 7.3: startValue is already known here (nothing
			-- deferred for fromTo), so a Relative_Value end Property_Map
			-- value is resolved against it immediately -- see module
			-- header CONVENTION above.
			local endValue = resolveEndValue(endMap[propertyName], startValue, propertyName)
			table.insert(plans, {
				property = propertyName,
				startValue = startValue,
				endValue = endValue,
				valueType = typeof(startValue),
			})
		end
		plansPerTarget[i] = plans
	end

	return Tween.new(targets, "fromTo", plansPerTarget, config or {})
end

-- ---------------------------------------------------------------------------
-- Active-phase capture (Requirements 2.2, 3.1, 3.2, 3.3)
-- ---------------------------------------------------------------------------

--- Called once per target -- the first time *that target's own* staggered
--- window opens (see `_advance` below, and module header CONVENTION
--- (stagger)), gated by `targetPlan.captured` rather than the Tween-wide
--- `self.started` (which still exists, but now only gates the whole
--- Animation's single `onStart` firing -- Requirement 11.1's first target
--- always opens at offset 0, so `self.started` and the first target's
--- `captured` flip together). For `to`, captures each property's current
--- Target value as its start value. For `from`, captures each property's
--- current Target value as its end value and immediately writes the
--- Property_Map's (source) value onto the Target, before any interpolated
--- value is ever applied (Requirement 3.2). For `fromTo`, both sides were
--- already fully resolved at construction time, so there is nothing to
--- capture.
local function captureActivePhase(self: InternalTween): ()
	local mode = self.mode

	-- Fast path: `fromTo` never captures, and once every target has captured
	-- its active phase there is nothing left to do -- skip the whole scan.
	if mode == "fromTo" or self.fullyCaptured then
		return
	end

	local pending = false

	for _, targetPlan in self.resolved do
		if not targetPlan.alive or targetPlan.captured then
			continue
		end

		local elapsedForTarget = self.position - self.delay - targetPlan.startOffset
		if elapsedForTarget < 0 then
			-- this target's window has not opened yet; still pending
			pending = true
			continue
		end

		local target = targetPlan.target

		for _, plan in targetPlan.plans do
			if mode == "to" then
				plan.startValue = readProperty(target, plan.property)
				-- Requirement 7.3: startValue is only known as of the line
				-- above, so a Relative_Value endValue is resolved here,
				-- immediately after capture -- see module header
				-- CONVENTION above. Resolved exactly once: this function
				-- only ever runs once per target (guarded by
				-- `targetPlan.captured` above).
				plan.endValue = resolveEndValue(plan.endValue, plan.startValue, plan.property)
				-- `valueType` was recorded as `typeof(destinationValue)` at
				-- construction time in `Tween.to` (see that factory), which
				-- is "string" for a still-unresolved Relative_Value. Now
				-- that `endValue` is a concrete resolved number, refresh
				-- `valueType` to match so it stays meaningful for any
				-- future caller that reads it post-resolution (it is not
				-- read anywhere within this module today).
				plan.valueType = typeof(plan.endValue)
			elseif mode == "from" then
				plan.endValue = readProperty(target, plan.property)
				writeProperty(target, plan.property, plan.startValue)
			end
		end

		targetPlan.captured = true
	end

	-- No target is still waiting for its window to open, so every alive
	-- target has now captured -- flip the fast-path flag so subsequent
	-- frames early-out at the top instead of re-scanning `self.resolved`.
	if not pending then
		self.fullyCaptured = true
	end
end

-- ---------------------------------------------------------------------------
-- Iteration/delay/repeatDelay math (Requirement 6, task 8.8)
-- ---------------------------------------------------------------------------

--- Given `elapsed` seconds measured from the moment the active phase began
--- (i.e. `self.position - self.delay`, already known to be `>= 0` by every
--- caller below), returns the 0-based iteration index that elapsed time
--- falls within and the local interpolation fraction (0..1) within that
--- iteration, honoring `repeatDelay` (Requirement 6.5) as a hold-at-final-
--- value window between iterations and, for a finite `repeatCount`
--- (Requirement 6.2), clamping to the final iteration once elapsed time
--- reaches the end of the active phase's content (never counting a
--- trailing `repeatDelay` after the last iteration, per Requirement 6.5).
--- `repeatCount == -1` (Requirement 6.3) never clamps, so the returned
--- iteration index grows without bound as `elapsed` grows -- see module
--- header CONVENTION for why this never needs to "complete".
--- Third return value (Requirement 13, task 8.18): `completedIterations`,
--- the number of iteration boundaries fully crossed as of `elapsed` --
--- i.e. how many iterations have *finished* (as opposed to `iterationIndex`,
--- which identifies the iteration current at `elapsed`, still in progress
--- unless `elapsed` has reached/passed its own boundary). `_advance` (see
--- below) compares successive calls' `completedIterations` against
--- `self.lastCompletedIterations` to detect exactly which boundaries were
--- newly crossed since the previous `_advance`, firing `onRepeat`/
--- `onComplete` for each one in order (Requirements 13.3-13.6) -- this is
--- necessary because `iterationIndex`/`localFraction` alone cannot
--- distinguish "exactly at an iteration's end, still within it" from "just
--- past an iteration's end, now inside its trailing repeatDelay window":
--- both report `localFraction == 1`, which is exactly the distinction a
--- completed-iteration count needs to make.
local function computeIterationState(self: InternalTween, elapsed: number): (number, number, number)
	local iterationDuration = self.iterationDuration
	local repeatDelay = self.repeatDelay
	local repeatCount = self.repeatCount
	local cycleLength = iterationDuration + repeatDelay
	-- Precomputed reciprocals (multiply instead of divide, see Tween.new).
	local invIterationDuration = self.invIterationDuration
	local invCycleLength = self.invCycleLength

	if repeatCount == -1 then
		local cycleIndex = math.floor(elapsed * invCycleLength)
		local posInCycle = elapsed - cycleIndex * cycleLength
		if posInCycle <= iterationDuration then
			return cycleIndex, posInCycle * invIterationDuration, cycleIndex
		end
		return cycleIndex, 1, cycleIndex + 1
	end

	local totalIterations = repeatCount + 1
	-- Total length of the active phase's content, deliberately excluding a
	-- trailing repeatDelay after the final iteration (Requirement 6.5).
	local maxElapsed = iterationDuration * totalIterations + repeatDelay * (totalIterations - 1)

	if elapsed >= maxElapsed then
		-- Natural-completion boundary: this is where `onComplete` fires
		-- from `_advance` below (or `onRepeat`, if a caller seeks past a
		-- non-final iteration boundary before this point). See module
		-- header CONVENTION: no detachment logic is wired up yet.
		return totalIterations - 1, 1, totalIterations
	end

	local cycleIndex = math.floor(elapsed * invCycleLength)
	local posInCycle = elapsed - cycleIndex * cycleLength
	if posInCycle <= iterationDuration then
		return cycleIndex, posInCycle * invIterationDuration, cycleIndex
	end
	-- posInCycle > iterationDuration means elapsed is inside a repeatDelay
	-- window -- the iteration at `cycleIndex` just crossed its boundary;
	-- this is where `onRepeat` fires from `_advance` below for a
	-- non-final iteration.
	return cycleIndex, 1, cycleIndex + 1
end

-- ---------------------------------------------------------------------------
-- Requirement 8: keyframe segment lookup / value resolution (task 8.15)
-- ---------------------------------------------------------------------------

--- Given the full ordered `waypoints` list (always spanning exactly
--- `[0, 1]`, see `buildKeyframeWaypoints`) and the current per-iteration
--- local fraction `t` (0..1), returns the 1-based indices of the two
--- consecutive waypoints bracketing `t` and the local fraction (0..1)
--- within that bracket. Because `waypoints` positions are strictly
--- ascending with no duplicates (enforced by `resolveKeyframes`), and the
--- list always starts at 0 and ends at 1, every `t` in `[0, 1]` falls
--- within exactly one bracket (ties at a shared boundary resolve to the
--- earlier bracket, at local fraction exactly 1 -- see module header
--- CONVENTION (keyframe waypoints) for why this still lands on the exact
--- boundary value, satisfying Property 12).
local function findKeyframeSegment(waypoints: { KeyframeWaypoint }, t: number): (number, number, number)
	local count = #waypoints

	for i = 1, count - 1 do
		local fromWaypoint = waypoints[i]
		local toWaypoint = waypoints[i + 1]

		if t <= toWaypoint.position or i == count - 1 then
			local span = toWaypoint.position - fromWaypoint.position
			local localFraction = (t - fromWaypoint.position) / span
			if localFraction < 0 then
				localFraction = 0
			elseif localFraction > 1 then
				localFraction = 1
			end
			return i, i + 1, localFraction
		end
	end

	-- Unreachable: `waypoints` always spans [0, 1] and `t` is always in
	-- [0, 1] (see `_render`), so the loop above always returns.
	return 1, 2, 0
end

--- Requirement 8.3, 8.5: the Easing_Function that governs the segment
--- ending at `toWaypoint`. A segment ending at a real configured Keyframe
--- uses that Keyframe's own resolved ease (already defaulted to
--- Quad.InOut by `Easing.resolve` when omitted, Requirement 8.5); a
--- segment ending at a synthetic bookend (i.e. the stretch of the
--- timeline before the earliest Keyframe or after the latest one) falls
--- back to the Tween's own overall `self.ease`, since no Keyframe governs
--- that stretch (see module header CONVENTION (keyframe waypoints)).
local function segmentEase(self: InternalTween, toWaypoint: KeyframeWaypoint): Types.Easing_Function
	local index = toWaypoint.keyframeIndex
	if index ~= nil then
		return (self.keyframeEase :: { Types.Easing_Function })[index]
	end
	return self.ease
end

--- Resolves `waypoint`'s value for a single `plan`: a real configured
--- Keyframe's value comes from that Keyframe's `values` Property_Map; a
--- synthetic position-0 bookend uses the plan's own `startValue`
--- (Requirement 8.6's captured current value, for `to` mode); a synthetic
--- position-1 bookend uses the plan's own `endValue`. May return `nil` if
--- a Keyframe's `values` omits this plan's property -- callers guard
--- against that exactly as the non-keyframe render path already guards
--- against an uncaptured `startValue`/`endValue`.
local function keyframeWaypointValue(waypoint: KeyframeWaypoint, plan: Types.PropertyPlan, keyframes: { Types.Keyframe }): any
	local index = waypoint.keyframeIndex
	if index ~= nil then
		return keyframes[index].values[plan.property]
	end
	if waypoint.position <= 0 then
		return plan.startValue
	end
	return plan.endValue
end

-- ---------------------------------------------------------------------------
-- Requirement 13 (task 8.18): restart resets lifecycle-callback bookkeeping
-- ---------------------------------------------------------------------------

--- Overrides `Animation.restart` to additionally reset the iteration-
--- boundary bookkeeping added by this task (`lastCompletedIterations`,
--- `completeFired`) so `onRepeat`/`onComplete` can fire again for the new
--- play-through, mirroring `Animation.restart`'s own reset of `started`
--- (which is what lets `onStart` refire, Requirement 13.1's "since it was
--- created or restarted"). No-op when killed, consistent with every other
--- control method (Requirement 12.12) -- bookkeeping is left untouched
--- rather than reset out from under a no-op restart.
function Tween.restart(self: Types.Tween): Types.Animation
	if self.state == "killed" then
		return Animation.restart(self)
	end

	local internal = (self :: any) :: InternalTween
	internal.lastCompletedIterations = 0
	internal.completeFired = false

	-- Requirement 11 (task 10.1): reset every target's own per-target
	-- capture flag too, mirroring `started`'s reset (`Animation.restart`
	-- below) -- a restarted staggered Tween's targets must all re-capture
	-- their start/end values as their windows re-open, exactly as a
	-- single-Target Tween already re-captures on restart.
	for _, targetPlan in internal.resolved do
		targetPlan.captured = false
		-- Discard specialized lerp closures so they rebuild against the
		-- freshly re-captured start/end values on the next render.
		for _, plan in targetPlan.plans do
			plan.lerp = nil
		end
	end
	-- Targets must re-capture as their windows re-open, so clear the
	-- fully-captured fast-path flag too.
	internal.fullyCaptured = false

	return Animation.restart(self)
end

-- ---------------------------------------------------------------------------
-- `_advance` / `_render` overrides
-- ---------------------------------------------------------------------------

--- Advances local position (via the shared `Animation._advancePosition`
--- helper -- module-qualified per Animation.luau's documented convention),
--- captures start/end values and fires `onStart` exactly once -- on the
--- update where elapsed time first reaches the configured `delay`
--- (Requirement 6.1, Property 17; `self.delay` is 0 by default,
--- Requirement 6.6, which reduces to "the very first `_advance` call"
--- exactly as before task 8.8) -- then re-renders (which fires `onUpdate`,
--- see `_render` below), then fires `onRepeat`/`onComplete` for every
--- iteration boundary newly crossed since the previous `_advance` call.
--- This ordering -- onStart, then the render's onUpdate, then onRepeat/
--- onComplete -- is exactly Requirement 13.6's fixed firing order; see
--- module header CONVENTION (lifecycle callbacks).
function Tween._advance(self: Types.Tween, dt: number): ()
	local internal = (self :: any) :: InternalTween

	-- Requirements 15.1, 15.4: destroyed/parent-nil target detection runs
	-- before any other per-target work this update (capture, position
	-- advancement doesn't touch targets, but `captureActivePhase` below
	-- does) -- see `dropDeadTargets` doc comment above.
	dropDeadTargets(internal)

	Animation._advancePosition(self, dt)

	-- Requirement 11: per-target active-phase capture, run every update
	-- (rather than gated on `self.started`) so a later-staggered target's
	-- own window -- which opens after the first target's -- still gets
	-- captured once it does; `captureActivePhase` itself guards each
	-- target independently via `targetPlan.captured` (see module header
	-- CONVENTION (stagger) and that function's own doc comment), so
	-- calling it unconditionally here is safe and a no-op for every
	-- already-captured target.
	captureActivePhase(internal)

	-- Requirement 13.1: onStart fires once, when the first target's own
	-- window opens (position >= delay -- the first target's startOffset
	-- is always 0 per Requirement 11.1, so this is exactly the same
	-- condition as before this task for the single-Target case).
	if not self.started and self.position >= internal.delay then
		self.started = true

		local onStart = internal.config.onStart
		if onStart ~= nil then
			onStart(self)
		end
	end

	-- Requirement 13.2: onUpdate fires from within `_render` itself (see
	-- below), so it fires here, after onStart and before onRepeat/
	-- onComplete.
	self:_render()

	-- Requirements 13.3, 13.4, 13.5, 13.6: onRepeat/onComplete. Comparing
	-- `computeIterationState`'s `completedIterations` return against
	-- `internal.lastCompletedIterations` (rather than recomputing from
	-- scratch every frame, per this task's requirements) detects exactly
	-- which iteration boundaries were newly crossed since the previous
	-- `_advance` call; looping over every newly-crossed boundary (instead
	-- of firing only the most recent one) ensures a caller that seeks or
	-- sets progress across more than one boundary in a single update still
	-- gets every intermediate boundary's callback, in ascending order.
	if internal.hasCallbacks then
	local elapsed = self.position - internal.delay
	if elapsed >= 0 then
		local _, _, completedIterations = computeIterationState(internal, elapsed)

		if completedIterations > internal.lastCompletedIterations then
			local repeatCount = internal.repeatCount
			-- Requirement 6.2: the final iteration's zero-based index is
			-- `repeatCount` (there are `repeatCount + 1` total iterations,
			-- 0-indexed) for a finite repeat; `nil` for infinite repeat
			-- (Requirement 6.3), so no iteration is ever treated as final
			-- and `onComplete` never fires (Requirement 13.5).
			local finalIterationIndex: number? = if repeatCount == -1 then nil else repeatCount

			for justCompletedIndex = internal.lastCompletedIterations, completedIterations - 1 do
				if finalIterationIndex ~= nil and justCompletedIndex == finalIterationIndex then
					-- Requirement 13.3: onComplete, exactly once.
					if not internal.completeFired then
						internal.completeFired = true
						local onComplete = internal.config.onComplete
						if onComplete ~= nil then
							onComplete(self)
						end
					end
				else
					-- Requirements 13.4, 13.5: onRepeat, for a non-final
					-- completed iteration (or, for infinite repeat, every
					-- completed iteration).
					local onRepeat = internal.config.onRepeat
					if onRepeat ~= nil then
						onRepeat(self, justCompletedIndex)
					end
				end
			end

			internal.lastCompletedIterations = completedIterations
		end
	end
	end

	-- Requirement 15.3 (task 12.1): natural-completion detachment. A
	-- finite-repeat Tween (repeatCount ~= -1; Requirement 6.3's infinite
	-- repeat never completes, Property 14) detaches from the Scheduler once
	-- it is done so it performs no further per-frame work. Guarded on
	-- `state == "playing"` so this only fires for a root Tween actively
	-- driven by the Scheduler: a Tween driven as a Timeline child is
	-- advanced via `_advance(0)` without its state ever being set to
	-- "playing" (see Timeline `_render`), so it never self-detaches out from
	-- under its parent Timeline. `_complete` leaves the resolved plans
	-- intact (unlike `releaseTargets`), so a completed root Tween holds its
	-- final value and stays `restart`able.
	--
	-- When callbacks are configured, `completeFired` (set in the boundary
	-- loop above) is the completion signal. When there are none, that whole
	-- boundary computation is skipped for performance, so completion is
	-- detected with a cheap `position >= duration` check instead
	-- (`self.duration` is the full timeline length -- see module header).
	if internal.repeatCount ~= -1 and self.state == "playing" then
		if internal.hasCallbacks then
			if internal.completeFired then
				Animation._complete(self)
			end
		elseif self.position >= self.duration then
			Animation._complete(self)
		end
	end
end

--- Computes which iteration is current and the local interpolation
--- fraction within it (via `computeIterationState`), applies the `yoyo`
--- direction flip for odd iteration indices (Requirement 6.4 -- see module
--- header CONVENTION: this only changes which side of the pair the eased
--- progress approaches, never the captured `startValue`/`endValue`
--- themselves), and writes each property's interpolated value onto its
--- Target. Before the configured `delay` has elapsed (Requirement 6.1,
--- Property 17), or before a plan's start/end value has been captured
--- (i.e. the Tween has never entered its active phase), no property write
--- (and no `onUpdate`, Requirement 13.2) occurs at all.
function Tween._render(self: Types.Tween): ()
	local internal = (self :: any) :: InternalTween

	-- NOTE: destroyed/parent-nil detection (`dropDeadTargets`) runs once per
	-- frame in `_advance`, before this render, so it is intentionally NOT
	-- repeated here -- doing it in both places doubled the per-target
	-- aliveness scan every frame. A direct `seek`/`progress` (which reaches
	-- `_render` without `_advance`) therefore relies on the next Scheduler
	-- update to drop a target destroyed in between, which matches
	-- Requirement 15.1's "next Scheduler update" wording.

	local waypoints = internal.keyframeWaypoints
	local anyRendered = false
	-- Requirement 13.2: `onUpdate` still fires once per render (not once
	-- per target), passing the *first* live target's own effective local
	-- fraction -- see the doc comment below, and module header CONVENTION
	-- (stagger), for why per-target elapsed time can differ under
	-- stagger. `firstEffectiveT` captures that value the first time any
	-- target actually renders this update.
	local firstEffectiveT: number? = nil

	for _, targetPlan in self.resolved do
		if not targetPlan.alive then
			continue
		end

		-- Requirement 11.1, 11.2 (module header CONVENTION (stagger)):
		-- each target's own local window is offset by its `startOffset`
		-- within the shared Animation timeline (`self.position`), so its
		-- elapsed/iteration/render state is computed against
		-- `self.position - self.delay - targetPlan.startOffset` rather
		-- than the Tween-wide `self.position - self.delay` used before
		-- this task. A target whose window has not yet opened
		-- (elapsed < 0) is skipped entirely for this update -- no
		-- property write occurs, mirroring the existing pre-delay
		-- behavior a single-Target Tween already has.
		local elapsed = self.position - internal.delay - targetPlan.startOffset

		if elapsed < 0 then
			continue
		end

		local iterationIndex, localFraction = computeIterationState(internal, elapsed)

		local effectiveT = localFraction
		if internal.yoyo and iterationIndex % 2 == 1 then
			effectiveT = 1 - localFraction
		end

		if firstEffectiveT == nil then
			firstEffectiveT = effectiveT
		end
		anyRendered = true

		local target = targetPlan.target

		if waypoints == nil then
			local easedProgress = self.ease(effectiveT)

			for _, plan in targetPlan.plans do
				-- Build the specialized lerp closure once (after start/end
				-- are known), then reuse it every frame -- no per-frame
				-- typeof dispatch. Cleared on restart so it rebuilds against
				-- freshly re-captured start/end values.
				local lerp = plan.lerp
				if lerp == nil then
					if plan.startValue == nil or plan.endValue == nil then
						continue
					end
					lerp = Interpolator.buildLerp(plan.startValue, plan.endValue, plan.property)
					plan.lerp = lerp
				end
				writeProperty(target, plan.property, lerp(easedProgress))
			end
		else
			-- Requirement 8.1, 8.2, 8.6: keyframed rendering -- locate the
			-- segment `effectiveT` falls within (shared across every
			-- plan for this target, since the waypoint positions are the
			-- same regardless of property), ease its local fraction with
			-- that segment's own easing function (Requirement 8.3, 8.5),
			-- then interpolate each property between that segment's
			-- start-of-segment and end-of-segment values (module header
			-- CONVENTION (keyframe waypoints)).
			local fromIndex, toIndex, segmentFraction = findKeyframeSegment(waypoints, effectiveT)
			local fromWaypoint = waypoints[fromIndex]
			local toWaypoint = waypoints[toIndex]
			local easedProgress = segmentEase(internal, toWaypoint)(segmentFraction)
			local keyframes = internal.keyframes :: { Types.Keyframe }

			for _, plan in targetPlan.plans do
				if plan.startValue == nil or plan.endValue == nil then
					continue
				end

				local segmentStart = keyframeWaypointValue(fromWaypoint, plan, keyframes)
				local segmentEnd = keyframeWaypointValue(toWaypoint, plan, keyframes)
				if segmentStart == nil or segmentEnd == nil then
					continue
				end

				local value = Interpolator.interpolate(segmentStart, segmentEnd, easedProgress, plan.property)
				writeProperty(target, plan.property, value)
			end
		end
	end

	-- Requirement 13.2: onUpdate fires on every render where at least one
	-- target actually rendered (i.e. some target's own elapsed time was
	-- `>= 0`), passing that first-rendered target's un-eased per-iteration
	-- local fraction -- rather than `easedProgress`, since eased progress
	-- can lie outside `[0, 1]` for overshoot easing while Property 32
	-- requires `onUpdate`'s progress stay within `[0, 1]`.
	if anyRendered then
		local onUpdate = internal.config.onUpdate
		if onUpdate ~= nil then
			onUpdate(self, firstEffectiveT :: number)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Requirements 12.7, 15.2 (task 12.1): kill releases Target references
-- ---------------------------------------------------------------------------

--- Overrides `Animation.kill` to additionally release this Tween's
--- references to its Targets (Requirement 12.7's "release its references to
--- Targets"; Requirement 15.2). Idempotent: killing an already-killed Tween
--- does nothing (guarded here, and `Animation.kill` is itself idempotent).
--- `Animation.kill` performs the detach (state -> "killed", unregister from
--- the Scheduler); `releaseTargets` then drops the Target-holding tables so
--- the Targets become eligible for garbage collection.
function Tween.kill(self: Types.Tween): ()
	if self.state == "killed" then
		return
	end

	Animation.kill(self)
	releaseTargets((self :: any) :: InternalTween)
end

return Tween
