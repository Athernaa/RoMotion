--!strict
--!optimize 2
--!native

local Types = require(script.Parent.Types)
local Animation = require(script.Parent.Animation)
local Interpolator = require(script.Parent.Interpolator)
local Easing = require(script.Parent.Easing)
local Errors = require(script.Parent.Errors)
local RelativeValue = require(script.Parent.RelativeValue)

local DEFAULT_DURATION = 0.5
type Mode = "to" | "from" | "fromTo"
type TargetOrTargets = Types.Target | { Types.Target }
type InternalTween = Types.Tween & {
	mode: Mode,
	iterationDuration: number,
	invIterationDuration: number,
	invCycleLength: number,
	delay: number,
	repeatCount: number,
	repeatDelay: number,
	yoyo: boolean,
	keyframeEase: { Types.Easing_Function }?,
	keyframeWaypoints: { KeyframeWaypoint }?,
	lastCompletedIterations: number,
	completeFired: boolean,
	hasCallbacks: boolean,
	fullyCaptured: boolean,
}
type KeyframeWaypoint = {
	position: number,
	keyframeIndex: number?,
}

local Tween = setmetatable({}, { __index = Animation })
Tween.__index = Tween

local function readProperty(target: Types.Target, propertyName: string): any
	return (target :: any)[propertyName]
end

local function writeProperty(target: Types.Target, propertyName: string, value: any): ()
	(target :: any)[propertyName] = value
end

local function propertyExists(target: Types.Target, propertyName: string): boolean
	local ok, value = pcall(function()
		return (target :: any)[propertyName]
	end)
	return ok and value ~= nil
end

local function resolveEndValue(rawValue: any, startValue: any, propertyName: string): any
	if typeof(rawValue) ~= "string" then
		return rawValue
	end

	return RelativeValue.resolve(startValue, rawValue, propertyName)
end

local function isTargetAlive(target: Types.Target): boolean
	if typeof(target) ~= "Instance" then
		return true
	end

	return (target :: Instance).Parent ~= nil
end

local function releaseTargets(self: InternalTween): ()
	self.targets = {}
	self.resolved = {}
	self.staggerOffset = {}
end

local function dropDeadTargets(self: InternalTween): ()
	local anyAlive = false

	for _, targetPlan in self.resolved do
		if targetPlan.alive and not isTargetAlive(targetPlan.target) then
			targetPlan.alive = false
		end

		if targetPlan.alive then
			anyAlive = true
		end
	end

	if not anyAlive and self.state ~= "killed" and self.state ~= "completed" then
		Animation._complete(self)
		releaseTargets(self)
	end
end

local function hasAtLeastOneProperty(map: Types.PropertyMap?): boolean
	if map == nil then
		return false
	end
	for _ in map do
		return true
	end
	return false
end

local function validatePropertiesExist(target: Types.Target, map: Types.PropertyMap): ()
	for propertyName in map do
		if not propertyExists(target, propertyName) then
			Errors.missingProperty(propertyName, target)
		end
	end
end

local function validateKeySets(startMap: Types.PropertyMap, endMap: Types.PropertyMap): ()
	local startKeys: { string } = {}
	local endKeys: { string } = {}
	local endSet: { [string]: boolean } = {}

	for propertyName in endMap do
		table.insert(endKeys, propertyName)
		endSet[propertyName] = true
	end

	local mismatch = false
	local startCount = 0
	for propertyName in startMap do
		table.insert(startKeys, propertyName)
		startCount += 1
		if not endSet[propertyName] then
			mismatch = true
		end
	end

	if startCount ~= #endKeys then
		mismatch = true
	end

	if mismatch then
		table.sort(startKeys)
		table.sort(endKeys)
		Errors.fromToKeyMismatch(startKeys, endKeys)
	end
end

local function resolveDuration(config: Types.Tween_Config): number
	local duration = config.duration

	if duration == nil then
		return DEFAULT_DURATION
	end

	if typeof(duration) ~= "number" or duration <= 0 then
		Errors.invalidDuration(duration)
		return 0 -- unreachable: Errors.invalidDuration always raises
	end

	return duration
end

local MAX_DELAY = 86400
local MAX_REPEAT = 1000000

local function resolveRepeat(config: Types.Tween_Config): number
	local repeatCount = config["repeat"]

	if repeatCount == nil then
		return 0
	end

	if typeof(repeatCount) ~= "number" then
		Errors.invalidRepeat(repeatCount)
		return 0 -- unreachable: Errors.invalidRepeat always raises
	end

	if repeatCount == -1 then
		return -1
	end

	if repeatCount < 0 or repeatCount ~= math.floor(repeatCount) or repeatCount > MAX_REPEAT then
		Errors.invalidRepeat(repeatCount)
		return 0 -- unreachable: Errors.invalidRepeat always raises
	end

	return repeatCount
end

local function resolveDelayField(config: Types.Tween_Config, fieldName: "delay" | "repeatDelay"): number
	local value = (config :: any)[fieldName]

	if value == nil then
		return 0
	end

	if typeof(value) ~= "number" or value < 0 or value > MAX_DELAY then
		Errors.invalidDelay(fieldName, value)
		return 0 -- unreachable: Errors.invalidDelay always raises
	end

	return value
end

local function resolveYoyo(config: Types.Tween_Config): boolean
	return config.yoyo == true
end

local MAX_STAGGER = 3600

local function resolveStagger(config: Types.Tween_Config): number
	local stagger = config.stagger

	if stagger == nil then
		return 0
	end

	if typeof(stagger) ~= "number" or stagger < 0 or stagger > MAX_STAGGER then
		Errors.invalidStagger(stagger)
		return 0 -- unreachable: Errors.invalidStagger always raises
	end

	return stagger
end

local function isTargetShaped(value: any): boolean
	local ty = typeof(value)
	return ty == "Instance" or ty == "table"
end

local function isTargetList(value: any): boolean
	if typeof(value) ~= "table" then
		return false
	end

	local arrayLength = #(value :: { any })

	local totalKeys = 0
	for _ in (value :: any) do
		totalKeys += 1
	end

	if totalKeys == 0 then
		return true
	end

	if arrayLength == 0 or arrayLength ~= totalKeys then
		return false
	end

	for i = 1, arrayLength do
		if not isTargetShaped((value :: any)[i]) then
			return false
		end
	end

	return true
end

local function resolveTargetList(target: any): { Types.Target }
	if isTargetList(target) then
		local list = target :: { Types.Target }
		if #list == 0 then
			Errors.emptyTargetsList()
			return {} -- unreachable: Errors.emptyTargetsList always raises
		end
		return list
	end

	return { target :: Types.Target }
end

local function validateKeyframePosition(position: any, index: number): ()
	if typeof(position) ~= "number" or position < 0 or position > 1 then
		Errors.invalidKeyframePosition(position, index)
	end
end

local function resolveKeyframes(config: Types.Tween_Config): ({ Types.Keyframe }?, { Types.Easing_Function }?)
	local rawKeyframes = config.keyframes

	if rawKeyframes == nil then
		return nil, nil
	end

	if #rawKeyframes == 0 then
		Errors.invalidKeyframesList("the keyframes list must not be empty")
		return nil, nil -- unreachable: Errors.invalidKeyframesList always raises
	end

	for index, keyframe in rawKeyframes do
		validateKeyframePosition(keyframe.position, index)
	end

	local sorted: { Types.Keyframe } = table.clone(rawKeyframes)
	table.sort(sorted, function(a, b)
		return a.position < b.position
	end)

	for i = 2, #sorted do
		if sorted[i].position == sorted[i - 1].position then
			Errors.invalidKeyframesList(
				string.format(
					"two or more Keyframes share the fractional position %s",
					tostring(sorted[i].position)
				)
			)
			return nil, nil -- unreachable: Errors.invalidKeyframesList always raises
		end
	end

	local eases: { Types.Easing_Function } = {}
	for i, keyframe in sorted do
		eases[i] = Easing.resolve(keyframe.ease)
	end

	return sorted, eases
end

local function buildKeyframeWaypoints(keyframes: { Types.Keyframe }?): { KeyframeWaypoint }?
	if keyframes == nil then
		return nil
	end

	local waypoints: { KeyframeWaypoint } = {}

	if keyframes[1].position > 0 then
		table.insert(waypoints, { position = 0, keyframeIndex = nil })
	end

	for i in keyframes do
		table.insert(waypoints, { position = keyframes[i].position, keyframeIndex = i })
	end

	if keyframes[#keyframes].position < 1 then
		table.insert(waypoints, { position = 1, keyframeIndex = nil })
	end

	return waypoints
end

function Tween.new(
	targets: { Types.Target },
	mode: Mode,
	plansPerTarget: { { Types.PropertyPlan } },
	config: Types.Tween_Config
): Types.Tween
	local iterationDuration = resolveDuration(config)
	local ease = Easing.resolve(config.ease)

	local delay = resolveDelayField(config, "delay")
	local repeatCount = resolveRepeat(config)
	local repeatDelay = resolveDelayField(config, "repeatDelay")
	local yoyo = resolveYoyo(config)
	local stagger = resolveStagger(config)
	local keyframes, keyframeEase = resolveKeyframes(config)
	local keyframeWaypoints = buildKeyframeWaypoints(keyframes)
	local perTweenDuration: number
	if repeatCount == -1 then
		perTweenDuration = math.huge
	else
		perTweenDuration = delay + iterationDuration * (repeatCount + 1) + repeatDelay * repeatCount
	end
	local n = #targets
	local duration = perTweenDuration + (n - 1) * stagger

	local base = Animation.new(duration)

	local resolved: { Types.PerTargetPlan } = {}
	local staggerOffset: { [Types.Target]: number } = {}
	for i, target in targets do
		local startOffset = (i - 1) * stagger
		table.insert(resolved, {
			target = target,
			startOffset = startOffset,
			plans = plansPerTarget[i],
			alive = true,
			captured = false,
		})
		staggerOffset[target] = startOffset
	end

	local self = base :: any
	self.targets = targets
	self.resolved = resolved
	self.config = config
	self.ease = ease
	self.keyframes = keyframes
	self.staggerOffset = staggerOffset
	self.mode = mode :: Mode
	self.iterationDuration = iterationDuration
	self.invIterationDuration = 1 / iterationDuration
	self.invCycleLength = 1 / (iterationDuration + repeatDelay)
	self.delay = delay
	self.repeatCount = repeatCount
	self.repeatDelay = repeatDelay
	self.yoyo = yoyo
	self.keyframeEase = keyframeEase
	self.keyframeWaypoints = keyframeWaypoints
	self.lastCompletedIterations = 0
	self.completeFired = false
	self.hasCallbacks = config.onStart ~= nil
		or config.onUpdate ~= nil
		or config.onComplete ~= nil
		or config.onRepeat ~= nil
	self.fullyCaptured = false
	self.needsIsolation = self.hasCallbacks

	return (setmetatable(self, Tween) :: any) :: Types.Tween
end

function Tween.to(target: TargetOrTargets?, propertyMap: Types.PropertyMap?, config: Types.Tween_Config?): Types.Tween
	if target == nil then
		Errors.nilTarget()
		return (nil :: any) :: Types.Tween -- unreachable: Errors.nilTarget always raises
	end

	if not hasAtLeastOneProperty(propertyMap) then
		Errors.emptyPropertyMap(propertyMap)
		return (nil :: any) :: Types.Tween -- unreachable: Errors.emptyPropertyMap always raises
	end

	local map = propertyMap :: Types.PropertyMap
	local targets = resolveTargetList(target)

	local plansPerTarget: { { Types.PropertyPlan } } = {}
	for i, singleTarget in targets do
		validatePropertiesExist(singleTarget, map)

		local plans: { Types.PropertyPlan } = {}
		for propertyName, destinationValue in map do
			table.insert(plans, {
				property = propertyName,
				startValue = nil, -- captured when the active phase begins (Req 2.2)
				endValue = destinationValue,
				valueType = typeof(destinationValue),
			})
		end
		plansPerTarget[i] = plans
	end

	return Tween.new(targets, "to", plansPerTarget, config or {})
end

function Tween.from(target: TargetOrTargets?, propertyMap: Types.PropertyMap?, config: Types.Tween_Config?): Types.Tween
	if target == nil then
		Errors.nilTarget()
		return (nil :: any) :: Types.Tween -- unreachable: Errors.nilTarget always raises
	end

	if not hasAtLeastOneProperty(propertyMap) then
		Errors.emptyPropertyMap(propertyMap)
		return (nil :: any) :: Types.Tween -- unreachable: Errors.emptyPropertyMap always raises
	end

	local map = propertyMap :: Types.PropertyMap
	local targets = resolveTargetList(target)

	local plansPerTarget: { { Types.PropertyPlan } } = {}
	for i, singleTarget in targets do
		validatePropertiesExist(singleTarget, map)

		local plans: { Types.PropertyPlan } = {}
		for propertyName, sourceValue in map do
			table.insert(plans, {
				property = propertyName,
				startValue = sourceValue,
				endValue = nil, -- captured when the active phase begins (Req 3.1)
				valueType = typeof(sourceValue),
			})
		end
		plansPerTarget[i] = plans
	end

	return Tween.new(targets, "from", plansPerTarget, config or {})
end

function Tween.fromTo(
	target: TargetOrTargets?,
	startPropertyMap: Types.PropertyMap?,
	endPropertyMap: Types.PropertyMap?,
	config: Types.Tween_Config?
): Types.Tween
	if target == nil then
		Errors.nilTarget()
		return (nil :: any) :: Types.Tween -- unreachable: Errors.nilTarget always raises
	end

	if not hasAtLeastOneProperty(startPropertyMap) then
		Errors.emptyPropertyMap(startPropertyMap)
		return (nil :: any) :: Types.Tween -- unreachable: Errors.emptyPropertyMap always raises
	end

	if not hasAtLeastOneProperty(endPropertyMap) then
		Errors.emptyPropertyMap(endPropertyMap)
		return (nil :: any) :: Types.Tween -- unreachable: Errors.emptyPropertyMap always raises
	end

	local startMap = startPropertyMap :: Types.PropertyMap
	local endMap = endPropertyMap :: Types.PropertyMap

	validateKeySets(startMap, endMap)

	local targets = resolveTargetList(target)

	local plansPerTarget: { { Types.PropertyPlan } } = {}
	for i, singleTarget in targets do
		validatePropertiesExist(singleTarget, startMap)
		validatePropertiesExist(singleTarget, endMap)

		local plans: { Types.PropertyPlan } = {}
		for propertyName, startValue in startMap do
			local endValue = resolveEndValue(endMap[propertyName], startValue, propertyName)
			table.insert(plans, {
				property = propertyName,
				startValue = startValue,
				endValue = endValue,
				valueType = typeof(startValue),
			})
		end
		plansPerTarget[i] = plans
	end

	return Tween.new(targets, "fromTo", plansPerTarget, config or {})
end

local function captureActivePhase(self: InternalTween): ()
	local mode = self.mode
	if mode == "fromTo" or self.fullyCaptured then
		return
	end

	local pending = false

	for _, targetPlan in self.resolved do
		if not targetPlan.alive or targetPlan.captured then
			continue
		end

		local elapsedForTarget = self.position - self.delay - targetPlan.startOffset
		if elapsedForTarget < 0 then
			pending = true
			continue
		end

		local target = targetPlan.target

		for _, plan in targetPlan.plans do
			if mode == "to" then
				plan.startValue = readProperty(target, plan.property)
				plan.endValue = resolveEndValue(plan.endValue, plan.startValue, plan.property)
				plan.valueType = typeof(plan.endValue)
			elseif mode == "from" then
				plan.endValue = readProperty(target, plan.property)
				writeProperty(target, plan.property, plan.startValue)
			end
		end

		targetPlan.captured = true
	end

	if not pending then
		self.fullyCaptured = true
	end
end

local function computeIterationState(self: InternalTween, elapsed: number): (number, number, number)
	local iterationDuration = self.iterationDuration
	local repeatDelay = self.repeatDelay
	local repeatCount = self.repeatCount
	local cycleLength = iterationDuration + repeatDelay
	local invIterationDuration = self.invIterationDuration
	local invCycleLength = self.invCycleLength

	if repeatCount == -1 then
		local cycleIndex = math.floor(elapsed * invCycleLength)
		local posInCycle = elapsed - cycleIndex * cycleLength
		if posInCycle <= iterationDuration then
			return cycleIndex, posInCycle * invIterationDuration, cycleIndex
		end
		return cycleIndex, 1, cycleIndex + 1
	end

	local totalIterations = repeatCount + 1
	local maxElapsed = iterationDuration * totalIterations + repeatDelay * (totalIterations - 1)

	if elapsed >= maxElapsed then
		return totalIterations - 1, 1, totalIterations
	end

	local cycleIndex = math.floor(elapsed * invCycleLength)
	local posInCycle = elapsed - cycleIndex * cycleLength
	if posInCycle <= iterationDuration then
		return cycleIndex, posInCycle * invIterationDuration, cycleIndex
	end
	return cycleIndex, 1, cycleIndex + 1
end

local function findKeyframeSegment(waypoints: { KeyframeWaypoint }, t: number): (number, number, number)
	local count = #waypoints

	for i = 1, count - 1 do
		local fromWaypoint = waypoints[i]
		local toWaypoint = waypoints[i + 1]

		if t <= toWaypoint.position or i == count - 1 then
			local span = toWaypoint.position - fromWaypoint.position
			local localFraction = (t - fromWaypoint.position) / span
			if localFraction < 0 then
				localFraction = 0
			elseif localFraction > 1 then
				localFraction = 1
			end
			return i, i + 1, localFraction
		end
	end

	return 1, 2, 0
end

local function segmentEase(self: InternalTween, toWaypoint: KeyframeWaypoint): Types.Easing_Function
	local index = toWaypoint.keyframeIndex
	if index ~= nil then
		return (self.keyframeEase :: { Types.Easing_Function })[index]
	end
	return self.ease
end

local function keyframeWaypointValue(waypoint: KeyframeWaypoint, plan: Types.PropertyPlan, keyframes: { Types.Keyframe }): any
	local index = waypoint.keyframeIndex
	if index ~= nil then
		return keyframes[index].values[plan.property]
	end
	if waypoint.position <= 0 then
		return plan.startValue
	end
	return plan.endValue
end

function Tween.restart(self: Types.Tween): Types.Animation
	if self.state == "killed" then
		return Animation.restart(self)
	end

	local internal = (self :: any) :: InternalTween
	internal.lastCompletedIterations = 0
	internal.completeFired = false

	for _, targetPlan in internal.resolved do
		targetPlan.captured = false
		for _, plan in targetPlan.plans do
			plan.lerp = nil
		end
	end
	internal.fullyCaptured = false

	return Animation.restart(self)
end

function Tween._advance(self: Types.Tween, dt: number): ()
	local internal = (self :: any) :: InternalTween
	dropDeadTargets(internal)
	Animation._advancePosition(self, dt)
	captureActivePhase(internal)
	if not self.started and self.position >= internal.delay then
		self.started = true

		local onStart = internal.config.onStart
		if onStart ~= nil then
			onStart(self)
		end
	end
	self:_render()
	if internal.hasCallbacks then
	local elapsed = self.position - internal.delay
	if elapsed >= 0 then
		local _, _, completedIterations = computeIterationState(internal, elapsed)

		if completedIterations > internal.lastCompletedIterations then
			local repeatCount = internal.repeatCount
			local finalIterationIndex: number? = if repeatCount == -1 then nil else repeatCount
			for justCompletedIndex = internal.lastCompletedIterations, completedIterations - 1 do
				if finalIterationIndex ~= nil and justCompletedIndex == finalIterationIndex then
					if not internal.completeFired then
						internal.completeFired = true
						local onComplete = internal.config.onComplete
						if onComplete ~= nil then
							onComplete(self)
						end
					end
				else
					local onRepeat = internal.config.onRepeat
					if onRepeat ~= nil then
						onRepeat(self, justCompletedIndex)
					end
				end
			end

			internal.lastCompletedIterations = completedIterations
		end
	end
	end
	if internal.repeatCount ~= -1 and self.state == "playing" then
		if internal.hasCallbacks then
			if internal.completeFired then
				Animation._complete(self)
			end
		elseif self.position >= self.duration then
			Animation._complete(self)
		end
	end
end

function Tween._render(self: Types.Tween): ()
	local internal = (self :: any) :: InternalTween
	local waypoints = internal.keyframeWaypoints
	local anyRendered = false
	local firstEffectiveT: number? = nil

	for _, targetPlan in self.resolved do
		if not targetPlan.alive then
			continue
		end
		local elapsed = self.position - internal.delay - targetPlan.startOffset

		if elapsed < 0 then
			continue
		end

		local iterationIndex, localFraction = computeIterationState(internal, elapsed)

		local effectiveT = localFraction
		if internal.yoyo and iterationIndex % 2 == 1 then
			effectiveT = 1 - localFraction
		end

		if firstEffectiveT == nil then
			firstEffectiveT = effectiveT
		end
		anyRendered = true

		local target = targetPlan.target

		if waypoints == nil then
			local easedProgress = self.ease(effectiveT)

			for _, plan in targetPlan.plans do
				local lerp = plan.lerp
				if lerp == nil then
					if plan.startValue == nil or plan.endValue == nil then
						continue
					end
					lerp = Interpolator.buildLerp(plan.startValue, plan.endValue, plan.property)
					plan.lerp = lerp
				end
				writeProperty(target, plan.property, lerp(easedProgress))
			end
		else
			local fromIndex, toIndex, segmentFraction = findKeyframeSegment(waypoints, effectiveT)
			local fromWaypoint = waypoints[fromIndex]
			local toWaypoint = waypoints[toIndex]
			local easedProgress = segmentEase(internal, toWaypoint)(segmentFraction)
			local keyframes = internal.keyframes :: { Types.Keyframe }

			for _, plan in targetPlan.plans do
				if plan.startValue == nil or plan.endValue == nil then
					continue
				end

				local segmentStart = keyframeWaypointValue(fromWaypoint, plan, keyframes)
				local segmentEnd = keyframeWaypointValue(toWaypoint, plan, keyframes)
				if segmentStart == nil or segmentEnd == nil then
					continue
				end

				local value = Interpolator.interpolate(segmentStart, segmentEnd, easedProgress, plan.property)
				writeProperty(target, plan.property, value)
			end
		end
	end

	if anyRendered then
		local onUpdate = internal.config.onUpdate
		if onUpdate ~= nil then
			onUpdate(self, firstEffectiveT :: number)
		end
	end
end

function Tween.kill(self: Types.Tween): ()
	if self.state == "killed" then
		return
	end

	Animation.kill(self)
	releaseTargets((self :: any) :: InternalTween)
end

return Tween
