--!nonstrict
-- RoMotion vs TweenService -- WORLD (3D part) performance & feature bench.
--
-- Animates real Workspace Parts (not UI), because that is where animation
-- cost is actually measurable. You pick ONE engine at a time (RoMotion OR
-- TweenService) and run a scenario on ALL parts; the live FPS / average FPS
-- / min-FPS readout then tells you the true per-engine cost. Run the same
-- scenario under each engine separately and compare the numbers.
--
-- Coverage:
--   * "Common" scenarios exercise everything BOTH engines can do (property
--     types, delay, repeat, yoyo, infinite repeat, easing) and are
--     engine-aware -- they run under whichever engine is selected.
--   * "RoMotion only" scenarios exercise features TweenService does not have
--     (from/fromTo, relative values, keyframes, stagger, timelines, labels &
--     position parameters, nested timelines, timeScale, custom easing,
--     lifecycle callbacks, seek/progress/reverse control).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Stats = game:GetService("Stats")

local RoMotion = require(ReplicatedStorage.Shared.RoMotion)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---------------------------------------------------------------------------
-- Config
-- ---------------------------------------------------------------------------
local PART_COUNT = 1000
local SPACING = 8
local MOVE_UP = 14
local PART_SIZE = 5
local SERVER_OFFSET_X = 400 -- server grid sits this far along +X from the client grid

-- Server bench remote (created by the server bench script). Used to trigger
-- server-side scenarios and to receive server memory / send-rate stats.
local remote = ReplicatedStorage:WaitForChild("RoMotionBenchRemote", 10) :: RemoteEvent?
local serverEngine = "RoMotion"

-- Fires a ONE-SHOT control signal to the server (start/stop + params). There
-- is deliberately NO per-frame client->server traffic anywhere in this
-- script -- the server computes the whole animation itself. You can verify
-- this by watching "Net Send" in the metrics bar stay ~0 during a server run.
local function fireServer(action: string, scenario: string?)
	if remote then
		remote:FireServer({ action = action, engine = serverEngine, scenario = scenario, count = PART_COUNT })
	end
end

local HOME_COLOR = Color3.fromRGB(80, 150, 255)
local TARGET_COLOR = Color3.fromRGB(255, 130, 70)

local COLOR_TEXT = Color3.fromRGB(235, 238, 245)
local COLOR_BTN = Color3.fromRGB(46, 50, 62)
local COLOR_BTN_HOVER = Color3.fromRGB(66, 72, 90)
local ACCENT_R = Color3.fromRGB(46, 108, 224)
local ACCENT_T = Color3.fromRGB(150, 120, 60)

-- currently selected engine for the "common" scenarios
local engine = "RoMotion" -- or "TweenService"

-- ---------------------------------------------------------------------------
-- Easing translation (RoMotion "Style.Direction" <-> Enum pair)
-- ---------------------------------------------------------------------------
local STYLE = {
	Linear = Enum.EasingStyle.Linear,
	Quad = Enum.EasingStyle.Quad,
	Cubic = Enum.EasingStyle.Cubic,
	Quart = Enum.EasingStyle.Quart,
	Quint = Enum.EasingStyle.Quint,
	Sine = Enum.EasingStyle.Sine,
	Expo = Enum.EasingStyle.Exponential,
	Circ = Enum.EasingStyle.Circular,
	Back = Enum.EasingStyle.Back,
	Elastic = Enum.EasingStyle.Elastic,
	Bounce = Enum.EasingStyle.Bounce,
}
local DIR = { In = Enum.EasingDirection.In, Out = Enum.EasingDirection.Out, InOut = Enum.EasingDirection.InOut }

local function parseEase(ease: string)
	local s, d = string.match(ease, "^(%a+)%.(%a+)$")
	if not s then
		s, d = ease, "InOut"
	end
	return STYLE[s] or Enum.EasingStyle.Quad, DIR[d] or Enum.EasingDirection.InOut
end

local function makeTweenInfo(duration, ease, repeatCount, reverses, delayTime)
	local st, di = parseEase(ease)
	return TweenInfo.new(duration, st, di, repeatCount or 0, reverses or false, delayTime or 0)
end

-- ---------------------------------------------------------------------------
-- World: parts grid + framing camera
-- ---------------------------------------------------------------------------
type Home = { cf: CFrame, size: Vector3, color: Color3 }

local partsFolder: Folder? = nil
local parts: { BasePart } = {}
local home: { [BasePart]: Home } = {}
local gridCenter = Vector3.zero

local function frameCameraAt(center: Vector3, count: number)
	local cols = math.ceil(math.sqrt(count))
	local rows = math.ceil(count / cols)
	local span = math.max(cols, rows) * SPACING
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Scriptable
		local camPos = center + Vector3.new(0, span * 0.55, span * 1.2)
		cam.CFrame = CFrame.lookAt(camPos, center)
		cam.FieldOfView = 70
	end
end

local function buildParts()
	if partsFolder then
		partsFolder:Destroy()
	end
	table.clear(parts)
	table.clear(home)

	local folder = Instance.new("Folder")
	folder.Name = "RoMotionBenchParts"
	folder.Parent = Workspace
	partsFolder = folder

	local cols = math.ceil(math.sqrt(PART_COUNT))
	local rows = math.ceil(PART_COUNT / cols)
	local originX = -(cols - 1) * SPACING / 2
	local originZ = -(rows - 1) * SPACING / 2
	gridCenter = Vector3.new(0, 20, 0)

	for i = 1, PART_COUNT do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		local pos = Vector3.new(originX + col * SPACING, 20, originZ + row * SPACING)

		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Size = Vector3.new(PART_SIZE, PART_SIZE, PART_SIZE)
		p.Color = HOME_COLOR
		p.CFrame = CFrame.new(pos)
		p.Parent = folder

		table.insert(parts, p)
		home[p] = { cf = p.CFrame, size = p.Size, color = p.Color }
	end

	frameCameraAt(gridCenter, PART_COUNT)
end

local function restorePart(p: BasePart)
	local h = home[p]
	if not h then
		return
	end
	p.CFrame = h.cf
	p.Size = h.size
	p.Color = h.color
	p.Transparency = 0
	p.Reflectance = 0
end

-- ---------------------------------------------------------------------------
-- Active-work tracking + metrics
-- ---------------------------------------------------------------------------
local activeRoMotion: { any } = {}
local activeTweens: { Tween } = {}
local pendingThreads: { thread } = {}

-- callback counters (for the lifecycle-callback demo)
local cbStart, cbUpdate, cbComplete, cbRepeat = 0, 0, 0, 0

local function trackR(a)
	table.insert(activeRoMotion, a)
	return a
end
local function trackT(t: Tween): Tween
	table.insert(activeTweens, t)
	return t
end

local function cancelAll()
	for _, a in activeRoMotion do
		pcall(function() a:kill() end)
	end
	table.clear(activeRoMotion)
	for _, t in activeTweens do
		pcall(function() t:Cancel() end)
	end
	table.clear(activeTweens)
	for _, th in pendingThreads do
		pcall(task.cancel, th)
	end
	table.clear(pendingThreads)
end

local function resetAll()
	cancelAll()
	for _, p in parts do
		restorePart(p)
	end
end

-- metrics window (reset when a scenario starts)
local mStart = 0
local mFrames = 0
local mMinFps = math.huge
local mScenario = "(idle)"
local mEngineUsed = ""

local function startMetrics(scenarioName: string, engineUsed: string)
	mStart = os.clock()
	mFrames = 0
	mMinFps = math.huge
	mScenario = scenarioName
	mEngineUsed = engineUsed
end

-- ---------------------------------------------------------------------------
-- Target helpers (identical values per part regardless of engine)
-- ---------------------------------------------------------------------------
local function upPosition(p: BasePart): Vector3
	return home[p].cf.Position + Vector3.new(0, MOVE_UP, 0)
end
local function moveCFrame(p: BasePart): CFrame
	return home[p].cf * CFrame.new(0, MOVE_UP, 0) * CFrame.Angles(0, math.rad(180), math.rad(45))
end
local function bigSize(p: BasePart): Vector3
	return home[p].size * 1.8
end

-- ---------------------------------------------------------------------------
-- Common scenarios: run under the SELECTED engine only (engine-aware)
-- ---------------------------------------------------------------------------
-- opts: { repeatN=, yoyo=, delay= }
local function runCommon(propsFn, duration, ease, opts)
	opts = opts or {}
	if engine == "RoMotion" then
		for _, p in parts do
			local cfg = { duration = duration, ease = ease }
			if opts.delay then cfg.delay = opts.delay end
			if opts.yoyo then cfg.yoyo = true end
			if opts.repeatN then cfg["repeat"] = opts.repeatN end
			trackR(RoMotion.to(p, propsFn(p), cfg):play())
		end
	else
		local info = makeTweenInfo(duration, ease, opts.repeatN, opts.yoyo, opts.delay)
		for _, p in parts do
			trackT(TweenService:Create(p, info, propsFn(p))):Play()
		end
	end
end

-- Assigns a different easing style to each part (engine-aware) so the whole
-- easing library is visible at once.
local EASE_STYLES = { "Linear", "Quad", "Cubic", "Quart", "Quint", "Sine", "Expo", "Circ", "Back", "Elastic", "Bounce" }
local function easeGallery()
	for i, p in parts do
		local e = EASE_STYLES[(i - 1) % #EASE_STYLES + 1] .. ".InOut"
		if engine == "RoMotion" then
			trackR(RoMotion.to(p, { Position = upPosition(p) }, { duration = 1.6, ease = e }):play())
		else
			trackT(TweenService:Create(p, makeTweenInfo(1.6, e), { Position = upPosition(p) })):Play()
		end
	end
end

local commonScenarios = {
	{ name = "Position", fn = function() runCommon(function(p) return { Position = upPosition(p) } end, 1.2, "Quad.InOut") end },
	{ name = "Position (side)", fn = function() runCommon(function(p) return { Position = home[p].cf.Position + Vector3.new(MOVE_UP, 0, 0) } end, 1.2, "Quad.InOut") end },
	{ name = "CFrame (move+rot)", fn = function() runCommon(function(p) return { CFrame = moveCFrame(p) } end, 1.5, "Cubic.InOut") end },
	{ name = "Size", fn = function() runCommon(function(p) return { Size = bigSize(p) } end, 1.0, "Back.Out") end },
	{ name = "Orientation spin", fn = function() runCommon(function() return { Orientation = Vector3.new(0, 180, 0) } end, 1.2, "Quad.InOut") end },
	{ name = "Color", fn = function() runCommon(function() return { Color = TARGET_COLOR } end, 1.0, "Sine.InOut") end },
	{ name = "Transparency", fn = function() runCommon(function() return { Transparency = 0.7 } end, 1.0, "Quad.Out") end },
	{ name = "Reflectance", fn = function() runCommon(function() return { Reflectance = 1 } end, 1.0, "Quad.Out") end },
	{ name = "Combined (4 props)", fn = function()
		runCommon(function(p)
			return { CFrame = moveCFrame(p), Color = TARGET_COLOR, Size = bigSize(p), Transparency = 0.4 }
		end, 1.5, "Back.InOut")
	end },
	{ name = "Delay 0.6s", fn = function() runCommon(function(p) return { Position = upPosition(p) } end, 1.0, "Quad.Out", { delay = 0.6 }) end },
	{ name = "Repeat x3", fn = function() runCommon(function(p) return { Position = upPosition(p) } end, 0.5, "Sine.InOut", { repeatN = 3 }) end },
	{ name = "Yoyo x3", fn = function() runCommon(function(p) return { Position = upPosition(p) } end, 0.5, "Sine.InOut", { repeatN = 3, yoyo = true }) end },
	{ name = "PERF: infinite yoyo", fn = function() runCommon(function(p) return { CFrame = moveCFrame(p) } end, 1.0, "Sine.InOut", { repeatN = -1, yoyo = true }) end },
	{ name = "Elastic", fn = function() runCommon(function(p) return { Position = upPosition(p) } end, 1.6, "Elastic.Out") end },
	{ name = "Bounce", fn = function() runCommon(function(p) return { Position = upPosition(p) } end, 1.6, "Bounce.Out") end },
	{ name = "Transform (pos+size+rot)", fn = function()
		runCommon(function(p) return { Position = upPosition(p), Size = bigSize(p), Orientation = Vector3.new(0, 180, 0) } end, 1.4, "Back.InOut")
	end },
	{ name = "Color + Fade", fn = function() runCommon(function() return { Color = TARGET_COLOR, Transparency = 0.6 } end, 1.0, "Sine.InOut") end },
	{ name = "Ease gallery (all)", fn = easeGallery },
	{ name = "Micro 0.15s (inf)", fn = function() runCommon(function(p) return { Position = upPosition(p) } end, 0.15, "Sine.InOut", { repeatN = -1, yoyo = true }) end },
	{ name = "Long 5s", fn = function() runCommon(function(p) return { CFrame = moveCFrame(p) } end, 5, "Linear") end },
	{ name = "Reflectance pulse (inf)", fn = function() runCommon(function() return { Reflectance = 1 } end, 0.8, "Sine.InOut", { repeatN = -1, yoyo = true }) end },
	{ name = "PERF: infinite spin", fn = function() runCommon(function() return { Orientation = Vector3.new(0, 180, 0) } end, 0.8, "Linear", { repeatN = -1, yoyo = true }) end },
	-- The definitive heavy stress test: every part continuously animates FIVE
	-- properties at once (CFrame move+rotate, Size, Color, Transparency,
	-- Reflectance) with a demanding easing, forever. Identical work for both
	-- engines, so the FPS / CPU difference here is the raw per-frame cost gap.
	{ name = "PERF: COMPLEX 5-prop (inf)", fn = function()
		runCommon(function(p)
			local h = home[p]
			return {
				CFrame = h.cf * CFrame.new(0, MOVE_UP, 0) * CFrame.Angles(math.rad(180), math.rad(180), math.rad(90)),
				Size = h.size * 2,
				Color = TARGET_COLOR,
				Transparency = 0.5,
				Reflectance = 0.85,
			}
		end, 1.2, "Back.InOut", { repeatN = -1, yoyo = true })
	end },
}

-- ---------------------------------------------------------------------------
-- RoMotion-only scenarios (features TweenService has no equivalent for)
-- ---------------------------------------------------------------------------
local function staggerStep(): number
	return math.clamp(2 / math.max(#parts, 1), 0.004, 0.05)
end

local function smoothstep(t: number): number
	return t * t * (3 - 2 * t)
end

local romotionScenarios = {
	{ name = "from (drop in)", fn = function()
		for _, p in parts do
			trackR(RoMotion.from(p, { Position = upPosition(p) }, { duration = 1.2, ease = "Bounce.Out" }):play())
		end
	end },

	{ name = "fromTo", fn = function()
		for _, p in parts do
			local base = home[p].cf.Position
			trackR(RoMotion.fromTo(p, { Position = base - Vector3.new(0, MOVE_UP, 0) }, { Position = base + Vector3.new(0, MOVE_UP, 0) }, { duration = 1.2, ease = "Cubic.InOut" }):play())
		end
	end },

	{ name = "Relative +=", fn = function()
		-- Relative values resolve against the value captured at play time.
		for _, p in parts do
			trackR(RoMotion.to(p, { Transparency = "+=0.6", Reflectance = "+=0.5" }, { duration = 1.0, ease = "Quad.Out" }):play())
		end
	end },

	{ name = "Keyframes (path)", fn = function()
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
	end },

	{ name = "Stagger (cascade)", fn = function()
		trackR(RoMotion.to(parts :: any, { Orientation = Vector3.new(0, 180, 0) }, {
			duration = 0.6,
			ease = "Quad.Out",
			stagger = staggerStep(),
		}):play())
	end },

	{ name = "Timeline (wave)", fn = function()
		local tl = RoMotion.timeline()
		for i, p in parts do
			local child = RoMotion.to(p, { Position = upPosition(p) }, { duration = 0.5, ease = "Sine.InOut", yoyo = true, ["repeat"] = 1 })
			tl:add(child, i == 1 and 0 or "-=0.48")
		end
		trackR(tl)
		tl:play()
	end },

	{ name = "Timeline labels+pos", fn = function()
		-- Exercises numeric, label, "<", ">" and "+=" position parameters.
		local tl = RoMotion.timeline()
		tl:addLabel("mid", 0.4)
		for i, p in parts do
			local pos: any
			if i == 1 then
				pos = 0
			elseif i % 4 == 0 then
				pos = "mid"
			elseif i % 4 == 1 then
				pos = "<"
			elseif i % 4 == 2 then
				pos = ">"
			else
				pos = "+=0.1"
			end
			tl:add(RoMotion.to(p, { Position = upPosition(p) }, { duration = 0.4, yoyo = true, ["repeat"] = 1 }), pos)
		end
		trackR(tl)
		tl:play()
	end },

	{ name = "Nested timeline", fn = function()
		local rootTl = RoMotion.timeline()
		local groups = 4
		local groupSize = math.max(1, math.floor(#parts / groups))
		for g = 0, groups - 1 do
			local sub = RoMotion.timeline()
			for k = 1, groupSize do
				local p = parts[g * groupSize + k]
				if p then
					sub:add(RoMotion.to(p, { Position = upPosition(p) }, { duration = 0.5, yoyo = true, ["repeat"] = 1 }), k == 1 and 0 or "-=0.46")
				end
			end
			rootTl:add(sub, g == 0 and 0 or "+=0.15")
		end
		trackR(rootTl)
		rootTl:play()
	end },

	{ name = "Custom easing", fn = function()
		for _, p in parts do
			trackR(RoMotion.to(p, { Position = upPosition(p) }, { duration = 1.2, ease = smoothstep }):play())
		end
	end },

	{ name = "Callbacks x4", fn = function()
		cbStart, cbUpdate, cbComplete, cbRepeat = 0, 0, 0, 0
		for _, p in parts do
			trackR(RoMotion.to(p, { Position = upPosition(p) }, {
				duration = 0.6,
				yoyo = true,
				["repeat"] = 4,
				onStart = function() cbStart += 1 end,
				onUpdate = function() cbUpdate += 1 end,
				onComplete = function() cbComplete += 1 end,
				onRepeat = function() cbRepeat += 1 end,
			}):play())
		end
	end },

	{ name = "Repeat + repeatDelay", fn = function()
		for _, p in parts do
			trackR(RoMotion.to(p, { Position = upPosition(p) }, {
				duration = 0.4,
				["repeat"] = 3,
				repeatDelay = 0.3,
				yoyo = true,
				ease = "Sine.InOut",
			}):play())
		end
	end },

	{ name = "from (color+fade)", fn = function()
		for _, p in parts do
			trackR(RoMotion.from(p, { Color = TARGET_COLOR, Transparency = 1 }, { duration = 1.2, ease = "Quad.Out" }):play())
		end
	end },

	{ name = "Stagger fade", fn = function()
		trackR(RoMotion.to(parts :: any, { Transparency = 0.7 }, { duration = 0.6, stagger = staggerStep() }):play())
	end },

	{ name = "Timeline @ 2x speed", fn = function()
		local tl = RoMotion.timeline()
		for i, p in parts do
			tl:add(RoMotion.to(p, { Position = upPosition(p) }, { duration = 0.5, yoyo = true, ["repeat"] = 1, ease = "Sine.InOut" }), i == 1 and 0 or "-=0.48")
		end
		tl:setTimeScale(2)
		trackR(tl)
		tl:play()
	end },

	{ name = "Infinite yoyo (control me)", fn = function()
		for _, p in parts do
			trackR(RoMotion.to(p, { CFrame = moveCFrame(p) }, { duration = 1.0, yoyo = true, ["repeat"] = -1, ease = "Sine.InOut" }):play())
		end
	end },
}

-- ---------------------------------------------------------------------------
-- UI: metrics bar + control panel
-- ---------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "RoMotionBench"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = playerGui

-- Metrics bar (top) ----------------------------------------------------------
local metricsBar = Instance.new("Frame")
metricsBar.Size = UDim2.new(1, 0, 0, 66)
metricsBar.BackgroundColor3 = Color3.fromRGB(10, 11, 15)
metricsBar.BackgroundTransparency = 0.1
metricsBar.BorderSizePixel = 0
metricsBar.Parent = gui

local mLine1 = Instance.new("TextLabel")
mLine1.BackgroundTransparency = 1
mLine1.Position = UDim2.new(0, 12, 0, 3)
mLine1.Size = UDim2.new(1, -24, 0, 20)
mLine1.Font = Enum.Font.GothamBold
mLine1.TextSize = 15
mLine1.TextColor3 = COLOR_TEXT
mLine1.TextXAlignment = Enum.TextXAlignment.Left
mLine1.Text = "FPS: --"
mLine1.Parent = metricsBar

local mLine2 = Instance.new("TextLabel")
mLine2.BackgroundTransparency = 1
mLine2.Position = UDim2.new(0, 12, 0, 23)
mLine2.Size = UDim2.new(1, -24, 0, 20)
mLine2.Font = Enum.Font.Gotham
mLine2.TextSize = 13
mLine2.TextColor3 = Color3.fromRGB(180, 186, 196)
mLine2.TextXAlignment = Enum.TextXAlignment.Left
mLine2.Text = ""
mLine2.Parent = metricsBar

local mLine3 = Instance.new("TextLabel")
mLine3.BackgroundTransparency = 1
mLine3.Position = UDim2.new(0, 12, 0, 43)
mLine3.Size = UDim2.new(1, -24, 0, 20)
mLine3.Font = Enum.Font.Gotham
mLine3.TextSize = 13
mLine3.TextColor3 = Color3.fromRGB(150, 220, 255)
mLine3.TextXAlignment = Enum.TextXAlignment.Left
mLine3.Text = ""
mLine3.Parent = metricsBar

-- Control panel (left) -------------------------------------------------------
local panel = Instance.new("ScrollingFrame")
panel.Position = UDim2.new(0, 8, 0, 74)
panel.Size = UDim2.new(0, 250, 1, -82)
panel.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel = 0
panel.ScrollBarThickness = 6
panel.CanvasSize = UDim2.new(0, 0, 0, 0)
panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
panel.Parent = gui

local pCorner = Instance.new("UICorner")
pCorner.CornerRadius = UDim.new(0, 8)
pCorner.Parent = panel

local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Vertical
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 4)
list.Parent = panel

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.PaddingLeft = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)
pad.Parent = panel

local orderN = 0
local function nextOrder(): number
	orderN += 1
	return orderN
end

local function addSection(titleText: string)
	local lbl = Instance.new("TextLabel")
	lbl.LayoutOrder = nextOrder()
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(1, 0, 0, 22)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 13
	lbl.TextColor3 = Color3.fromRGB(140, 150, 165)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = string.upper(titleText)
	lbl.Parent = panel
end

local function addButton(text: string, color: Color3?, onClick: () -> ()): TextButton
	local btn = Instance.new("TextButton")
	btn.LayoutOrder = nextOrder()
	btn.Size = UDim2.new(1, 0, 0, 30)
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 13
	btn.TextColor3 = COLOR_TEXT
	btn.BackgroundColor3 = color or COLOR_BTN
	btn.AutoButtonColor = false
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.Parent = panel
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = btn
	local base = color or COLOR_BTN
	btn.MouseEnter:Connect(function() btn.BackgroundColor3 = COLOR_BTN_HOVER end)
	btn.MouseLeave:Connect(function() btn.BackgroundColor3 = base end)
	btn.Activated:Connect(onClick)
	return btn
end

local function runScenario(name: string, fn: () -> (), engineForThis: string)
	resetAll()
	startMetrics(name, engineForThis)
	fn()
end

-- Engine selector ------------------------------------------------------------
addSection("Engine (for common tests)")
local engineBtnR: TextButton
local engineBtnT: TextButton
local function refreshEngine()
	engineBtnR.BackgroundColor3 = engine == "RoMotion" and ACCENT_R or COLOR_BTN
	engineBtnT.BackgroundColor3 = engine == "TweenService" and ACCENT_T or COLOR_BTN
end
engineBtnR = addButton("RoMotion", ACCENT_R, function()
	engine = "RoMotion"
	refreshEngine()
end)
engineBtnT = addButton("TweenService", COLOR_BTN, function()
	engine = "TweenService"
	refreshEngine()
end)

-- Part count -----------------------------------------------------------------
addSection("Part count (rebuild)")
for _, n in { 1000, 2000, 5000, 10000 } do
	addButton(string.format("%d parts", n), nil, function()
		PART_COUNT = n
		resetAll()
		buildParts()
		startMetrics("(idle)", "")
	end)
end

-- Common scenarios -----------------------------------------------------------
addSection("Common tests (both engines)")
for _, sc in commonScenarios do
	addButton(sc.name, nil, function()
		runScenario(sc.name, sc.fn, engine)
	end)
end

-- RoMotion-only scenarios ----------------------------------------------------
addSection("RoMotion only")
for _, sc in romotionScenarios do
	addButton(sc.name, ACCENT_R, function()
		runScenario(sc.name, sc.fn, "RoMotion")
	end)
end

-- Playback controls ----------------------------------------------------------
addSection("Playback control")
local CTRL = Color3.fromRGB(40, 70, 110)

addButton("Pause", CTRL, function()
	for _, a in activeRoMotion do pcall(function() a:pause() end) end
	for _, t in activeTweens do pcall(function() t:Pause() end) end
end)
addButton("Resume", CTRL, function()
	for _, a in activeRoMotion do pcall(function() a:resume() end) end
	for _, t in activeTweens do pcall(function() t:Play() end) end
end)
addButton("Reverse (R only)", CTRL, function()
	for _, a in activeRoMotion do pcall(function() a:reverse() end) end
end)
addButton("Restart", CTRL, function()
	for _, a in activeRoMotion do pcall(function() a:restart() end) end
	for _, t in activeTweens do pcall(function() t:Cancel(); t:Play() end) end
end)
addButton("Progress 25% (R only)", CTRL, function()
	for _, a in activeRoMotion do pcall(function() a:progress(0.25) end) end
end)
addButton("Progress 75% (R only)", CTRL, function()
	for _, a in activeRoMotion do pcall(function() a:progress(0.75) end) end
end)
addButton("timeScale 0.25x (R only)", CTRL, function()
	for _, a in activeRoMotion do pcall(function() a:setTimeScale(0.25) end) end
end)
addButton("timeScale 3x (R only)", CTRL, function()
	for _, a in activeRoMotion do pcall(function() a:setTimeScale(3) end) end
end)

-- Server execution -----------------------------------------------------------
addSection("Server execution (network + memory)")
local srvBtnR: TextButton
local srvBtnT: TextButton
local function refreshServerEngine()
	srvBtnR.BackgroundColor3 = serverEngine == "RoMotion" and ACCENT_R or COLOR_BTN
	srvBtnT.BackgroundColor3 = serverEngine == "TweenService" and ACCENT_T or COLOR_BTN
end
srvBtnR = addButton("Server engine: RoMotion", ACCENT_R, function()
	serverEngine = "RoMotion"
	refreshServerEngine()
end)
srvBtnT = addButton("Server engine: TweenService", COLOR_BTN, function()
	serverEngine = "TweenService"
	refreshServerEngine()
end)

for _, id in { "Position", "CFrame", "Combined", "InfiniteYoyo", "Complex" } do
	addButton("Srv: " .. id, Color3.fromRGB(60, 90, 70), function()
		fireServer("start", id)
	end)
end
-- Networked global tween: server broadcasts once, clients render locally.
-- Compare its near-zero sustained network vs. "Srv: InfiniteYoyo".
addButton("Srv: Global (networked)", Color3.fromRGB(40, 110, 90), function()
	fireServer("start", "Global")
end)
for _, id in { "Stagger", "Timeline", "Keyframes" } do
	addButton("Srv (R only): " .. id, Color3.fromRGB(50, 80, 90), function()
		fireServer("start", id)
	end)
end
addButton("SERVER STOP", Color3.fromRGB(120, 60, 55), function()
	fireServer("stop")
end)
addButton("Focus: client grid", COLOR_BTN, function()
	frameCameraAt(gridCenter, PART_COUNT)
end)
addButton("Focus: server grid", COLOR_BTN, function()
	frameCameraAt(Vector3.new(SERVER_OFFSET_X, 20, 0), PART_COUNT)
end)

addSection("")
addButton("STOP / CLEAR (client)", Color3.fromRGB(120, 50, 55), function()
	resetAll()
	startMetrics("(idle)", "")
end)

-- ---------------------------------------------------------------------------
-- Metrics loop
-- ---------------------------------------------------------------------------
local dispAccum = 0
local dispFrames = 0
local dispFps = 0
-- Smoothed idle baseline for network, captured only while no scenario runs,
-- so the display can show how much Recv/Send a scenario actually ADDS on top
-- of the constant background traffic.
local baseRecv = 0
local baseSend = 0

RunService.RenderStepped:Connect(function(dt: number)
	local inst = dt > 0 and (1 / dt) or 0

	-- rolling display FPS
	dispAccum += dt
	dispFrames += 1
	if dispAccum >= 0.3 then
		dispFps = math.floor(dispFrames / dispAccum + 0.5)
		dispFrames = 0
		dispAccum = 0
	end

	-- scenario metrics
	mFrames += 1
	if inst > 0 and inst < mMinFps then
		mMinFps = inst
	end
	local elapsed = os.clock() - mStart
	local avg = elapsed > 0 and (mFrames / elapsed) or 0

	mLine1.Text = string.format(
		"FPS: %d    Avg: %.0f    Min: %.0f    |    Engine: %s    Scenario: %s",
		dispFps,
		avg,
		mMinFps == math.huge and 0 or mMinFps,
		mEngineUsed ~= "" and mEngineUsed or "-",
		mScenario
	)
	mLine2.Text = string.format(
		"Parts: %d    |    Active  RoMotion: %d  Tween: %d    |    callbacks  start:%d update:%d repeat:%d complete:%d",
		#parts,
		#activeRoMotion,
		#activeTweens,
		cbStart,
		cbUpdate,
		cbRepeat,
		cbComplete
	)
	local recv = Stats.DataReceiveKbps
	local send = Stats.DataSendKbps
	if mScenario == "(idle)" then
		-- capture the resting background traffic (character parked + no test)
		baseRecv = baseRecv * 0.9 + recv * 0.1
		baseSend = baseSend * 0.9 + send * 0.1
	end

	mLine3.Text = string.format(
		"Recv: %.1f (Δ%+.1f)  |  Send: %.1f (Δ%+.1f) Kbps  |  Client mem: %.0f MB   (server: F9 > Server)",
		recv,
		recv - baseRecv,
		send,
		send - baseSend,
		Stats:GetTotalMemoryUsageMb()
	)
end)

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------
-- Park the player's character so it stops replicating its physics/state to
-- the server. The client owns its character's assembly, so a live character
-- continuously sends CFrame/Humanoid updates upstream -- that shows up as
-- client "Net Send" and is easy to mistake for bench traffic. Anchored and
-- still, the character sends nothing. After this, any residual client->server
-- Send during a SERVER run is purely Roblox's replication-acknowledgement
-- packets (proportional to how much the client is RECEIVING -- unavoidable,
-- and identical for both engines). The bench itself never sends per frame.
local function parkCharacter(char: Model)
	task.defer(function()
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			pcall(function()
				hum.JumpHeight = 0
			end)
		end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			hrp.Anchored = true
		end
	end)
end
if player.Character then
	parkCharacter(player.Character)
end
player.CharacterAdded:Connect(parkCharacter)

buildParts()
refreshEngine()
refreshServerEngine()
startMetrics("(idle)", "")

print("[RoMotionBench] loaded -- pick an engine, pick a part count, run a scenario, read the FPS. Run each engine separately to compare.")
