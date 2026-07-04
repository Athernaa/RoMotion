--!strict
-- RoMotion public entry point.
--
-- The single required module for the whole library, delivered as a
-- folder-style ModuleScript that resolves to `ReplicatedStorage.Shared.RoMotion`
-- (Requirement 1.1): this `init.luau` IS the `RoMotion` ModuleScript, and
-- every sibling submodule (`Types`, `Tween`, `Timeline`, `Easing`, ...) is a
-- child of it, hence the `script.<Name>` requires below (children of this
-- module) rather than the `script.Parent.<Name>` form the submodules use
-- among themselves.
--
-- Responsibilities (Requirement 1):
--   - Assemble and return exactly one table (Requirement 1.2) exposing the
--     factory functions `to`, `from`, `fromTo`, `timeline` (Requirement 1.3)
--     plus the `Easing` library for direct use.
--   - Assert at load time that each required factory field exists and is a
--     function; if any is missing or not a function, raise a load-time error
--     and never return a partial table (Requirement 1.4).
--   - Re-export the public Luau types `Animation`, `Tween`, `Timeline`,
--     `Tween_Config`, and `Easing_Function` (Requirement 1.8).
--
-- Requirements satisfied structurally, without dedicated code here:
--   - 1.5 (same table + same scheduler state on every require): Luau caches
--     a ModuleScript's return value per VM, so every `require` yields this
--     same returned table; the `Scheduler` holds its active set/connection
--     in module-level upvalues that likewise persist per VM.
--   - 1.6 (all active Animations advanced from one centralized loop): every
--     Animation registers with the singleton `Scheduler`, which drives them
--     from a single `RunService.Heartbeat` connection.
--   - 1.7 (`--!strict` as the first line): see line 1 above.

local Types = require(script.Types)
local Tween = require(script.Tween)
local Timeline = require(script.Timeline)
local Easing = require(script.Easing)
local Global = require(script.Global)

-- ---------------------------------------------------------------------------
-- Requirement 1.8: re-export public type definitions.
-- ---------------------------------------------------------------------------
export type Animation = Types.Animation
export type Tween = Types.Tween
export type Timeline = Types.Timeline
export type Tween_Config = Types.Tween_Config
export type Easing_Function = Types.Easing_Function

-- Additional public types that appear in the factory signatures, re-exported
-- for caller convenience (the five above are the ones Requirement 1.8
-- mandates).
export type Target = Types.Target
export type PropertyMap = Types.PropertyMap
export type Keyframe = Types.Keyframe
export type Position_Parameter = Types.Position_Parameter

-- ---------------------------------------------------------------------------
-- `timeline` factory.
--
-- Wraps `Timeline.new` behind the public `timeline(config?)` shape. A
-- Timeline takes no construction-time configuration today, so any supplied
-- `config` is accepted (for forward-compatibility and to match the
-- documented `timeline(config?)` surface) and currently ignored.
-- ---------------------------------------------------------------------------
local function timeline(_config: { [string]: any }?): Types.Timeline
	return Timeline.new()
end

-- ---------------------------------------------------------------------------
-- Requirements 1.2, 1.3: assemble the single returned factory table.
-- ---------------------------------------------------------------------------
local RoMotion = {
	to = Tween.to,
	from = Tween.from,
	fromTo = Tween.fromTo,
	timeline = timeline,
	Easing = Easing,
	-- Networked, server-authored tweens rendered locally on every client
	-- (see Global.luau). Server: `RoMotion.global.to(...)`. Client: errors.
	global = Global,
}

-- ---------------------------------------------------------------------------
-- Requirement 1.4: at load time, assert every required factory field exists
-- and is a function. If any is missing or not a function, raise -- aborting
-- the `require` before this module ever returns -- so callers never receive
-- a partially-populated table.
-- ---------------------------------------------------------------------------
local REQUIRED_FACTORIES = { "to", "from", "fromTo", "timeline" }

for _, fieldName in REQUIRED_FACTORIES do
	if typeof((RoMotion :: any)[fieldName]) ~= "function" then
		error(
			string.format(
				"RoMotion: required factory field %q is missing or not a function -- the module cannot load",
				fieldName
			)
		)
	end
end

return RoMotion
