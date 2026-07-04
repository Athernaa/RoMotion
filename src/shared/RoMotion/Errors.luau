--!strict

local RAISE_LEVEL = 3

local Errors = {}

local function describe(value: any): string
	if value == nil then
		return "nil"
	end
	local ty = typeof(value)
	if ty == "string" then
		return string.format("%q", value)
	elseif ty == "number" or ty == "boolean" then
		return tostring(value)
	elseif ty == "Instance" then
		return string.format("%s (%s)", value.Name, value.ClassName)
	else
		return string.format("<%s>", ty)
	end
end

local function joinNames(names: { string }): string
	return table.concat(names, ", ")
end

function Errors.invalidDuration(value: any)
	error(
		string.format(
			"RoMotion: invalid Tween_Config.duration %s -- duration must be a number greater than 0",
			describe(value)
		),
		RAISE_LEVEL
	)
end

function Errors.nilTarget()
	error("RoMotion: invalid argument Target (nil) -- Target must not be nil", RAISE_LEVEL)
end

function Errors.emptyPropertyMap(value: any)
	error(
		string.format(
			"RoMotion: invalid argument Property_Map %s -- Property_Map must be a non-nil table with at least one property",
			describe(value)
		),
		RAISE_LEVEL
	)
end

function Errors.missingProperty(propertyName: string, target: any)
	error(
		string.format(
			"RoMotion: invalid property %s -- property does not exist on Target %s",
			describe(propertyName),
			describe(target)
		),
		RAISE_LEVEL
	)
end

function Errors.fromToKeyMismatch(startKeys: { string }, endKeys: { string })
	error(
		string.format(
			"RoMotion: fromTo start/end Property_Map key mismatch -- start keys [%s] do not match end keys [%s]",
			joinNames(startKeys),
			joinNames(endKeys)
		),
		RAISE_LEVEL
	)
end

function Errors.typeMismatch(property: string, startType: string, endType: string)
	error(
		string.format(
			"RoMotion: type mismatch for property %s -- start value is %s but end value is %s",
			describe(property),
			startType,
			endType
		),
		RAISE_LEVEL
	)
end

function Errors.unsupportedType(property: string, valueType: string)
	error(
		string.format(
			"RoMotion: unsupported type for property %s -- type %s is not supported by the Interpolator",
			describe(property),
			valueType
		),
		RAISE_LEVEL
	)
end

function Errors.unknownEasing(name: string)
	error(
		string.format(
			"RoMotion: unknown easing %s -- no matching entry in the Easing_Library",
			describe(name)
		),
		RAISE_LEVEL
	)
end

function Errors.invalidCustomEasingReturn(returnedValue: any)
	error(
		string.format(
			"RoMotion: invalid custom easing return value %s -- custom easing functions must return a number",
			describe(returnedValue)
		),
		RAISE_LEVEL
	)
end

function Errors.invalidRepeat(value: any)
	error(
		string.format(
			'RoMotion: invalid Tween_Config["repeat"] %s -- repeat must be an integer >= 0, or exactly -1 for infinite',
			describe(value)
		),
		RAISE_LEVEL
	)
end

function Errors.invalidDelay(fieldName: string, value: any)
	error(
		string.format(
			"RoMotion: invalid Tween_Config.%s %s -- %s must be a number in the range 0 to 86400 inclusive",
			fieldName,
			describe(value),
			fieldName
		),
		RAISE_LEVEL
	)
end

function Errors.malformedRelativeValue(spec: string)
	error(
		string.format(
			'RoMotion: invalid Relative_Value %s -- expected a string matching "+=X" or "-=X" with X a finite number',
			describe(spec)
		),
		RAISE_LEVEL
	)
end

function Errors.nonNumericRelativeStart(property: string, valueType: string)
	error(
		string.format(
			"RoMotion: invalid Relative_Value target for property %s -- captured start value is of type %s, expected number",
			describe(property),
			valueType
		),
		RAISE_LEVEL
	)
end

function Errors.invalidKeyframePosition(position: any, index: number?)
	if index ~= nil then
		error(
			string.format(
				"RoMotion: invalid Keyframe[%d].position %s -- position must be a number in the range 0 to 1 inclusive",
				index,
				describe(position)
			),
			RAISE_LEVEL
		)
	else
		error(
			string.format(
				"RoMotion: invalid Keyframe.position %s -- position must be a number in the range 0 to 1 inclusive",
				describe(position)
			),
			RAISE_LEVEL
		)
	end
end

function Errors.invalidKeyframesList(reason: string)
	error(string.format("RoMotion: invalid keyframes list -- %s", reason), RAISE_LEVEL)
end

function Errors.invalidTimeScale(value: any)
	error(
		string.format(
			"RoMotion: invalid Timeline timeScale %s -- timeScale must be a number greater than 0",
			describe(value)
		),
		RAISE_LEVEL
	)
end

function Errors.cyclicNesting(child: any)
	error(
		string.format(
			"RoMotion: cyclic Timeline nesting detected -- child %s is the parent Timeline itself or one of its descendants",
			describe(child)
		),
		RAISE_LEVEL
	)
end

function Errors.invalidTimelineChild(value: any)
	error(
		string.format(
			"RoMotion: invalid Timeline child %s -- child must be an Animation (Tween or Timeline)",
			describe(value)
		),
		RAISE_LEVEL
	)
end

function Errors.unknownLabel(name: string)
	error(
		string.format(
			"RoMotion: unknown label %s -- no Label with that name exists on this Timeline",
			describe(name)
		),
		RAISE_LEVEL
	)
end

function Errors.invalidPositionParameter(value: any)
	error(
		string.format(
			"RoMotion: invalid Position_Parameter %s -- numeric position parameters must be 0 or greater",
			describe(value)
		),
		RAISE_LEVEL
	)
end

function Errors.invalidStagger(value: any)
	error(
		string.format(
			"RoMotion: invalid Tween_Config.stagger %s -- stagger must be a number in the range 0 to 3600 seconds",
			describe(value)
		),
		RAISE_LEVEL
	)
end

function Errors.emptyTargetsList()
	error("RoMotion: invalid argument Targets -- the Targets list must not be empty", RAISE_LEVEL)
end

return Errors
