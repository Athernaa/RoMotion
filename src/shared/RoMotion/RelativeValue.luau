--!strict
local Errors = require(script.Parent.Errors)

local RelativeValue = {}

export type ParsedRelativeValue = {
	op: "+" | "-",
	amount: number,
}

local DEFAULT_PROPERTY_NAME = "value"
function RelativeValue.parse(spec: string): ParsedRelativeValue
	if typeof(spec) ~= "string" then
		Errors.malformedRelativeValue(spec)
		error("unreachable") -- Errors.malformedRelativeValue always raises
	end
	local opChar, numString = spec:match("^%s*([%+%-])=%s*(.-)%s*$")

	if opChar == nil or numString == nil or numString == "" then
		Errors.malformedRelativeValue(spec)
		error("unreachable") -- Errors.malformedRelativeValue always raises
	end

	local amount = tonumber(numString)
	if amount == nil or amount ~= amount or amount == math.huge or amount == -math.huge then
		Errors.malformedRelativeValue(spec)
		error("unreachable") -- Errors.malformedRelativeValue always raises
	end

	local op: "+" | "-" = if opChar == "+" then "+" else "-"

	return { op = op, amount = amount }
end

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
