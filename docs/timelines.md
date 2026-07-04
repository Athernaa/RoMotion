# Timelines

A **Timeline** sequences child Animations (Tweens and other Timelines) in time. It is itself an Animation, so it has the full playback control surface and can be nested inside other timelines.

## Creating a timeline

```lua
local tl = RoMotion.timeline()
```

An empty timeline has a duration of `0`. It grows as you add children.

## Adding children

```lua
tl:add(child, position?)
```

- `child` — any Animation (a Tween you built with `RoMotion.to/from/fromTo`, or another Timeline). Build it but **do not** `:play()` it — the timeline drives it.
- `position` — optional [Position Parameter](#position-parameters) deciding where the child starts. If omitted, the child is **appended at the current end** of the timeline.

`add` returns the timeline, so calls chain.

```lua
local tl = RoMotion.timeline()
    :add(RoMotion.to(A, { Position = ga }, { duration = 0.4 }))   -- starts at 0
    :add(RoMotion.to(B, { Position = gb }, { duration = 0.4 }))   -- starts after A
    :add(RoMotion.to(C, { Transparency = 0 }, { duration = 0.3 }))-- starts after B
tl:play()
```

The timeline's **total duration** is always the greatest child end time (`startTime + child.duration`) across all children, recomputed as you add.

## Position Parameters

The `position` argument controls where a child starts, GSAP‑style:

| Value | Meaning |
| --- | --- |
| *(omitted)* | Append at the timeline's current end. |
| a number `≥ 0` | Absolute time in seconds from the timeline start. |
| `"+=X"` | X seconds **after** the current end. |
| `"-=X"` | X seconds **before** the current end (clamped to ≥ 0), creating overlap. |
| `"<"` | At the **start time** of the most recently added child. |
| `">"` | At the **end time** of the most recently added child. |
| a **label name** | At that label's recorded time (see below). |

```lua
tl:add(intro, 0)          -- absolute: at 0s
tl:add(boom, "+=0.5")     -- 0.5s after the current end
tl:add(flash, "<")        -- at the same time boom starts
tl:add(fadeOut, ">")      -- right when the previous child ends
tl:add(sfx, "beat")       -- at the "beat" label
```

- `"<"` / `">"` with **no** previous child resolve to `0`.
- A numeric position **less than 0** raises an error.
- An **unknown label** raises an error and the child is not added.

## Labels

Labels are named time markers you can target with position parameters or use for organization.

```lua
tl:addLabel("chorus", 2.5)      -- mark 2.5s as "chorus"
tl:add(drop, "chorus")          -- place a child at that mark
```

- A label name is 1–256 characters; its time must be `≥ 0`.
- Adding a label whose name already exists **replaces** its recorded time.

## Nesting timelines

A Timeline can be added as a child of another Timeline. The nested timeline contributes its own total duration:

```lua
local intro = RoMotion.timeline()
    :add(RoMotion.to(Logo, { Size = big }, { duration = 0.5 }))
    :add(RoMotion.to(Logo, { Rotation = 360 }, { duration = 0.5 }))

local main = RoMotion.timeline()
    :add(intro)                 -- the whole intro runs as one block
    :add(RoMotion.to(Menu, { Position = center }, { duration = 0.4 }), "+=0.2")

main:play()
```

Adding a timeline to **itself or to one of its descendants** is rejected (cyclic nesting error), leaving the timeline unchanged. Adding a non‑Animation value is also rejected.

## Time scaling (and it's recursive)

`setTimeScale` changes playback speed. On a timeline, it applies to **all children, nested timelines, and their descendants**:

```lua
tl:setTimeScale(2)    -- everything runs at double speed
tl:setTimeScale(0.5)  -- everything at half speed
```

A timeline rejects a `timeScale` of `0` or negative and keeps its previous value.

## Controlling a timeline

Because a timeline is an Animation, it uses the same controls as a tween — `play`, `pause`, `resume`, `reverse`, `restart`, `seek`, `progress`, `kill`. Controlling the timeline controls the whole choreography, including children.

```lua
tl:play()
tl:seek(1.0)     -- jump the whole choreography to 1 second in
tl:reverse()     -- play the whole thing backward
```

Next: [Playback Control](playback-control.md).
