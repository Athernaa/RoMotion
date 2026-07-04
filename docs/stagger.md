# Stagger

Stagger applies **one tween definition across many targets**, offsetting each target's start time so the effect cascades — a classic "wave" of motion — from a single call.

## Basic usage

Pass an **ordered list of targets** as the first argument and a numeric `stagger` (seconds) in the config:

```lua
local boxes = { box1, box2, box3, box4, box5 }

RoMotion.to(boxes, { Position = "+=0" }, { -- (use a real destination in practice)
    duration = 0.5,
    stagger = 0.1,   -- each box starts 0.1s after the previous
    ease = "Quad.Out",
}):play()
```

- The **first** target starts at offset `0`.
- The **i‑th** target (0‑based) starts at `i * stagger` seconds.
- All targets share the same properties, duration, and easing.

## What you get back

Staggering returns a **single Animation** that controls **all** the staggered tweens as one unit. Pausing, reversing, seeking, or killing it affects every target together.

```lua
local wave = RoMotion.to(boxes, { Rotation = 360 }, { duration = 0.6, stagger = 0.08 })
wave:play()
-- later:
wave:pause()   -- pauses the whole cascade
wave:reverse() -- runs the cascade backward
```

Its **total duration** is:

```
(n - 1) * stagger + duration
```

where `n` is the number of targets — the last target's offset plus one iteration.

## Simultaneous (no stagger)

`stagger = 0` (or omitting it) starts every target at the same time. This is the natural way to animate many objects together with one call:

```lua
RoMotion.to(boxes, { Transparency = 1 }, { duration = 0.4 }):play() -- all fade together
```

## Choosing targets

Targets are matched by **list order**, so the visual cascade follows whatever order you build the list in. Arrange the list to fan out from a point, sweep across a row, ripple outward from the center, etc.

```lua
-- Cascade top-to-bottom
local column = {}
for _, item in ipairs(list:GetChildren()) do table.insert(column, item) end
RoMotion.to(column, { Position = "+=20" }, { duration = 0.3, stagger = 0.05 }):play()
```

## Rules

- The targets list must not be empty.
- `stagger` must be a number in the range `0`–`3600`.

Both are validated at creation; a bad value raises a clear error and no tweens are created.

## Stagger + repeat/yoyo/callbacks

Stagger composes with the rest of the config. Repeat and yoyo apply per target; lifecycle callbacks fire for the animation as a whole (`onUpdate` reports the leading target's progress).

Next: [Timelines](timelines.md).
