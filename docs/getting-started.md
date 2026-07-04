# Getting Started

This page walks you from your first tween to a small choreography in a few minutes.

## Your first tween

```lua
local RoMotion = require(game.ReplicatedStorage.RoMotion)

local part = workspace.Part

RoMotion.to(part, { Transparency = 1 }, { duration = 1 }):play()
```

Three things to notice:

1. **`RoMotion.to(target, properties, config)`** creates a tween.
2. The properties table maps **property name → destination value**.
3. **You must call `:play()`** — creating a tween does not start it automatically. This lets you build, store, and control a tween before it runs.

> 💡 Every factory (`to`, `from`, `fromTo`, `timeline`) returns an **Animation** object. Almost every method returns the same object, so calls are chainable: `RoMotion.to(...):play()`.

## Animating multiple properties

Pass as many properties as you like — they all animate together over the same duration:

```lua
RoMotion.to(part, {
    Position = part.Position + Vector3.new(0, 8, 0),
    Color = Color3.fromRGB(255, 120, 60),
    Transparency = 0.5,
}, {
    duration = 1.2,
    ease = "Back.InOut",
}):play()
```

## Choosing an easing

The `ease` field takes a **name string** from the built‑in library or **your own function**:

```lua
RoMotion.to(part, { Position = goal }, { duration = 1, ease = "Elastic.Out" }):play()

-- Custom easing: any function mapping t (0..1) to eased progress.
RoMotion.to(part, { Position = goal }, {
    duration = 1,
    ease = function(t) return t * t end, -- ease-in quad, by hand
}):play()
```

The default easing is `Quad.InOut`. See [Easing](easing.md) for the full list.

## From, and FromTo

- **`to`** animates from the *current* value to a destination.
- **`from`** animates from a *given* value to the current value (great for entrances).
- **`fromTo`** animates between two explicit values.

```lua
-- Fade a GUI IN: it starts fully transparent and ends at its current transparency.
RoMotion.from(Frame, { BackgroundTransparency = 1 }, { duration = 0.4 }):play()

-- Explicit start and end.
RoMotion.fromTo(part,
    { Position = a },  -- start
    { Position = b },  -- end
    { duration = 1 }
):play()
```

## Controlling playback

Hold on to the returned Animation to control it later:

```lua
local tween = RoMotion.to(part, { Position = goal }, { duration = 2, ease = "Sine.InOut" })
tween:play()

task.wait(0.5)
tween:pause()
task.wait(0.5)
tween:reverse()   -- play backward toward the start
```

See [Playback Control](playback-control.md) for the whole surface.

## Repeating and yoyo

```lua
RoMotion.to(part, { Position = goal }, {
    duration = 0.6,
    ["repeat"] = 3,   -- plays 4 times total (1 + 3 repeats)
    yoyo = true,      -- alternate direction each iteration
}):play()
```

> ⚠️ `repeat` is a reserved word in Luau, so it is written as `["repeat"]` inside the config table.

## Reacting with callbacks

```lua
RoMotion.to(part, { Position = goal }, {
    duration = 1,
    onStart = function() print("started") end,
    onUpdate = function(_, progress) print("progress", progress) end,
    onComplete = function() print("done") end,
}):play()
```

## A small timeline

```lua
local tl = RoMotion.timeline()
tl:add(RoMotion.to(A, { Position = aGoal }, { duration = 0.4 }))
tl:add(RoMotion.to(B, { Position = bGoal }, { duration = 0.4 }))   -- runs after A
tl:add(RoMotion.to(C, { Transparency = 0 }, { duration = 0.3 }), "-=0.2") -- overlaps B's end
tl:play()
```

Next, read [Core Concepts](core-concepts.md) to understand how RoMotion works under the hood, or jump straight to [Tweens](tweens.md).
