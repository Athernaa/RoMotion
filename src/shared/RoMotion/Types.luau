--!strict
-- RoMotion shared type definitions.
--
-- This module has no runtime behavior; it only exports the Luau types shared
-- across the RoMotion package (Animation.luau, Tween.luau, Timeline.luau,
-- Scheduler.luau, Interpolator.luau, Easing.luau, RelativeValue.luau, and the
-- public init.luau). See design.md "Data Models" and "Components and
-- Interfaces" for the authoritative shape of each type.
--
-- `PerTargetPlan` and `PropertyPlan` are internal-only types: they are
-- exported here so sibling submodules can reference them, but they are not
-- re-exported from the public `init.luau` surface.

--[[
    PlaybackState: the discrete lifecycle state of any Animation.
    Requirement 1.8 (exported public type), Requirements 12.1-12.12.
]]
export type PlaybackState = "idle" | "playing" | "paused" | "completed" | "killed"

--[[
    Direction: playback direction. By convention, 1 = forward and -1 =
    backward. Luau does not support numeric literal singleton types (only
    string/boolean singletons), so this is a plain `number` rather than a
    `1 | -1` union; callers must only ever assign/compare against 1 or -1.
]]
export type Direction = number

--[[
    Target: a Roblox Instance, or a plain table-like target whose properties
    can be read/written directly (see Requirements 2, 3 Glossary "Target").
]]
export type Target = Instance | { [string]: any }

--[[
    PropertyMap: property name -> destination/source value. Values may be a
    concrete Roblox value or a Relative_Value string (e.g. "+=100").
]]
export type PropertyMap = { [string]: any }

--[[
    Easing_Function: maps a normalized time t in [0, 1] to an eased progress
    value (which may lie outside [0, 1] for overshoot easing).
]]
export type Easing_Function = (t: number) -> number

--[[
    Position_Parameter: where a child Animation starts on a Timeline.
    A non-negative absolute time in seconds, or a string: "+=X", "-=X",
    a label name, "<", or ">".
]]
export type Position_Parameter = number | string

--[[
    Keyframe: an intermediate waypoint within a Tween's total duration.
]]
export type Keyframe = {
	position: number, -- fractional 0..1 of the Tween's total duration
	values: PropertyMap,
	ease: (string | Easing_Function)?, -- defaults to Quad.InOut when omitted
}

--[[
    Tween_Config: options accepted by `to`/`from`/`fromTo`.
    `repeat` is a Luau reserved word, so it is accessed as config["repeat"].
]]
export type Tween_Config = {
	duration: number?, -- seconds > 0, default 0.5
	ease: (string | Easing_Function)?, -- default "Quad.InOut"
	delay: number?, -- 0..86400, default 0
	["repeat"]: number?, -- integer 0..1_000_000, or -1 for infinite, default 0
	repeatDelay: number?, -- 0..86400, default 0
	yoyo: boolean?, -- default false
	stagger: number?, -- 0..3600, default 0
	keyframes: { Keyframe }?, -- optional multi-step definition
	onStart: ((anim: Animation) -> ())?,
	onUpdate: ((anim: Animation, progress: number) -> ())?,
	onComplete: ((anim: Animation) -> ())?,
	onRepeat: ((anim: Animation, iterationIndex: number) -> ())?,
}

--[[
    Animation: the shared control surface implemented by both Tween and
    Timeline. All control methods return `self` to allow chaining, except
    `kill` (no return) and `progress` when called with no argument (returns
    the current fraction).
]]
export type Animation = {
	-- state
	position: number, -- current local time in seconds, 0..duration
	duration: number, -- total duration in seconds
	direction: Direction,
	timeScale: number, -- > 0
	state: PlaybackState,
	started: boolean, -- has active phase begun since create/restart
	-- Performance flag read by the Scheduler: when false, the Scheduler
	-- advances this animation WITHOUT a per-frame pcall wrapper (safe for
	-- pure interpolation with no user callbacks). Set true whenever user
	-- lifecycle callbacks may run, so their errors stay isolated
	-- (Requirements 13.7, 15.5).
	needsIsolation: boolean,

	-- control surface (Requirement 12)
	play: (self: Animation) -> Animation,
	pause: (self: Animation) -> Animation,
	resume: (self: Animation) -> Animation,
	restart: (self: Animation) -> Animation,
	reverse: (self: Animation) -> Animation,
	seek: (self: Animation, seconds: number) -> Animation,
	progress: (self: Animation, fraction: number?) -> number | Animation,
	setTimeScale: (self: Animation, scale: number) -> Animation,
	kill: (self: Animation) -> (),

	-- internal advancement, implemented by Tween/Timeline
	_advance: (self: Animation, dt: number) -> (),
	_render: (self: Animation) -> (), -- apply values at current position
}

--[[
    PropertyPlan (internal): the resolved start/end plan for a single
    property on a single target.
]]
export type PropertyPlan = {
	property: string,
	startValue: any, -- captured at active phase (Req 2.2, 3.2, 8.6)
	endValue: any, -- resolved (relative values applied)
	valueType: string,
	-- Performance: a specialized `(alpha) -> value` closure built once (via
	-- Interpolator.buildLerp) after start/end are known, capturing the
	-- precomputed per-component deltas so the per-frame render does only
	-- arithmetic -- no typeof dispatch. `nil` until first built; rebuilt on
	-- restart. Only used by the non-keyframe render path.
	lerp: ((alpha: number) -> any)?,
}

--[[
    PerTargetPlan (internal): the resolved plan for a single target,
    including all of its per-property plans.
]]
export type PerTargetPlan = {
	target: Target,
	startOffset: number, -- stagger offset (Req 11.1)
	plans: { PropertyPlan },
	alive: boolean, -- cleared when target destroyed (Req 15.1)
	captured: boolean, -- whether this target's own staggered active-phase
	-- capture (Req 11.1, 11.2) has run; lets `to`/`from` capture start/end
	-- values independently per target as each target's own local window
	-- opens, rather than once globally for the whole Tween.
}

--[[
    Tween: an Animation that interpolates one or more target properties.
]]
export type Tween = Animation & {
	targets: { Target },
	resolved: { PerTargetPlan }, -- computed start/end per property per target
	config: Tween_Config,
	ease: Easing_Function,
	keyframes: { Keyframe }?,
	staggerOffset: { [Target]: number },
}

--[[
    Timeline: an Animation that sequences child Animations.
]]
export type Timeline = Animation & {
	children: { { anim: Animation, startTime: number } },
	labels: { [string]: number },
	add: (self: Timeline, child: Animation, position: Position_Parameter?) -> Timeline,
	addLabel: (self: Timeline, name: string, time: number) -> Timeline,
}

return {}
