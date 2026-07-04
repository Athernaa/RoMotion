--!strict

local Types = require(script.Types)
local Tween = require(script.Tween)
local Timeline = require(script.Timeline)
local Easing = require(script.Easing)
local Global = require(script.Global)

export type Animation = Types.Animation
export type Tween = Types.Tween
export type Timeline = Types.Timeline
export type Tween_Config = Types.Tween_Config
export type Easing_Function = Types.Easing_Function

export type Target = Types.Target
export type PropertyMap = Types.PropertyMap
export type Keyframe = Types.Keyframe
export type Position_Parameter = Types.Position_Parameter


local function timeline(_config: { [string]: any }?): Types.Timeline
	return Timeline.new()
end

local RoMotion = {
	to = Tween.to,
	from = Tween.from,
	fromTo = Tween.fromTo,
	timeline = timeline,
	Easing = Easing,
	global = Global,
}

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
