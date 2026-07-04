--!strict
-- RoMotion Timeline: an Animation that sequences child Animations.
--
-- Implements the Timeline core (Requirements 9.1, 9.2, 9.6, 9.8), labels
-- and Position_Parameter resolution (Requirement 10), and child
-- advancement plus recursive time scaling (Requirements 9.3, 9.4, 9.5) on
-- top of the shared `Animation` base state machine, including cyclic
-- nesting rejection (Requirement 9.7). See design.md "Timeline.luau" and
-- requirements.md Requirements 9 and 10 for the authoritative contract.
--
-- Extends `Animation.luau` using the same subclassing convention as
-- `Tween.luau` (see Animation.luau's module header): `Timeline` is its own
-- metatable with `__index = Animation`, so control methods
-- (play/pause/resume/restart/reverse/seek/progress/kill) fall back to the
-- shared implementation unmodified. Only `_render` and `setTimeScale` are
-- overridden below; `_advance` is NOT overridden -- the shared
-- `Animation._advance` already advances `self.position` (via
-- `_advancePosition`, which applies this Timeline's own `direction` and
-- `timeScale` and halts backward playback at 0) and then calls
-- `self:_render()`, so the Timeline's per-child driving lives entirely in
-- `_render`. This is deliberate: `Animation.seek`/`Animation.progress`
-- (Requirement 12) also set `self.position` and call `self:_render()`
-- directly (without going through `_advance`), so putting all child
-- driving in `_render` makes seek/progress re-drive children for free.
--
-- CONVENTION (child advancement -- playhead mapping, Requirements 9.3,
-- 9.4):
-- Children are pure *slaves* of this Timeline's playhead (`self.position`),
-- exactly like GSAP timeline children. `_render` (below) maps each child's
-- timeline-local time to `self.position - startTime`, sets the child's own
-- `position` to that (clamped into the child's `[0, childDuration]`
-- window), and then calls `child:_advance(0)`. Passing `dt = 0` means the
-- child's own `_advancePosition` makes no further change to the position
-- we just set (so a child never drifts away from its mapped playhead
-- offset), while everything else `_advance` does still runs at that
-- position: a Tween child captures its active phase, fires its lifecycle
-- callbacks as it crosses iteration/completion boundaries, and renders its
-- interpolated values; a nested Timeline child recursively drives its own
-- children. Because a child's mapped offset is driven off `self.position`,
-- and `self.position` was advanced (by the shared `_advance`) at this
-- Timeline's own `timeScale`, every descendant's effective playback speed
-- is scaled by this Timeline's `timeScale` transitively -- a nested
-- Timeline's playhead is mapped from this Timeline's already-scaled
-- playhead, and its children are mapped from that in turn (Requirement
-- 9.4: "all child Animations, including nested Timelines and their
-- descendants"). This also makes forward playback, backward playback
-- (`reverse`), and `seek`/`progress` all work through the one mapping,
-- since each simply moves `self.position` and re-renders.
--
-- A child whose window has not yet opened (`self.position < startTime`) is
-- left un-rendered/inactive (Property 20); a child whose window has closed
-- (`self.position > startTime + childDuration`) is held at its final value
-- by clamping its mapped offset to `childDuration`, rather than being
-- reset -- once a child has played to its end on the timeline it stays at
-- its end state until the playhead moves back into its window.
--
-- CONVENTION (recursive time scale, Requirements 9.4, 9.5):
-- `setTimeScale` (below) validates `scale > 0` (rejecting `<= 0` via
-- `Errors.invalidTimeScale` and retaining the previously applied scale,
-- since validation happens before any mutation -- Requirement 9.5), stores
-- it, and then *propagates* it to every child by calling
-- `child:setTimeScale(scale)` recursively (a nested Timeline child
-- re-propagates to its own descendants), so the whole subtree's stored
-- `timeScale` reflects the applied scale (task 11.3, Requirement 9.4). The
-- scale that actually drives playback speed, however, is applied through
-- the playhead mapping described above (this Timeline's own `timeScale`
-- scales `self.position`, which cascades to all descendants), so
-- propagation keeps descendant state coherent without double-applying the
-- scale on top of that cascade.
--
-- CONVENTION (add / append / duration, Requirements 9.1, 9.2, 9.6, 9.8):
-- `self.children` is an ordered array of `{ anim, startTime }` entries
-- (matching `Types.Timeline.children` exactly), in the order they were
-- added -- so `self.children[#self.children]` is always the most recently
-- added child, which Requirements 10.5/10.6 (`"<"`/`">"`) resolve against.
-- `Timeline.add` validates that `child` is Animation-shaped (Requirement
-- 9.8, via `Errors.invalidTimelineChild`) before any mutation, then
-- resolves the new child's absolute `startTime` from the supplied
-- Position_Parameter (see `resolveStartTime`/CONVENTION below). After
-- inserting the new child, `recomputeDuration` recomputes `self.duration`
-- as the greatest `startTime + child.duration` across every entry of
-- `self.children` (Requirement 9.1), or 0 when there are no children (also
-- Requirement 9.1, and the value `Timeline.new` starts with). Nesting --
-- "a Timeline may be added as a child of another Timeline, contributing
-- its own total duration" (Requirement 9.6) -- requires no special-casing:
-- a nested Timeline is still an `Animation` with its own `duration` field
-- kept current by this same `recomputeDuration` running on the nested
-- Timeline itself, so reading `child.duration` generically already
-- produces the right contribution whether `child` is a Tween or a Timeline.
--
-- CONVENTION (Position_Parameter resolution, Requirement 10):
-- `resolveStartTime` maps a supplied Position_Parameter to an absolute
-- start time in seconds, mirroring design.md Property 22:
--   - nil            -> `self.duration` (append at current end, Req 9.2).
--   - number >= 0    -> that number of seconds from time 0 (Req 10.2);
--                       a number < 0 raises `Errors.invalidPositionParameter`
--                       and the child is NOT added (Req 10.8).
--   - "<"            -> the most recently added child's start time, or 0
--                       when no child was previously added (Reqs 10.5, 10.9).
--   - ">"            -> the most recently added child's end time
--                       (`startTime + duration`), or 0 when none (Reqs
--                       10.6, 10.9).
--   - "+=X" / "-=X"  -> `max(0, currentEnd ± X)` where `currentEnd` is the
--                       Timeline's current total duration (Req 10.3),
--                       clamped to a minimum of 0. The numeric portion X is
--                       parsed by reusing `RelativeValue.parse` so the same
--                       whitespace tolerance and finite-number validation
--                       used for Property_Map relative values (Requirement
--                       7) applies here too.
--   - any other      -> treated as a label name (Req 10.4): resolves to
--     string           that label's recorded time, or raises
--                       `Errors.unknownLabel` and does NOT add the child
--                       when no such label exists (Req 10.7).
-- A string is classified as relative ("+=X"/"-=X") when it begins with an
-- optional run of whitespace followed by `+=` or `-=`; `"<"`/`">"` are
-- matched exactly first; everything else is a label name. This matches
-- GSAP, where a `+=`/`-=` prefix always denotes a relative offset rather
-- than a label, so a label may not be named with such a prefix.
--
-- CONVENTION (addLabel validation):
-- Requirement 10.1 records a Label with a 1..256-character name at a time
-- >= 0, and Requirement 10.10 replaces an existing same-named Label's time.
-- The Error Handling table in design.md defines no user-facing error for an
-- out-of-contract label name/time (only Req 10.7's unknown-label-as-
-- Position_Parameter is a defined error), so `addLabel` simply records/
-- replaces for in-contract input. Clearly out-of-contract input (a
-- non-string name, an empty or >256-character name, or a non-number/
-- negative time) is guarded defensively with a plain `error(..., 2)` rather
-- than an `Errors.*` builder, since no builder or acceptance criterion
-- covers it -- this is runtime robustness, not spec'd validation.

local Types = require(script.Parent.Types)
local Animation = require(script.Parent.Animation)
local Errors = require(script.Parent.Errors)
local RelativeValue = require(script.Parent.RelativeValue)

local Timeline = setmetatable({}, { __index = Animation })
Timeline.__index = Timeline

local MAX_LABEL_LENGTH = 256

-- One entry of `self.children`. Structurally identical to
-- `Types.Timeline.children`'s element type; declared separately here only
-- for readability in this module's internal helpers.
type ChildEntry = { anim: Types.Animation, startTime: number }

-- ---------------------------------------------------------------------------
-- Requirement 9.8: non-Animation child rejection
-- ---------------------------------------------------------------------------

--- Reports whether `value` exposes the full shared `Animation` control
--- surface. A duck-typed check (rather than a metatable/class-identity
--- check) is used because `Tween` and `Timeline` are distinct metatables
--- that both merely share this surface via `Animation.luau` -- there is no
--- single common "is an Animation" marker beyond the surface itself, and
--- duck-typing it here lets a future third `Animation` subclass (if one is
--- ever added) be accepted as a Timeline child without this module needing
--- to know about it.
local function isAnimationLike(value: any): boolean
	if typeof(value) ~= "table" then
		return false
	end

	return typeof(value.play) == "function"
		and typeof(value.pause) == "function"
		and typeof(value.resume) == "function"
		and typeof(value.restart) == "function"
		and typeof(value.reverse) == "function"
		and typeof(value.seek) == "function"
		and typeof(value.progress) == "function"
		and typeof(value.setTimeScale) == "function"
		and typeof(value.kill) == "function"
		and typeof(value._advance) == "function"
		and typeof(value._render) == "function"
end

-- ---------------------------------------------------------------------------
-- Requirement 9.7: cyclic nesting detection
-- ---------------------------------------------------------------------------

--- Reports whether `value` is a RoMotion Timeline, by identity of its
--- metatable. All Timeline instances share the single `Timeline` metatable
--- (see `Timeline.new`), while Tween instances have a distinct metatable,
--- so this precisely distinguishes a Timeline from any other Animation
--- without walking the control surface. Used to decide whether a node has
--- a `children` subtree worth descending into during cycle detection.
local function isTimeline(value: any): boolean
	return getmetatable(value) == Timeline
end

--- Reports whether the subtree rooted at `node` (inclusive of `node`
--- itself) contains `target`. Descends into `children` only for Timeline
--- nodes (a Tween is always a leaf). The existing timeline structure is
--- always acyclic -- this very check prevents any cycle from being
--- introduced on every `add` -- so the recursion always terminates.
local function subtreeContains(node: Types.Animation, target: Types.Animation): boolean
	if node == target then
		return true
	end

	if isTimeline(node) then
		for _, entry in (node :: Types.Timeline).children do
			if subtreeContains(entry.anim, target) then
				return true
			end
		end
	end

	return false
end

-- ---------------------------------------------------------------------------
-- Requirements 9.1, 9.6: duration recomputation
-- ---------------------------------------------------------------------------

--- Recomputes and stores this Timeline's total `duration` as the greatest
--- `startTime + child.duration` among `self.children`, or 0 when there are
--- no children.
local function recomputeDuration(self: Types.Timeline): ()
	local maxEnd = 0

	for _, entry in self.children do
		local endTime = entry.startTime + entry.anim.duration
		if endTime > maxEnd then
			maxEnd = endTime
		end
	end

	(self :: any).duration = maxEnd
end

-- ---------------------------------------------------------------------------
-- Requirement 10: Position_Parameter resolution
-- ---------------------------------------------------------------------------

--- Requirement 10.3: reports whether `s` is a relative Position_Parameter
--- string ("+=X"/"-=X"), i.e. begins with optional whitespace then `+=` or
--- `-=`. See module header CONVENTION (Position_Parameter resolution).
local function isRelativePositionString(s: string): boolean
	return s:match("^%s*[%+%-]=") ~= nil
end

--- Requirement 10: resolves a Position_Parameter (or nil, for append) to an
--- absolute start time in seconds. Raises (and the caller must not add the
--- child) for a numeric parameter < 0 (Req 10.8) or a label name that does
--- not exist (Req 10.7). See module header CONVENTION for the full mapping.
local function resolveStartTime(self: Types.Timeline, position: Types.Position_Parameter?): number
	-- Requirement 9.2: no Position_Parameter -> append at the current end.
	if position == nil then
		return self.duration
	end

	if typeof(position) == "number" then
		-- Requirement 10.8: numeric Position_Parameter < 0 is invalid.
		if position < 0 then
			Errors.invalidPositionParameter(position)
		end
		-- Requirement 10.2.
		return position
	end

	if typeof(position) == "string" then
		local lastChild = self.children[#self.children]

		if position == "<" then
			-- Requirements 10.5, 10.9.
			if lastChild == nil then
				return 0
			end
			return lastChild.startTime
		elseif position == ">" then
			-- Requirements 10.6, 10.9.
			if lastChild == nil then
				return 0
			end
			return lastChild.startTime + lastChild.anim.duration
		elseif isRelativePositionString(position) then
			-- Requirement 10.3: max(0, currentEnd ± X). `RelativeValue.parse`
			-- reuse gives the same whitespace tolerance / finite-number
			-- validation (Requirement 7) for X.
			local parsed = RelativeValue.parse(position)
			local currentEnd = self.duration
			local resolved = if parsed.op == "+" then currentEnd + parsed.amount else currentEnd - parsed.amount
			return math.max(0, resolved)
		else
			-- Requirements 10.4, 10.7: label name lookup.
			local labelTime = self.labels[position]
			if labelTime == nil then
				Errors.unknownLabel(position)
			end
			return labelTime
		end
	end

	-- Defensive: a Position_Parameter is declared as `number | string`, so
	-- any other runtime type (reached only when a caller passes an
	-- off-type value through `any`) is not a valid Position_Parameter.
	Errors.invalidPositionParameter(position)
	return 0 -- unreachable: Errors.invalidPositionParameter always raises
end

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

--- Constructs an empty Timeline with `duration = 0` (Requirement 9.1, the
--- "no children" case) and no children/labels.
function Timeline.new(): Types.Timeline
	local base = Animation.new(0)

	local self = base :: any
	self.children = {} :: { ChildEntry }
	self.labels = {} :: { [string]: number }

	return (setmetatable(self, Timeline) :: any) :: Types.Timeline
end

-- ---------------------------------------------------------------------------
-- Requirements 9.1, 9.2, 9.6, 9.8, 10: add
-- ---------------------------------------------------------------------------

--- IF `child` is not Animation-shaped, raises via
--- `Errors.invalidTimelineChild` and leaves `self.children` unchanged
--- (Requirement 9.8).
---
--- IF `child` is a Timeline and adding it here would create a cycle -- i.e.
--- `child` is this Timeline itself, or this Timeline is one of `child`'s
--- descendants (equivalently, `child`'s own subtree already contains
--- `self`) -- raises via `Errors.cyclicNesting` and leaves `self.children`
--- unchanged (Requirement 9.7). The check runs before any start-time
--- resolution or insertion, so nothing is mutated on rejection.
---
--- Otherwise resolves the new child's absolute start time from `position`
--- (Requirement 10; nil appends at the current end, Requirement 9.2),
--- inserts it, and recomputes the Timeline's total duration to include it
--- (Requirements 9.1, 9.6). When `position` resolution raises (a numeric
--- parameter < 0, Req 10.8, or an unknown label name, Req 10.7), the child
--- is NOT added: the raise unwinds before the `table.insert` below.
function Timeline.add(self: Types.Timeline, child: Types.Animation, position: Types.Position_Parameter?): Types.Timeline
	if not isAnimationLike(child) then
		Errors.invalidTimelineChild(child)
		return self
	end

	-- Requirement 9.7: reject a Timeline child whose subtree already
	-- contains this Timeline (covers both "added as a child of itself",
	-- child == self, and "added as a child of any of its descendants",
	-- self reachable within child's subtree). Runs before any mutation so
	-- `self.children` is left unchanged on rejection.
	if isTimeline(child) and subtreeContains(child, self) then
		Errors.cyclicNesting(child)
		return self
	end

	local startTime = resolveStartTime(self, position)

	table.insert(self.children, { anim = child, startTime = startTime })
	recomputeDuration(self)

	return self
end

-- ---------------------------------------------------------------------------
-- Requirements 10.1, 10.10: addLabel
-- ---------------------------------------------------------------------------

--- Requirement 10.1: records `name` as a named time marker at `time`
--- seconds. Requirement 10.10: if a Label with the same `name` already
--- exists, its recorded time is replaced with `time`. `name` must be a
--- string of 1..256 characters and `time` a number >= 0 (see module header
--- CONVENTION (addLabel validation) for why out-of-contract input is
--- guarded with a plain `error` rather than an `Errors.*` builder).
function Timeline.addLabel(self: Types.Timeline, name: string, time: number): Types.Timeline
	if typeof(name) ~= "string" or #name < 1 or #name > MAX_LABEL_LENGTH then
		error(
			string.format(
				"RoMotion: invalid Label name -- name must be a string of 1 to %d characters",
				MAX_LABEL_LENGTH
			),
			2
		)
	end

	if typeof(time) ~= "number" or time < 0 then
		error("RoMotion: invalid Label time -- time must be a number greater than or equal to 0", 2)
	end

	-- Requirements 10.1 (record) and 10.10 (replace): a plain assignment
	-- covers both, since a new name creates the marker and an existing name
	-- overwrites its recorded time.
	self.labels[name] = time

	return self
end

-- ---------------------------------------------------------------------------
-- Requirement 9.3, 9.4: `_render` override (child advancement)
-- ---------------------------------------------------------------------------

--- Drives every child at the Timeline's current playhead (`self.position`)
--- by playhead mapping (see module header CONVENTION (child advancement)).
--- Called by the shared `Animation._advance` after it advances
--- `self.position`, and by `Animation.seek`/`Animation.progress` directly,
--- so forward playback, backward playback, and seek/progress all re-drive
--- children through this one method.
---
--- Each child is mapped to timeline-local offset `self.position -
--- startTime`: a child whose window has not yet opened (offset < 0) is left
--- inactive/un-rendered (Property 20); an active or past-window child has
--- its own `position` set to that offset clamped into `[0, childDuration]`
--- (so a finished child holds at its final value), and is then driven via
--- `child:_advance(0)` so it captures/renders/fires its own callbacks at
--- that position without drifting off the mapped offset (`dt = 0` leaves
--- the position we set unchanged).
function Timeline._render(self: Types.Timeline): ()
	for _, entry in self.children do
		local anim = entry.anim

		-- A killed child is permanently inactive; never drive it again.
		if anim.state == "killed" then
			continue
		end

		local childLocalTime = self.position - entry.startTime

		-- Requirement 9.3 / Property 20: before its window opens, the child
		-- is inactive -- do not render it.
		if childLocalTime < 0 then
			continue
		end

		-- Hold a past-window child at its final value by clamping to its
		-- duration (`math.min` leaves an infinite-duration child -- e.g. a
		-- nested infinite-repeat Tween -- mapped straight through).
		anim.position = math.min(childLocalTime, anim.duration)
		anim:_advance(0)
	end
end

-- ---------------------------------------------------------------------------
-- Requirements 9.4, 9.5, 12.12: `setTimeScale` override
-- ---------------------------------------------------------------------------

--- Sets this Timeline's playback time scale and propagates it recursively
--- to all descendants (Requirement 9.4). No-op when killed (Requirement
--- 12.12). IF `scale <= 0` (or is not a number), raises via
--- `Errors.invalidTimeScale` and retains the previously applied scale --
--- validation happens before any mutation, so nothing is changed
--- (Requirement 9.5). See module header CONVENTION (recursive time scale)
--- for why propagation does not double-apply on top of the playhead-
--- mapping scale cascade.
function Timeline.setTimeScale(self: Types.Timeline, scale: number): Types.Animation
	if self.state == "killed" then
		return self
	end

	-- Requirement 9.5: reject scale <= 0 (and non-number) and retain the
	-- previous scale by validating before mutating anything.
	if typeof(scale) ~= "number" or scale <= 0 then
		Errors.invalidTimeScale(scale)
		return self -- unreachable: Errors.invalidTimeScale always raises
	end

	(self :: any).timeScale = scale

	-- Requirement 9.4: propagate to all descendants. A nested Timeline
	-- child re-propagates to its own descendants via this same override.
	for _, entry in self.children do
		entry.anim:setTimeScale(scale)
	end

	return self
end

-- ---------------------------------------------------------------------------
-- Requirements 12.7, 15.2 (task 12.1): kill releases child references
-- ---------------------------------------------------------------------------

--- Overrides `Animation.kill` to additionally release this Timeline's
--- references to its child Animations and labels. A Timeline holds no
--- Target Instances directly -- its "Target references" (Requirement 12.7,
--- 15.2) are the child Animations it drives, which in turn hold Targets --
--- so dropping them lets the whole subtree become eligible for garbage
--- collection once the Timeline is killed. Idempotent: killing an
--- already-killed Timeline does nothing (guarded here, and `Animation.kill`
--- is itself idempotent). `Animation.kill` performs the detach (state ->
--- "killed", unregister from the Scheduler); the child Animations, driven
--- only by this Timeline, simply stop being advanced once its `children`
--- are cleared.
function Timeline.kill(self: Types.Timeline): ()
	if self.state == "killed" then
		return
	end

	Animation.kill(self)
	self.children = {}
	self.labels = {}
end

return Timeline
