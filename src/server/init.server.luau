--!nonstrict
-- RoMotion vs TweenService -- SERVER-side bench.
--
-- Many games drive animation from the server. This script animates real,
-- server-owned Parts (which replicate to every client) so you can observe the
-- network + memory cost of server-side animation, and compare it against
-- client-local RoMotion (which the client bench runs with ~zero replication).
--
-- Server-owned parts change on the server, so their property updates replicate
-- to clients every network frame -- watch the client's "Net Recv Kbps" climb
-- during any server scenario, regardless of engine. This is exactly the
-- traffic that client-local RoMotion avoids.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Stats = game:GetService("Stats")

local RoMotion = require(ReplicatedStorage.Shared.RoMotion)

-- ---------------------------------------------------------------------------
-- Config (kept in sync with the client's SERVER_OFFSET_X / SPACING / sizes)
-- ---------------------------------------------------------------------------
local SPACING = 8
local PART_SIZE = 5
local MOVE_UP = 14
local OFFSET_X = 400
local HOME_COLOR = Color3.fromRGB(90, 220, 130)
local TARGET_COLOR = Color3.fromRGB(255, 90, 120)

local STYLE = {
	Linear = Enum.EasingStyle.Linear,
	Quad = Enum.EasingStyle.Quad,
	Sine = Enum.EasingStyle.Sine,
	Cubic = Enum.EasingStyle.Cubic,
	Back = Enum.EasingStyle.Back,
}
local DIR = {
	In = Enum.EasingDirection.In,
	Out = Enum.EasingDirection.Out,
	InOut = Enum.EasingDirection.InOut,
}
local function makeTweenInfo(duration, styleName, dirName, repeatCount, reverses)
	return TweenInfo.new(
		duration,
		STYLE[styleName] or Enum.EasingStyle.Quad,
		DIR[dirName] or Enum.EasingDirection.InOut,
		repeatCount or 0,
		reverses or false,
		0
	)
end

-- ---------------------------------------------------------------------------
-- Remote (client triggers scenarios; server pushes stats back)
-- ---------------------------------------------------------------------------
local remote = ReplicatedStorage:FindFirstChild("RoMotionBenchRemote")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "RoMotionBenchRemote"
	remote.Parent = ReplicatedStorage
end

-- ---------------------------------------------------------------------------
-- Server parts grid
-- ---------------------------------------------------------------------------
type Home = { cf: CFrame, size: Vector3, color: Color3 }

local folder: Folder? = nil
local parts: { BasePart } = {}
local home: { [BasePart]: Home } = {}

local activeRoMotion: { any } = {}
local activeTweens: { Tween } = {}
local activeGlobalHandles: { any } = {}

local function trackR(a)
	table.insert(activeRoMotion, a)
	return a
end
local function trackT(t: Tween): Tween
	table.insert(activeTweens, t)
	return t
end

local function clearActive()
	for _, a in activeRoMotion do
		pcall(function() a:kill() end)
	end
	table.clear(activeRoMotion)
	for _, t in activeTweens do
		pcall(function() t:Cancel() end)
	end
	table.clear(activeTweens)
	-- Stop any global (networked) tweens too (tells all clients to kill their
	-- local copies).
	for _, h in activeGlobalHandles do
		pcall(function() h:Stop() end)
	end
	table.clear(activeGlobalHandles)
end

local function restoreParts()
	for _, p in parts do
		local h = home[p]
		if h then
			p.CFrame = h.cf
			p.Size = h.size
			p.Color = h.color
			p.Transparency = 0
			p.Reflectance = 0
		end
	end
end

local function buildParts(count: number)
	if folder then
		folder:Destroy()
	end
	table.clear(parts)
	table.clear(home)

	local f = Instance.new("Folder")
	f.Name = "RoMotionBenchServerParts"
	f.Parent = Workspace
	folder = f

	local cols = math.ceil(math.sqrt(count))
	local rows = math.ceil(count / cols)
	local originX = OFFSET_X - (cols - 1) * SPACING / 2
	local originZ = -(rows - 1) * SPACING / 2

	for i = 1, count do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Size = Vector3.new(PART_SIZE, PART_SIZE, PART_SIZE)
		p.Color = HOME_COLOR
		p.CFrame = CFrame.new(originX + col * SPACING, 20, originZ + row * SPACING)
		p.Parent = f
		table.insert(parts, p)
		home[p] = { cf = p.CFrame, size = p.Size, color = p.Color }
	end
end

-- ---------------------------------------------------------------------------
-- Target helpers
-- ---------------------------------------------------------------------------
local function upPos(p: BasePart): Vector3
	return home[p].cf.Position + Vector3.new(0, MOVE_UP, 0)
end
local function moveCF(p: BasePart): CFrame
	return home[p].cf * CFrame.new(0, MOVE_UP, 0) * CFrame.Angles(0, math.rad(180), math.rad(45))
end
local function bigSize(p: BasePart): Vector3
	return home[p].size * 1.8
end

local function staggerStep(): number
	return math.clamp(2 / math.max(#parts, 1), 0.004, 0.05)
end

-- ---------------------------------------------------------------------------
-- Scenarios. "Position"/"CFrame"/"Combined"/"InfiniteYoyo" are engine-aware;
-- "Stagger"/"Timeline"/"Keyframes" are RoMotion-only.
-- ---------------------------------------------------------------------------
local function runCommon(engine, propsFn, duration, styleName, dirName, repeatN, yoyo)
	if engine == "RoMotion" then
		for _, p in parts do
			local cfg = { duration = duration, ease = styleName .. "." .. dirName }
			if yoyo then cfg.yoyo = true end
			if repeatN then cfg["repeat"] = repeatN end
			trackR(RoMotion.to(p, propsFn(p), cfg):play())
		end
	else
		local info = makeTweenInfo(duration, styleName, dirName, repeatN, yoyo)
		for _, p in parts do
			trackT(TweenService:Create(p, info, propsFn(p))):Play()
		end
	end
end

local scenarios: { [string]: (engine: string) -> () } = {
	Position = function(engine)
		runCommon(engine, function(p) return { Position = upPos(p) } end, 1.2, "Quad", "InOut")
	end,
	CFrame = function(engine)
		runCommon(engine, function(p) return { CFrame = moveCF(p) } end, 1.5, "Cubic", "InOut")
	end,
	Combined = function(engine)
		runCommon(engine, function(p)
			return { CFrame = moveCF(p), Color = TARGET_COLOR, Size = bigSize(p), Transparency = 0.4 }
		end, 1.5, "Back", "InOut")
	end,
	InfiniteYoyo = function(engine)
		runCommon(engine, function(p) return { CFrame = moveCF(p) } end, 1.0, "Sine", "InOut", -1, true)
	end,
	-- Heavy 5-property continuous stress (same as the client's COMPLEX test),
	-- so the server-side CPU/memory gap between the two engines is obvious.
	Complex = function(engine)
		runCommon(engine, function(p)
			local h = home[p]
			return {
				CFrame = h.cf * CFrame.new(0, MOVE_UP, 0) * CFrame.Angles(math.rad(180), math.rad(180), math.rad(90)),
				Size = h.size * 2,
				Color = TARGET_COLOR,
				Transparency = 0.5,
				Reflectance = 0.85,
			}
		end, 1.2, "Back", "InOut", -1, true)
	end,

	-- RoMotion-only (ignore requested engine; always RoMotion)
	Stagger = function()
		trackR(RoMotion.to(parts :: any, { Orientation = Vector3.new(0, 180, 0) }, {
			duration = 0.6,
			ease = "Quad.Out",
			stagger = staggerStep(),
		}):play())
	end,
	Timeline = function()
		local tl = RoMotion.timeline()
		for i, p in parts do
			tl:add(RoMotion.to(p, { Position = upPos(p) }, { duration = 0.5, yoyo = true, ["repeat"] = 1, ease = "Sine.InOut" }), i == 1 and 0 or "-=0.48")
		end
		trackR(tl)
		tl:play()
	end,
	Keyframes = function()
		for _, p in parts do
			local cf = home[p].cf
			trackR(RoMotion.to(p, { CFrame = cf }, {
				duration = 1.8,
				keyframes = {
					{ position = 0.4, values = { CFrame = cf * CFrame.new(0, MOVE_UP, 0) }, ease = "Sine.Out" },
					{ position = 0.7, values = { CFrame = cf * CFrame.new(MOVE_UP, MOVE_UP, 0) * CFrame.Angles(0, math.rad(180), 0) }, ease = "Sine.InOut" },
				},
			}):play())
		end
	end,

	-- NETWORKED global tween: the server broadcasts ONE packet (all targets,
	-- uniform Orientation goal) and every client renders it locally. Watch
	-- the server "send Kbps" stay tiny vs. the InfiniteYoyo scenario, which
	-- replicates every part's CFrame every frame.
	Global = function()
		local handle = RoMotion.global.to(parts, { Orientation = Vector3.new(0, 180, 0) }, {
			duration = 1.0,
			ease = "Sine.InOut",
			yoyo = true,
			["repeat"] = -1,
		})
		table.insert(activeGlobalHandles, handle)
	end,
}

-- ---------------------------------------------------------------------------
-- Remote handling
-- ---------------------------------------------------------------------------
-- Runs a scenario DIRECTLY on the server. The animation never travels over
-- the network -- the server computes every frame and sets the part
-- properties itself, which then replicate to clients exactly like any
-- server-authored TweenService tween. Nothing is relayed to a client to run.
local function startScenario(engineName: string, scenarioName: string, count: any)
	clearActive()
	restoreParts()

	local n = math.clamp(math.floor(tonumber(count) or 500), 1, 5000)
	if #parts ~= n then
		buildParts(n)
	end

	local sc = scenarios[scenarioName]
	if sc then
		sc(engineName == "TweenService" and "TweenService" or "RoMotion")
	end
end

local function stopScenario()
	clearActive()
	restoreParts()
end

-- (A) Control channel for the client bench GUI. This carries ONLY a
-- start/stop signal plus parameters -- it is a one-shot trigger, not a
-- per-frame relay. Kicking off a server tween from an event like this is
-- exactly how real games start server-side animation.
remote.OnServerEvent:Connect(function(_player, msg)
	if type(msg) ~= "table" then
		return
	end
	if msg.action == "start" then
		startScenario(msg.engine, msg.scenario, msg.count)
	elseif msg.action == "stop" then
		stopScenario()
	end
end)

-- (B) PURE server-side control via Attributes on this Script -- ZERO client
-- involvement. In Studio, select this Script (ServerScriptService > Server)
-- and edit its Attributes: set `Scenario` / `Engine` / `Count`, then toggle
-- `Run` on. The server runs the tween directly and you can read server CPU /
-- memory / outgoing Kbps in the Developer Console. This is the "developers
-- just use tween on the server" path, provable without any client.
script:SetAttribute("Scenario", script:GetAttribute("Scenario") or "InfiniteYoyo")
script:SetAttribute("Engine", script:GetAttribute("Engine") or "RoMotion")
script:SetAttribute("Count", script:GetAttribute("Count") or 500)
script:SetAttribute("Run", false)

script:GetAttributeChangedSignal("Run"):Connect(function()
	if script:GetAttribute("Run") then
		startScenario(script:GetAttribute("Engine"), script:GetAttribute("Scenario"), script:GetAttribute("Count"))
	else
		stopScenario()
	end
end)

-- ---------------------------------------------------------------------------
-- Server stats are printed to the SERVER console ONLY -- no network is sent
-- from here. This deliberately avoids any server<->client stats traffic so
-- the only network you observe during a run is the actual part replication
-- the animation causes. Read these in-game via F9 > Server too.
-- ---------------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(2)
		print(string.format(
			"[RoMotionBench-Server] mem=%.0f MB  send=%.1f Kbps  parts=%d",
			Stats:GetTotalMemoryUsageMb(),
			Stats.DataSendKbps,
			#parts
		))
	end
end)

-- Build an initial grid so the server parts exist and replicate immediately.
buildParts(500)

print("[RoMotionBench-Server] ready -- server-side scenarios available via the client panel's 'Server execution' section.")
