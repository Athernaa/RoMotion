--!strict
-- RoMotion centralized error message builders.
--
-- Every user-facing validation error in RoMotion is raised through this
-- module so that messages are consistently formatted and always name the
-- offending argument/field and its value. See design.md "Error Handling"
-- for the authoritative condition -> requirement -> behavior table; each
-- exported function below corresponds to exactly one row of that table.
--
-- CONVENTION (raise level):
-- Every function in this module directly raises via `error(message, level)`
-- instead of returning a message string. Calling code simply does:
--
--     Errors.invalidDuration(value)  -- never returns; always throws
--
-- All builders call `error` with level 3. Level 1 would point at the `error`
-- call site inside this module (useless to the caller). Level 2 would point
-- at the validating function that called into Errors.luau (e.g. the body of
-- `Tween.to`), which is still internal to RoMotion. Level 3 walks one frame
-- further up the stack, past the validating/factory function, to the code
-- that actually called that factory/method -- i.e. the user's call site.
-- This matches "eager validation in the factory functions" described in
-- design.md: the factory (or a small helper it calls at the top of its own
-- body) is expected to call straight into an Errors.* builder, so 3 frames
-- up (error -> builder -> factory) lands on the caller of the factory.
--
-- If a validation helper is nested more than one call deep below the public
-- factory/method (i.e. Errors.* is invoked from a helper that itself is
-- invoked by the factory, not from the factory body directly), that extra
-- frame should be accounted for by wrapping the call in `pcall`/`assert` at
-- the shallower frame instead of by changing the level here, to keep this
-- module's convention uniform.

local RAISE_LEVEL = 3

local Errors = {}

--- Formats a Luau `typeof`-style value into a short, readable string for
--- error messages (handles nil, primitives, and generic tables/instances).
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

-- ---------------------------------------------------------------------------
-- Requirement 2.4: `duration` provided and not a number > 0.
-- ---------------------------------------------------------------------------
function Errors.invalidDuration(value: any)
	error(
		string.format(
			"RoMotion: invalid Tween_Config.duration %s -- duration must be a number greater than 0",
			describe(value)
		),
		RAISE_LEVEL
	)
end

-- ---------------------------------------------------------------------------
-- Requirements 2.5, 3.5: nil Target.
-- ---------------------------------------------------------------------------
function Errors.nilTarget()
	error("RoMotion: invalid argument Target (nil) -- Target must not be nil", RAISE_LEVEL)
end

-- ---------------------------------------------------------------------------
-- Requirements 2.6, 3.5: nil or empty Property_Map.
-- ---------------------------------------------------------------------------
function Errors.emptyPropertyMap(value: any)
	error(
		string.format(
			"RoMotion: invalid argument Property_Map %s -- Property_Map must be a non-nil table with at least one property",
			describe(value)
		),
		RAISE_LEVEL
	)
end

-- ---------------------------------------------------------------------------
-- Requirements 2.7, 3.6: property named in Property_Map absent on Target.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Requirement 3.4: `fromTo` start/end Property_Map key sets differ.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Requirement 4.7: start/end value type mismatch for a single property.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Requirement 4.8: property value type not supported by the Interpolator.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Requirement 5.8: `ease` string does not match any Easing_Library entry.
-- ---------------------------------------------------------------------------
function Errors.unknownEasing(name: string)
	error(
		string.format(
			"RoMotion: unknown easing %s -- no matching entry in the Easing_Library",
			describe(name)
		),
		RAISE_LEVEL
	)
end

-- ---------------------------------------------------------------------------
-- Requirement 5.9: custom `ease` function returned a non-numeric value.
-- ---------------------------------------------------------------------------
function Errors.invalidCustomEasingReturn(returnedValue: any)
	error(
		string.format(
			"RoMotion: invalid custom easing return value %s -- custom easing functions must return a number",
			describe(returnedValue)
		),
		RAISE_LEVEL
	)
end

-- ---------------------------------------------------------------------------
-- Requirement 6.7: invalid `repeat` (negative other than -1, or non-integer).
-- ---------------------------------------------------------------------------
function Errors.invalidRepeat(value: any)
	error(
		string.format(
			'RoMotion: invalid Tween_Config["repeat"] %s -- repeat must be an integer >= 0, or exactly -1 for infinite',
			describe(value)
		),
		RAISE_LEVEL
	)
end

-- ---------------------------------------------------------------------------
-- Requirement 6.8: invalid `delay` or `repeatDelay` (negative or > 86400).
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Requirement 7.5: malformed Relative_Value string.
-- ---------------------------------------------------------------------------
function Errors.malformedRelativeValue(spec: string)
	error(
		string.format(
			'RoMotion: invalid Relative_Value %s -- expected a string matching "+=X" or "-=X" with X a finite number',
			describe(spec)
		),
		RAISE_LEVEL
	)
end

-- ---------------------------------------------------------------------------
-- Requirement 7.6: Relative_Value applied to a non-number captured start.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Requirement 8.4: Keyframe fractional position outside 0..1.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Requirement 8.7: empty `keyframes` list, or two or more Keyframes sharing
-- the same fractional position.
-- ---------------------------------------------------------------------------
function Errors.invalidKeyframesList(reason: string)
	error(string.format("RoMotion: invalid keyframes list -- %s", reason), RAISE_LEVEL)
end

-- ---------------------------------------------------------------------------
-- Requirement 9.5: Timeline `timeScale` set to a value <= 0.
-- ---------------------------------------------------------------------------
function Errors.invalidTimeScale(value: any)
	error(
		string.format(
			"RoMotion: invalid Timeline timeScale %s -- timeScale must be a number greater than 0",
			describe(value)
		),
		RAISE_LEVEL
	)
end

-- ---------------------------------------------------------------------------
-- Requirement 9.7: Timeline added as a child of itself or a descendant.
-- ---------------------------------------------------------------------------
function Errors.cyclicNesting(child: any)
	error(
		string.format(
			"RoMotion: cyclic Timeline nesting detected -- child %s is the parent Timeline itself or one of its descendants",
			describe(child)
		),
		RAISE_LEVEL
	)
end

-- ---------------------------------------------------------------------------
-- Requirement 9.8: a non-Animation value added as a child to a Timeline.
-- ---------------------------------------------------------------------------
function Errors.invalidTimelineChild(value: any)
	error(
		string.format(
			"RoMotion: invalid Timeline child %s -- child must be an Animation (Tween or Timeline)",
			describe(value)
		),
		RAISE_LEVEL
	)
end

-- ---------------------------------------------------------------------------
-- Requirement 10.7: Position_Parameter names a Label that does not exist.
-- ---------------------------------------------------------------------------
function Errors.unknownLabel(name: string)
	error(
		string.format(
			"RoMotion: unknown label %s -- no Label with that name exists on this Timeline",
			describe(name)
		),
		RAISE_LEVEL
	)
end

-- ---------------------------------------------------------------------------
-- Requirement 10.8: numeric Position_Parameter is less than 0.
-- ---------------------------------------------------------------------------
function Errors.invalidPositionParameter(value: any)
	error(
		string.format(
			"RoMotion: invalid Position_Parameter %s -- numeric position parameters must be 0 or greater",
			describe(value)
		),
		RAISE_LEVEL
	)
end

-- ---------------------------------------------------------------------------
-- Requirement 11.4: `stagger` value not a number, or outside 0..3600.
-- ---------------------------------------------------------------------------
function Errors.invalidStagger(value: any)
	error(
		string.format(
			"RoMotion: invalid Tween_Config.stagger %s -- stagger must be a number in the range 0 to 3600 seconds",
			describe(value)
		),
		RAISE_LEVEL
	)
end

-- ---------------------------------------------------------------------------
-- Requirement 11.5: Targets list is empty.
-- ---------------------------------------------------------------------------
function Errors.emptyTargetsList()
	error("RoMotion: invalid argument Targets -- the Targets list must not be empty", RAISE_LEVEL)
end

return Errors
