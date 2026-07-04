--!strict
--!optimize 2
--!native
-- RoMotion pure interpolation core.
--
-- Computes an intermediate value between a `start` value and a `goal` value
-- at a given eased progress, for every Roblox data type RoMotion supports.
-- See design.md "Interpolator.luau" and requirements.md Requirement 4 for
-- the authoritative behavior; this module implements that contract exactly:
--
--   Interpolator.interpolate: (start: any, goal: any, easedProgress: number, propertyName: string?) -> any
--   Interpolator.isSupported: (value: any) -> boolean
--
-- Supported types (Requirement 4.1): number, Vector2, Vector3, UDim, UDim2,
-- Color3, CFrame.
--
-- CONVENTION (propertyName parameter):
-- The public `Interpolator.interpolate` signature in design.md is
-- `(start: any, goal: any, easedProgress: number) -> any` -- it has no
-- notion of a property name, because Interpolator is a pure function with
-- no knowledge of the Tween/Target/Property_Map that called it. But the
-- shared `Errors.luau` builders `Errors.typeMismatch` and
-- `Errors.unsupportedType` both take a property name so error messages can
-- name the offending property (Requirements 4.7, 4.8). To reuse those
-- builders without modifying Errors.luau, `interpolate` accepts an
-- *optional* trailing `propertyName: string?` argument; callers that have a
-- property name (e.g. Tween.luau) should pass it, and calls that omit it
-- fall back to a generic placeholder name below. This keeps the 3-argument
-- call shape from design.md fully compatible while allowing richer error
-- messages when a caller has more context.
--
-- CONVENTION (validate-then-compute):
-- Both error conditions are checked before any interpolation math runs.
-- Interpolator has no target reference to "leave unchanged", so honoring
-- the design's "leaving target unchanged" guidance (Requirements 4.7, 4.8)
-- simply means: never perform partial computation before raising.

local Errors = require(script.Parent.Errors)

local Interpolator = {}

-- Placeholder property name used when a caller does not supply one.
local DEFAULT_PROPERTY_NAME = "value"

-- The exhaustive set of `typeof(...)` results this module can interpolate.
local SUPPORTED_TYPES: { [string]: boolean } = {
	number = true,
	Vector2 = true,
	Vector3 = true,
	UDim = true,
	UDim2 = true,
	Color3 = true,
	CFrame = true,
}

--- Requirement 4.1: reports whether a value's runtime type is one of the
--- seven types this Interpolator supports.
function Interpolator.isSupported(value: any): boolean
	return SUPPORTED_TYPES[typeof(value)] == true
end

-- ---------------------------------------------------------------------------
-- Per-type component-wise linear interpolation (Requirements 4.2, 4.3, 4.4).
--
-- Each of these is only ever invoked with easedProgress strictly outside the
-- {0, 1} shortcut handled directly in `interpolate`, but they are written to
-- be correct for any real number (including values outside 0..1, to support
-- overshoot easing -- Requirement 4.1).
-- ---------------------------------------------------------------------------

local function lerpNumber(start: number, goal: number, t: number): number
	return start + (goal - start) * t
end

local function interpolateVector2(start: Vector2, goal: Vector2, t: number): Vector2
	return Vector2.new(lerpNumber(start.X, goal.X, t), lerpNumber(start.Y, goal.Y, t))
end

local function interpolateVector3(start: Vector3, goal: Vector3, t: number): Vector3
	return Vector3.new(
		lerpNumber(start.X, goal.X, t),
		lerpNumber(start.Y, goal.Y, t),
		lerpNumber(start.Z, goal.Z, t)
	)
end

local function interpolateUDim(start: UDim, goal: UDim, t: number): UDim
	return UDim.new(lerpNumber(start.Scale, goal.Scale, t), lerpNumber(start.Offset, goal.Offset, t))
end

local function interpolateUDim2(start: UDim2, goal: UDim2, t: number): UDim2
	return UDim2.new(
		lerpNumber(start.X.Scale, goal.X.Scale, t),
		lerpNumber(start.X.Offset, goal.X.Offset, t),
		lerpNumber(start.Y.Scale, goal.Y.Scale, t),
		lerpNumber(start.Y.Offset, goal.Y.Offset, t)
	)
end

local function interpolateColor3(start: Color3, goal: Color3, t: number): Color3
	return Color3.new(
		lerpNumber(start.R, goal.R, t),
		lerpNumber(start.G, goal.G, t),
		lerpNumber(start.B, goal.B, t)
	)
end

-- Requirement 4.4: CFrame position via linear interpolation, rotation via
-- spherical linear interpolation. Roblox's `CFrame:Lerp` already implements
-- exactly this combination (position lerp + rotation slerp) in one call, so
-- it is used directly here rather than re-deriving the math. The p == 0 and
-- p == 1 exactness guarantee (Requirements 4.5, 4.6) is handled by the
-- caller via an explicit shortcut, not by relying on `:Lerp`'s behavior at
-- the boundaries.
local function interpolateCFrame(start: CFrame, goal: CFrame, t: number): CFrame
	return start:Lerp(goal, t)
end

--- Requirement 4.1-4.8: interpolates `start` toward `goal` at `easedProgress`.
--- `easedProgress` may lie outside the closed interval 0..1 (overshoot
--- easing); the component-wise formulas below support that without clamping.
function Interpolator.interpolate(start: any, goal: any, easedProgress: number, propertyName: string?): any
	local name = propertyName or DEFAULT_PROPERTY_NAME

	local startType = typeof(start)
	local goalType = typeof(goal)

	-- Requirement 4.7: start/end type mismatch. Validate before any
	-- computation is attempted.
	if startType ~= goalType then
		Errors.typeMismatch(name, startType, goalType)
		return nil
	end

	-- Requirement 4.8: neither type is one of the seven supported types.
	if not SUPPORTED_TYPES[startType] then
		Errors.unsupportedType(name, startType)
		return nil
	end

	-- Requirements 4.5, 4.6: exact endpoints. The general per-component
	-- formula `start + (goal - start) * p` is not guaranteed to reproduce
	-- `start`/`goal` bit-for-bit at the boundaries (floating point error,
	-- and for CFrame, `:Lerp` is not guaranteed to bitwise-reproduce the
	-- original CFrame at alpha 0 or 1), so both boundaries return the
	-- original value directly instead of going through the formula.
	if easedProgress == 0 then
		return start
	elseif easedProgress == 1 then
		return goal
	end

	if startType == "number" then
		return lerpNumber(start, goal, easedProgress)
	elseif startType == "Vector2" then
		return interpolateVector2(start, goal, easedProgress)
	elseif startType == "Vector3" then
		return interpolateVector3(start, goal, easedProgress)
	elseif startType == "UDim" then
		return interpolateUDim(start, goal, easedProgress)
	elseif startType == "UDim2" then
		return interpolateUDim2(start, goal, easedProgress)
	elseif startType == "Color3" then
		return interpolateColor3(start, goal, easedProgress)
	elseif startType == "CFrame" then
		return interpolateCFrame(start, goal, easedProgress)
	end

	-- Unreachable: SUPPORTED_TYPES is exhaustive over the branches above, so
	-- every type that passes the `isSupported` check is handled. Kept as a
	-- defensive fallback rather than a silent `nil` return.
	Errors.unsupportedType(name, startType)
	return nil
end

-- ---------------------------------------------------------------------------
-- buildLerp: closure specialization for the per-frame hot path.
--
-- `interpolate` above re-checks `typeof` on both operands and walks a
-- type-dispatch chain on EVERY call. For an animation that runs for many
-- frames, the value type never changes, so that dispatch is pure per-frame
-- overhead. `buildLerp` resolves the type and precomputes the per-component
-- deltas ONCE, then returns a specialized `(alpha) -> value` closure that
-- does only the arithmetic for that one type -- no `typeof`, no branching.
-- This mirrors how the fastest Roblox tween libraries (e.g. TweenPlus)
-- pre-process values at tween-creation time.
--
-- Type validation (Requirements 4.7, 4.8) happens here, at build time (which
-- is the moment the tween captures its active phase), instead of per render;
-- the raise still occurs before any value is written, so the "leave target
-- unchanged" guarantee holds. Exact endpoints (Requirements 4.5, 4.6) are
-- preserved by the `alpha == 0`/`alpha == 1` shortcuts inside each closure.
--
-- The returned closure supports `alpha` outside 0..1 (overshoot easing,
-- Requirement 4.1) exactly like `interpolate`.
function Interpolator.buildLerp(startValue: any, goal: any, propertyName: string?): (alpha: number) -> any
	local name = propertyName or DEFAULT_PROPERTY_NAME

	local startType = typeof(startValue)
	local goalType = typeof(goal)

	if startType ~= goalType then
		Errors.typeMismatch(name, startType, goalType)
	end
	if not SUPPORTED_TYPES[startType] then
		Errors.unsupportedType(name, startType)
	end

	if startType == "number" then
		local difference = goal - startValue
		return function(alpha)
			if alpha == 0 then
				return startValue
			elseif alpha == 1 then
				return goal
			end
			return startValue + difference * alpha
		end
	elseif startType == "Vector3" or startType == "Vector2" then
		-- Vector2/Vector3 support component-wise `+` and scalar `*` natively.
		local difference = goal - startValue
		return function(alpha)
			if alpha == 0 then
				return startValue
			elseif alpha == 1 then
				return goal
			end
			return startValue + difference * alpha
		end
	elseif startType == "Color3" then
		local sr, sg, sb = startValue.R, startValue.G, startValue.B
		local dr, dg, db = goal.R - sr, goal.G - sg, goal.B - sb
		return function(alpha)
			if alpha == 0 then
				return startValue
			elseif alpha == 1 then
				return goal
			end
			return Color3.new(sr + dr * alpha, sg + dg * alpha, sb + db * alpha)
		end
	elseif startType == "UDim" then
		local ss, so = startValue.Scale, startValue.Offset
		local ds, doff = goal.Scale - ss, goal.Offset - so
		return function(alpha)
			if alpha == 0 then
				return startValue
			elseif alpha == 1 then
				return goal
			end
			return UDim.new(ss + ds * alpha, so + doff * alpha)
		end
	elseif startType == "UDim2" then
		local sxs, sxo = startValue.X.Scale, startValue.X.Offset
		local sys, syo = startValue.Y.Scale, startValue.Y.Offset
		local dxs, dxo = goal.X.Scale - sxs, goal.X.Offset - sxo
		local dys, dyo = goal.Y.Scale - sys, goal.Y.Offset - syo
		return function(alpha)
			if alpha == 0 then
				return startValue
			elseif alpha == 1 then
				return goal
			end
			return UDim2.new(sxs + dxs * alpha, sxo + dxo * alpha, sys + dys * alpha, syo + dyo * alpha)
		end
	elseif startType == "CFrame" then
		-- CFrame:Lerp is a native (C) call that already does position lerp +
		-- rotation slerp; capturing the endpoints and calling it directly is
		-- cheaper than re-dispatching through `interpolate` each frame.
		return function(alpha)
			if alpha == 0 then
				return startValue
			elseif alpha == 1 then
				return goal
			end
			return startValue:Lerp(goal, alpha)
		end
	end

	-- Unreachable: SUPPORTED_TYPES gates the branches above.
	Errors.unsupportedType(name, startType)
	return function()
		return startValue
	end
end

return Interpolator
