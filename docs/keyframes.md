# Keyframes

Keyframes let a **single tween pass through several intermediate states** — a multi‑step path — instead of a straight start → end. Think of an object that moves right, then up, then back, all in one tween with one timeline of its own.

## Shape

Pass a `keyframes` list in the config. Each **Keyframe** is:

```lua
{
    position = 0.5,               -- fractional point in the tween (0..1)
    values = { Position = ... },  -- a Property Map for this waypoint
    ease = "Sine.Out",            -- optional; defaults to Quad.InOut
}
```

- `position` — where in the tween's total duration this waypoint is reached, as a fraction from `0` to `1`.
- `values` — the property values at that waypoint.
- `ease` — optional easing for the **segment ending at this keyframe**.

## How endpoints work

The property map you pass to `to` / `from` / `fromTo` still defines the **position‑0** and **position‑1** endpoints:

- Position 0 = the captured current value (for `to`) or the value you supply.
- Position 1 = the tween's destination.

`keyframes` add waypoints **in between**. If the earliest keyframe's position is greater than 0, the tween interpolates from the captured current value to that first keyframe.

## Example: an L‑shaped path

```lua
local home = part.CFrame

RoMotion.to(part, { CFrame = home }, {  -- ends back home (position 1)
    duration = 1.8,
    keyframes = {
        { position = 0.4, values = { CFrame = home * CFrame.new(0, 8, 0) },  ease = "Sine.Out" },
        { position = 0.7, values = { CFrame = home * CFrame.new(8, 8, 0) },  ease = "Sine.InOut" },
    },
}):play()
-- Path: home → up (at 40%) → up-and-right (at 70%) → back home (at 100%)
```

## Rules

- Keyframe positions must be numbers within `0`–`1` inclusive.
- The list must not be empty, and no two keyframes may share the same position.
- Keyframes are interpolated in **ascending order of position**, regardless of the order you list them in.
- A keyframe without an `ease` uses `Quad.InOut` for its segment.

Violating any of these raises a clear error identifying the offending keyframe or list.

## Reaching a keyframe exactly

Because each waypoint sits at an exact fractional position and each segment's easing hits its endpoints exactly, **seeking the tween to a keyframe's position yields exactly that keyframe's value**. This makes keyframe tweens reliable for precise, repeatable motion.

```lua
local t = RoMotion.to(part, { CFrame = home }, {
    duration = 2,
    keyframes = {
        { position = 0.5, values = { CFrame = midpoint } },
    },
})
t:play()
t:progress(0.5) -- part is now exactly at `midpoint`
```

## Notes and limits

- Keyframes compose with any mode (`to`/`from`/`fromTo`) — the mode determines the position‑0/position‑1 endpoints; keyframes fill in the middle.
- Keyframes are **not** supported for [global (networked) tweens](global-tweens.md).

Next: [Stagger](stagger.md).
