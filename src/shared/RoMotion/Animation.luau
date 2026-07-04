--!strict
--!optimize 2
--!native

local Types = require(script.Parent.Types)
local Scheduler = require(script.Parent.Scheduler)

type Animation = Types.Animation
type PlaybackState = Types.PlaybackState
type Direction = Types.Direction

local Animation = {}
Animation.__index = Animation

function Animation.new(duration: number): Animation
	local self = {
		position = 0,
		duration = duration,
		direction = 1,
		timeScale = 1,
		state = "idle",
		started = false,
		needsIsolation = true,
	}

	return (setmetatable(self, Animation) :: any) :: Animation
end

function Animation.play(self: Animation): Animation
	if self.state == "killed" then
		return self
	end

	self.direction = 1
	self.state = "playing"
	Scheduler.add(Scheduler, self)

	return self
end

function Animation.pause(self: Animation): Animation
	if self.state == "killed" then
		return self
	end

	self.state = "paused"

	return self
end

function Animation.resume(self: Animation): Animation
	if self.state == "killed" then
		return self
	end

	self.state = "playing"
	Scheduler.add(Scheduler, self)

	return self
end

function Animation.restart(self: Animation): Animation
	if self.state == "killed" then
		return self
	end

	self.position = 0
	self.direction = 1
	self.started = false
	self.state = "playing"
	Scheduler.add(Scheduler, self)

	return self
end

function Animation.reverse(self: Animation): Animation
	if self.state == "killed" then
		return self
	end

	self.direction = -1
	self.state = "playing"
	Scheduler.add(Scheduler, self)

	return self
end

function Animation.seek(self: Animation, seconds: number): Animation
	if self.state == "killed" then
		return self
	end

	self.position = math.clamp(seconds, 0, self.duration)
	self:_render()

	return self
end

function Animation.progress(self: Animation, fraction: number?): number | Animation
	if fraction == nil then
		if self.duration == 0 then
			return 0
		end
		return self.position / self.duration
	end

	if self.state == "killed" then
		return self
	end

	local clamped = math.clamp(fraction, 0, 1)
	self.position = clamped * self.duration
	self:_render()

	return self
end

function Animation.setTimeScale(self: Animation, scale: number): Animation
	if self.state == "killed" then
		return self
	end

	self.timeScale = scale

	return self
end

function Animation.kill(self: Animation): ()
	if self.state == "killed" then
		return
	end

	self.state = "killed"
	Scheduler.remove(Scheduler, self)
end

function Animation._advancePosition(self: Animation, dt: number): ()
	if self.state ~= "playing" then
		return
	end

	local delta = dt * self.direction * self.timeScale
	local newPosition = self.position + delta

	if self.direction == -1 and newPosition <= 0 then
		self.position = 0
		self.state = "paused"
	else
		self.position = newPosition
	end
end

function Animation._complete(self: Animation): ()
	if self.state == "killed" then
		return
	end

	self.state = "completed"
	Scheduler.remove(Scheduler, self)
end

function Animation._advance(self: Animation, dt: number): ()
	Animation._advancePosition(self, dt)
	self:_render()
end

function Animation._render(self: Animation): ()
	-- no-op: nothing to render at the base Animation level.
end

return Animation
