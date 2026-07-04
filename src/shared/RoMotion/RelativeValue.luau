--!strict
-- RoMotion relative value parsing.
--
-- Parses and resolves GSAP-style relative destination strings ("+=X",
-- "-=X") used as Property_Map values for number-typed properties. See
-- design.md "RelativeValue.luau" and requirements.md Requirement 7 for the
-- authoritative contract:
--
--   RelativeValue.parse: (spec: string) -> { op: "+" | "-", amount: number }
--   RelativeValue.resolve: (startValue: number, spec: string) -> number
--
-- CONVENTION (propertyName parameter):
-- Mirrors Interpolator.luau's optional trailing `propertyName: string?`
-- convention: the design's `resolve(startValue: number, spec: string) ->
-- number` signature has no notion of a property name, because
-- RelativeValue is a pure function with no knowledge of the
-- Tween/Target/Property_Map that called it. But `Errors.nonNumericRelativeStart`
-- (Requirement 7.6) names the offending property, so `resolve` accepts an
-- *optional* trailing `propertyName: string?` argument; callers that have a
-- property name (e.g. Tween.luau) should pass it, and calls that omit it
-- fall back to a generic placeholder name below. This keeps the 2-argument
-- call shape from design.md fully compatible while allowing richer error
-- messages when a caller has more context.
--
-- CONVENTION (validate-then-compute):
-- Both `parse` and `resolve` validate their inputs completely before doing
-- any arithmetic, matching Interpolator.luau's pattern: RelativeValue has no
-- target reference to "leave unchanged", so honoring the design's "leaving
-- the Target's property value unchanged" guidance (Requirements 7.5, 7.6)
-- simply means the caller (Tween.luau) never receives a computed end value
-- to apply -- `error()` (raised by the Errors.* builders) unwinds before any
-- value is returned.
--
-- CONVENTION (validation order in `resolve`):
-- `resolve` checks the `spec` string's syntax (Requirement 7.5, via
-- `parse`) before checking whether `startValue` is numeric (Requirement
-- 7.6). A malformed Relative_Value string is invalid on its own terms
-- regardless of what it would be applied against, so it is surfaced first;
-- only a syntactically valid Relative_Value can meaningfully be described
-- as "assigned to a property whose captured start value is not of type
-- number" per Requirement 7.6's wording.

local Errors = require(script.Parent.Errors)

local RelativeValue = {}

export type ParsedRelativeValue = {
	op: "+" | "-",
	amount: number,
}

-- Placeholder property name used when a caller does not supply one.
local DEFAULT_PROPERTY_NAME = "value"

--- Requirements 7.1, 7.2, 7.4, 7.5: parses a Relative_Value string of the
--- form "+=X" or "-=X" (tolerating arbitrary whitespace around the "+="/"-="
--- operator and around the numeric portion X) into its operator and numeric
--- amount. Raises via `Errors.malformedRelativeValue` if `spec` is not a
--- string, does not match the "+=X"/"-=X" pattern, or X does not parse as a
--- finite number.
function RelativeValue.parse(spec: string): ParsedRelativeValue
	-- `spec` is typed as `string` per the design signature, but callers may
	-- pass an arbitrary Property_Map value at runtime (e.g. a number,
	-- Vector3, or nil), so its type is validated defensively before any
	-- string operation is attempted.
	if typeof(spec) ~= "string" then
		Errors.malformedRelativeValue(spec)
		error("unreachable") -- Errors.malformedRelativeValue always raises
	end

	-- Requirement 7.4: tolerate leading/trailing whitespace around the
	-- "+="/"-=" operator and around the numeric portion X. The operator is
	-- matched as the two-character token "+=" or "-=" so that whitespace is
	-- only ever "around" it, never splitting it apart (e.g. "+ =5" does not
	-- match, matching the pattern "+=X" described by Requirement 7.1/7.2).
	local opChar, numString = spec:match("^%s*([%+%-])=%s*(.-)%s*$")

	if opChar == nil or numString == nil or numString == "" then
		Errors.malformedRelativeValue(spec)
		error("unreachable") -- Errors.malformedRelativeValue always raises
	end

	local amount = tonumber(numString)

	-- Requirement 7.5: X must parse as a finite number. `tonumber` returns
	-- nil for anything it cannot parse as a number at all; guard separately
	-- against non-finite results (e.g. an overflowing exponent such as
	-- "1e400") and NaN, neither of which counts as "a finite number".
	if amount == nil or amount ~= amount or amount == math.huge or amount == -math.huge then
		Errors.malformedRelativeValue(spec)
		error("unreachable") -- Errors.malformedRelativeValue always raises
	end

	local op: "+" | "-" = if opChar == "+" then "+" else "-"

	return { op = op, amount = amount }
end

--- Requirements 7.1, 7.2, 7.3, 7.6: resolves a Relative_Value `spec` against
--- a captured `startValue`, returning `startValue + amount` for "+=X" and
--- `startValue - amount` for "-=X". Raises via `Errors.malformedRelativeValue`
--- if `spec` is malformed (Requirement 7.5), or via
--- `Errors.nonNumericRelativeStart` if `startValue` is not of type number
--- (Requirement 7.6). `startValue` is typed as `number` per the design
--- signature, but is validated defensively here since callers may pass a
--- runtime value captured from an arbitrary Target property (e.g. a string
--- or Vector3) if that property turns out not to be numeric.
function RelativeValue.resolve(startValue: number, spec: string, propertyName: string?): number
	local parsed = RelativeValue.parse(spec)

	if typeof(startValue) ~= "number" then
		local name = propertyName or DEFAULT_PROPERTY_NAME
		Errors.nonNumericRelativeStart(name, typeof(startValue))
		return 0 -- unreachable: Errors.nonNumericRelativeStart always raises
	end

	if parsed.op == "+" then
		return startValue + parsed.amount
	else
		return startValue - parsed.amount
	end
end

return RelativeValue
