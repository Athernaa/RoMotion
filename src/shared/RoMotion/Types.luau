--!strict
export type PlaybackState = "idle" | "playing" | "paused" | "completed" | "killed"
export type Direction = number
export type Target = Instance | { [string]: any }
export type PropertyMap = { [string]: any }
export type Easing_Function = (t: number) -> number
export type Position_Parameter = number | string
export type Keyframe = {
	position: number, -- fractional 0..1 of the Tween's total duration
	values: PropertyMap,
	ease: (string | Easing_Function)?, -- defaults to Quad.InOut when omitted
}
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
export type Animation = {
	position: number, -- current local time in seconds, 0..duration
	duration: number, -- total duration in seconds
	direction: Direction,
	timeScale: number, -- > 0
	state: PlaybackState,
	started: boolean, -- has active phase begun since create/restart
	needsIsolation: boolean,
	play: (self: Animation) -> Animation,
	pause: (self: Animation) -> Animation,
	resume: (self: Animation) -> Animation,
	restart: (self: Animation) -> Animation,
	reverse: (self: Animation) -> Animation,
	seek: (self: Animation, seconds: number) -> Animation,
	progress: (self: Animation, fraction: number?) -> number | Animation,
	setTimeScale: (self: Animation, scale: number) -> Animation,
	kill: (self: Animation) -> (),
	_advance: (self: Animation, dt: number) -> (),
	_render: (self: Animation) -> (), -- apply values at current position
}
export type PropertyPlan = {
	property: string,
	startValue: any, -- captured at active phase (Req 2.2, 3.2, 8.6)
	endValue: any, -- resolved (relative values applied)
	valueType: string,
	lerp: ((alpha: number) -> any)?,
}
export type PerTargetPlan = {
	target: Target,
	startOffset: number, -- stagger offset (Req 11.1)
	plans: { PropertyPlan },
	alive: boolean, -- cleared when target destroyed (Req 15.1)
	captured: boolean, -- whether this target's own staggered active-phase
}
export type Tween = Animation & {
	targets: { Target },
	resolved: { PerTargetPlan }, -- computed start/end per property per target
	config: Tween_Config,
	ease: Easing_Function,
	keyframes: { Keyframe }?,
	staggerOffset: { [Target]: number },
}
export type Timeline = Animation & {
	children: { { anim: Animation, startTime: number } },
	labels: { [string]: number },
	add: (self: Timeline, child: Animation, position: Position_Parameter?) -> Timeline,
	addLabel: (self: Timeline, name: string, time: number) -> Timeline,
}

return {}
