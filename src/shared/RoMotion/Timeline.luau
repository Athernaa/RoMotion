--!strict
local Types = require(script.Parent.Types)
local Animation = require(script.Parent.Animation)
local Errors = require(script.Parent.Errors)
local RelativeValue = require(script.Parent.RelativeValue)
local Timeline = setmetatable({}, { __index = Animation })
Timeline.__index = Timeline

local MAX_LABEL_LENGTH = 256
type ChildEntry = { anim: Types.Animation, startTime: number }

local function isAnimationLike(value: any): boolean
	if typeof(value) ~= "table" then
		return false
	end

	return typeof(value.play) == "function"
		and typeof(value.pause) == "function"
		and typeof(value.resume) == "function"
		and typeof(value.restart) == "function"
		and typeof(value.reverse) == "function"
		and typeof(value.seek) == "function"
		and typeof(value.progress) == "function"
		and typeof(value.setTimeScale) == "function"
		and typeof(value.kill) == "function"
		and typeof(value._advance) == "function"
		and typeof(value._render) == "function"
end

local function isTimeline(value: any): boolean
	return getmetatable(value) == Timeline
end

local function subtreeContains(node: Types.Animation, target: Types.Animation): boolean
	if node == target then
		return true
	end

	if isTimeline(node) then
		for _, entry in (node :: Types.Timeline).children do
			if subtreeContains(entry.anim, target) then
				return true
			end
		end
	end

	return false
end

local function recomputeDuration(self: Types.Timeline): ()
	local maxEnd = 0

	for _, entry in self.children do
		local endTime = entry.startTime + entry.anim.duration
		if endTime > maxEnd then
			maxEnd = endTime
		end
	end

	(self :: any).duration = maxEnd
end

local function isRelativePositionString(s: string): boolean
	return s:match("^%s*[%+%-]=") ~= nil
end

local function resolveStartTime(self: Types.Timeline, position: Types.Position_Parameter?): number
	if position == nil then
		return self.duration
	end

	if typeof(position) == "number" then
		if position < 0 then
			Errors.invalidPositionParameter(position)
		end
		return position
	end

	if typeof(position) == "string" then
		local lastChild = self.children[#self.children]

		if position == "<" then
			if lastChild == nil then
				return 0
			end
			return lastChild.startTime
		elseif position == ">" then
			if lastChild == nil then
				return 0
			end
			return lastChild.startTime + lastChild.anim.duration
		elseif isRelativePositionString(position) then
			local parsed = RelativeValue.parse(position)
			local currentEnd = self.duration
			local resolved = if parsed.op == "+" then currentEnd + parsed.amount else currentEnd - parsed.amount
			return math.max(0, resolved)
		else
			local labelTime = self.labels[position]
			if labelTime == nil then
				Errors.unknownLabel(position)
			end
			return labelTime
		end
	end

	Errors.invalidPositionParameter(position)
	return 0 -- unreachable: Errors.invalidPositionParameter always raises
end

function Timeline.new(): Types.Timeline
	local base = Animation.new(0)

	local self = base :: any
	self.children = {} :: { ChildEntry }
	self.labels = {} :: { [string]: number }

	return (setmetatable(self, Timeline) :: any) :: Types.Timeline
end

function Timeline.add(self: Types.Timeline, child: Types.Animation, position: Types.Position_Parameter?): Types.Timeline
	if not isAnimationLike(child) then
		Errors.invalidTimelineChild(child)
		return self
	end

	if isTimeline(child) and subtreeContains(child, self) then
		Errors.cyclicNesting(child)
		return self
	end

	local startTime = resolveStartTime(self, position)

	table.insert(self.children, { anim = child, startTime = startTime })
	recomputeDuration(self)

	return self
end

function Timeline.addLabel(self: Types.Timeline, name: string, time: number): Types.Timeline
	if typeof(name) ~= "string" or #name < 1 or #name > MAX_LABEL_LENGTH then
		error(
			string.format(
				"RoMotion: invalid Label name -- name must be a string of 1 to %d characters",
				MAX_LABEL_LENGTH
			),
			2
		)
	end

	if typeof(time) ~= "number" or time < 0 then
		error("RoMotion: invalid Label time -- time must be a number greater than or equal to 0", 2)
	end

	self.labels[name] = time

	return self
end

function Timeline._render(self: Types.Timeline): ()
	for _, entry in self.children do
		local anim = entry.anim

		if anim.state == "killed" then
			continue
		end

		local childLocalTime = self.position - entry.startTime

		if childLocalTime < 0 then
			continue
		end
		anim.position = math.min(childLocalTime, anim.duration)
		anim:_advance(0)
	end
end

function Timeline.setTimeScale(self: Types.Timeline, scale: number): Types.Animation
	if self.state == "killed" then
		return self
	end

	if typeof(scale) ~= "number" or scale <= 0 then
		Errors.invalidTimeScale(scale)
		return self -- unreachable: Errors.invalidTimeScale always raises
	end

	(self :: any).timeScale = scale

	for _, entry in self.children do
		entry.anim:setTimeScale(scale)
	end

	return self
end

function Timeline.kill(self: Types.Timeline): ()
	if self.state == "killed" then
		return
	end

	Animation.kill(self)
	self.children = {}
	self.labels = {}
end

return Timeline
