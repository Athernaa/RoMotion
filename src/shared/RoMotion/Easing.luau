--!strict
--!optimize 2
--!native
-- RoMotion easing library.
--
-- Provides the built-in named Easing_Library (Linear, Quad, Cubic, Quart,
-- Quint, Sine, Expo, Circ, Back, Elastic, Bounce, each with In/Out/InOut
-- variants) plus `Easing.resolve`, which turns a Tween_Config `ease` field
-- (a name string, a custom Easing_Function, or nil) into a concrete
-- Easing_Function. See design.md "Easing.luau" and requirements.md
-- Requirement 5 for the authoritative contract.
--
-- CONVENTION (exact endpoints):
-- Every named easing function must return EXACTLY 0 at t=0 and EXACTLY 1 at
-- t=1 (Requirements 5.2, 5.3). Several of the underlying formulas (notably
-- Elastic and Bounce) accumulate floating-point drift near the boundaries
-- when evaluated directly, so rather than hand-tuning ~30 formulas, every
-- named function is wrapped with `exact01`, which short-circuits t=0 and
-- t=1 before the underlying formula ever runs. The raw formulas themselves
-- only ever need to be correct -- and finite -- on the open interval (0, 1)
-- (Requirement 5.4), which they are.
--
-- CONVENTION (name lookup / resolve):
-- Named easing functions are exposed two ways: nested access for direct use
-- (`Easing.Quad.InOut`) and a flat `name -> function` table (`"Quad.InOut"`,
-- `"Bounce.Out"`, ...) used by `Easing.resolve` for string lookup
-- (Requirement 5.5). Because Linear's three variants are identical, the bare
-- name `"Linear"` (no `.In`/`.Out`/`.InOut` suffix) is also accepted as an
-- alias for `Easing.Linear.InOut`.

local Errors = require(script.Parent.Errors)
local Types = require(script.Parent.Types)

type Easing_Function = Types.Easing_Function

local Easing = {}

--- Wraps a raw easing formula so t=0 and t=1 always return exactly 0 and 1,
--- regardless of floating-point drift in the underlying formula.
local function exact01(fn: (number) -> number): Easing_Function
	return function(t: number): number
		if t == 0 then
			return 0
		elseif t == 1 then
			return 1
		end
		return fn(t)
	end
end

-- ---------------------------------------------------------------------------
-- Linear
-- ---------------------------------------------------------------------------

local function linear(t: number): number
	return t
end

-- ---------------------------------------------------------------------------
-- Quad
-- ---------------------------------------------------------------------------

local function quadIn(t: number): number
	return t * t
end

local function quadOut(t: number): number
	local f = 1 - t
	return 1 - f * f
end

local function quadInOut(t: number): number
	if t < 0.5 then
		return 2 * t * t
	else
		local f = -2 * t + 2
		return 1 - (f * f) / 2
	end
end

-- ---------------------------------------------------------------------------
-- Cubic
-- ---------------------------------------------------------------------------

local function cubicIn(t: number): number
	return t * t * t
end

local function cubicOut(t: number): number
	local f = 1 - t
	return 1 - f * f * f
end

local function cubicInOut(t: number): number
	if t < 0.5 then
		return 4 * t * t * t
	else
		local f = -2 * t + 2
		return 1 - (f * f * f) / 2
	end
end

-- ---------------------------------------------------------------------------
-- Quart
-- ---------------------------------------------------------------------------

local function quartIn(t: number): number
	return t * t * t * t
end

local function quartOut(t: number): number
	local f = 1 - t
	return 1 - f * f * f * f
end

local function quartInOut(t: number): number
	if t < 0.5 then
		return 8 * t * t * t * t
	else
		local f = -2 * t + 2
		return 1 - (f * f * f * f) / 2
	end
end

-- ---------------------------------------------------------------------------
-- Quint
-- ---------------------------------------------------------------------------

local function quintIn(t: number): number
	return t * t * t * t * t
end

local function quintOut(t: number): number
	local f = 1 - t
	return 1 - f * f * f * f * f
end

local function quintInOut(t: number): number
	if t < 0.5 then
		return 16 * t * t * t * t * t
	else
		local f = -2 * t + 2
		return 1 - (f * f * f * f * f) / 2
	end
end

-- ---------------------------------------------------------------------------
-- Sine
-- ---------------------------------------------------------------------------

local HALF_PI = math.pi / 2

local function sineIn(t: number): number
	return 1 - math.cos(t * HALF_PI)
end

local function sineOut(t: number): number
	return math.sin(t * HALF_PI)
end

local function sineInOut(t: number): number
	return -(math.cos(math.pi * t) - 1) / 2
end

-- ---------------------------------------------------------------------------
-- Expo
-- ---------------------------------------------------------------------------

local function expoIn(t: number): number
	return 2 ^ (10 * t - 10)
end

local function expoOut(t: number): number
	return 1 - 2 ^ (-10 * t)
end

local function expoInOut(t: number): number
	if t < 0.5 then
		return (2 ^ (20 * t - 10)) / 2
	else
		return (2 - 2 ^ (-20 * t + 10)) / 2
	end
end

-- ---------------------------------------------------------------------------
-- Circ
-- ---------------------------------------------------------------------------

local function circIn(t: number): number
	return 1 - math.sqrt(1 - t * t)
end

local function circOut(t: number): number
	local f = t - 1
	return math.sqrt(1 - f * f)
end

local function circInOut(t: number): number
	if t < 0.5 then
		local f = 2 * t
		return (1 - math.sqrt(1 - f * f)) / 2
	else
		local f = -2 * t + 2
		return (math.sqrt(1 - f * f) + 1) / 2
	end
end

-- ---------------------------------------------------------------------------
-- Back
-- ---------------------------------------------------------------------------

local BACK_C1 = 1.70158
local BACK_C2 = BACK_C1 * 1.525
local BACK_C3 = BACK_C1 + 1

local function backIn(t: number): number
	return BACK_C3 * t * t * t - BACK_C1 * t * t
end

local function backOut(t: number): number
	local f = t - 1
	return 1 + BACK_C3 * f * f * f + BACK_C1 * f * f
end

local function backInOut(t: number): number
	if t < 0.5 then
		local f = 2 * t
		return (f * f * ((BACK_C2 + 1) * f - BACK_C2)) / 2
	else
		local f = 2 * t - 2
		return (f * f * ((BACK_C2 + 1) * f + BACK_C2) + 2) / 2
	end
end

-- ---------------------------------------------------------------------------
-- Elastic
-- ---------------------------------------------------------------------------

local ELASTIC_C4 = (2 * math.pi) / 3
local ELASTIC_C5 = (2 * math.pi) / 4.5

local function elasticIn(t: number): number
	return -(2 ^ (10 * t - 10)) * math.sin((10 * t - 10.75) * ELASTIC_C4)
end

local function elasticOut(t: number): number
	return (2 ^ (-10 * t)) * math.sin((10 * t - 0.75) * ELASTIC_C4) + 1
end

local function elasticInOut(t: number): number
	if t < 0.5 then
		return -((2 ^ (20 * t - 10)) * math.sin((20 * t - 11.125) * ELASTIC_C5)) / 2
	else
		return ((2 ^ (-20 * t + 10)) * math.sin((20 * t - 11.125) * ELASTIC_C5)) / 2 + 1
	end
end

-- ---------------------------------------------------------------------------
-- Bounce
-- ---------------------------------------------------------------------------

local BOUNCE_N1 = 7.5625
local BOUNCE_D1 = 2.75

-- Shared raw bounce-out formula reused by bounceIn/bounceInOut via the
-- standard "mirror through 1-t" and "half-and-mirror" compositions.
local function bounceOutRaw(t: number): number
	if t < 1 / BOUNCE_D1 then
		return BOUNCE_N1 * t * t
	elseif t < 2 / BOUNCE_D1 then
		local f = t - 1.5 / BOUNCE_D1
		return BOUNCE_N1 * f * f + 0.75
	elseif t < 2.5 / BOUNCE_D1 then
		local f = t - 2.25 / BOUNCE_D1
		return BOUNCE_N1 * f * f + 0.9375
	else
		local f = t - 2.625 / BOUNCE_D1
		return BOUNCE_N1 * f * f + 0.984375
	end
end

local function bounceIn(t: number): number
	return 1 - bounceOutRaw(1 - t)
end

local function bounceOut(t: number): number
	return bounceOutRaw(t)
end

local function bounceInOut(t: number): number
	if t < 0.5 then
		return (1 - bounceOutRaw(1 - 2 * t)) / 2
	else
		return (1 + bounceOutRaw(2 * t - 1)) / 2
	end
end

-- ---------------------------------------------------------------------------
-- Requirement 5.1: assemble the nested Easing_Library surface
-- (`Easing.Quad.InOut`, `Easing.Bounce.Out`, ...), each variant wrapped with
-- `exact01` to satisfy Requirements 5.2, 5.3.
-- ---------------------------------------------------------------------------

Easing.Linear = {
	In = exact01(linear),
	Out = exact01(linear),
	InOut = exact01(linear),
}

Easing.Quad = {
	In = exact01(quadIn),
	Out = exact01(quadOut),
	InOut = exact01(quadInOut),
}

Easing.Cubic = {
	In = exact01(cubicIn),
	Out = exact01(cubicOut),
	InOut = exact01(cubicInOut),
}

Easing.Quart = {
	In = exact01(quartIn),
	Out = exact01(quartOut),
	InOut = exact01(quartInOut),
}

Easing.Quint = {
	In = exact01(quintIn),
	Out = exact01(quintOut),
	InOut = exact01(quintInOut),
}

Easing.Sine = {
	In = exact01(sineIn),
	Out = exact01(sineOut),
	InOut = exact01(sineInOut),
}

Easing.Expo = {
	In = exact01(expoIn),
	Out = exact01(expoOut),
	InOut = exact01(expoInOut),
}

Easing.Circ = {
	In = exact01(circIn),
	Out = exact01(circOut),
	InOut = exact01(circInOut),
}

Easing.Back = {
	In = exact01(backIn),
	Out = exact01(backOut),
	InOut = exact01(backInOut),
}

Easing.Elastic = {
	In = exact01(elasticIn),
	Out = exact01(elasticOut),
	InOut = exact01(elasticInOut),
}

Easing.Bounce = {
	In = exact01(bounceIn),
	Out = exact01(bounceOut),
	InOut = exact01(bounceInOut),
}

-- ---------------------------------------------------------------------------
-- Requirement 5.5: flat `name -> Easing_Function` table used by `resolve`
-- for exact-match string lookup (e.g. "Quad.InOut", "Bounce.Out").
-- ---------------------------------------------------------------------------

local EasingByName: { [string]: Easing_Function } = {
	["Linear.In"] = Easing.Linear.In,
	["Linear.Out"] = Easing.Linear.Out,
	["Linear.InOut"] = Easing.Linear.InOut,
	["Quad.In"] = Easing.Quad.In,
	["Quad.Out"] = Easing.Quad.Out,
	["Quad.InOut"] = Easing.Quad.InOut,
	["Cubic.In"] = Easing.Cubic.In,
	["Cubic.Out"] = Easing.Cubic.Out,
	["Cubic.InOut"] = Easing.Cubic.InOut,
	["Quart.In"] = Easing.Quart.In,
	["Quart.Out"] = Easing.Quart.Out,
	["Quart.InOut"] = Easing.Quart.InOut,
	["Quint.In"] = Easing.Quint.In,
	["Quint.Out"] = Easing.Quint.Out,
	["Quint.InOut"] = Easing.Quint.InOut,
	["Sine.In"] = Easing.Sine.In,
	["Sine.Out"] = Easing.Sine.Out,
	["Sine.InOut"] = Easing.Sine.InOut,
	["Expo.In"] = Easing.Expo.In,
	["Expo.Out"] = Easing.Expo.Out,
	["Expo.InOut"] = Easing.Expo.InOut,
	["Circ.In"] = Easing.Circ.In,
	["Circ.Out"] = Easing.Circ.Out,
	["Circ.InOut"] = Easing.Circ.InOut,
	["Back.In"] = Easing.Back.In,
	["Back.Out"] = Easing.Back.Out,
	["Back.InOut"] = Easing.Back.InOut,
	["Elastic.In"] = Easing.Elastic.In,
	["Elastic.Out"] = Easing.Elastic.Out,
	["Elastic.InOut"] = Easing.Elastic.InOut,
	["Bounce.In"] = Easing.Bounce.In,
	["Bounce.Out"] = Easing.Bounce.Out,
	["Bounce.InOut"] = Easing.Bounce.InOut,
}

-- Bare "Linear" is accepted as an alias for "Linear.InOut": all three Linear
-- variants are identical, so there is no In/Out/InOut distinction to lose.
EasingByName["Linear"] = Easing.Linear.InOut

local DEFAULT_EASING_NAME = "Quad.InOut"

-- ---------------------------------------------------------------------------
-- Requirements 5.5, 5.6, 5.7, 5.8: resolve a Tween_Config `ease` field (a
-- name string, a custom Easing_Function, or nil) to a concrete
-- Easing_Function.
-- ---------------------------------------------------------------------------
function Easing.resolve(ease: (string | Easing_Function)?): Easing_Function
	-- Requirement 5.7: omitted `ease` defaults to Quad.InOut.
	if ease == nil then
		return EasingByName[DEFAULT_EASING_NAME]
	end

	local easeType = typeof(ease)

	-- Requirement 5.6: a supplied function is passed through as-is; RoMotion
	-- invokes it directly with progress `t` when rendering the Tween.
	if easeType == "function" then
		return ease :: Easing_Function
	end

	-- Requirement 5.5: an exact-match string name resolves to the
	-- corresponding Easing_Library entry.
	if easeType == "string" then
		local name = ease :: string
		local fn = EasingByName[name]
		if fn ~= nil then
			return fn
		end

		-- Requirement 5.8: unknown easing name -- error and do not resolve.
		Errors.unknownEasing(name)
		return (nil :: any) :: Easing_Function -- unreachable: unknownEasing always raises
	end

	-- Defensive fallback: `ease` is typed as `(string | Easing_Function)?`,
	-- so this branch is unreachable for well-typed callers, but is handled
	-- rather than silently returning an invalid value.
	Errors.unknownEasing(tostring(ease))
	return (nil :: any) :: Easing_Function -- unreachable: unknownEasing always raises
end

return Easing
