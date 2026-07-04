--!strict
--!optimize 2
--!native
local Errors = require(script.Parent.Errors)

local Interpolator = {}
local DEFAULT_PROPERTY_NAME = "value"
local SUPPORTED_TYPES: { [string]: boolean } = {
	number = true,
	Vector2 = true,
	Vector3 = true,
	UDim = true,
	UDim2 = true,
	Color3 = true,
	CFrame = true,
}

function Interpolator.isSupported(value: any): boolean
	return SUPPORTED_TYPES[typeof(value)] == true
end

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

local function interpolateCFrame(start: CFrame, goal: CFrame, t: number): CFrame
	return start:Lerp(goal, t)
end

function Interpolator.interpolate(start: any, goal: any, easedProgress: number, propertyName: string?): any
	local name = propertyName or DEFAULT_PROPERTY_NAME

	local startType = typeof(start)
	local goalType = typeof(goal)

	if startType ~= goalType then
		Errors.typeMismatch(name, startType, goalType)
		return nil
	end

	if not SUPPORTED_TYPES[startType] then
		Errors.unsupportedType(name, startType)
		return nil
	end

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

	Errors.unsupportedType(name, startType)
	return nil
end

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
		return function(alpha)
			if alpha == 0 then
				return startValue
			elseif alpha == 1 then
				return goal
			end
			return startValue:Lerp(goal, alpha)
		end
	end

	Errors.unsupportedType(name, startType)
	return function()
		return startValue
	end
end

return Interpolator
