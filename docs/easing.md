# Easing

Easing shapes *how* a value moves between its start and end — slow‑in, fast‑out, bouncy, elastic, and so on. RoMotion ships the full GSAP‑style family and also accepts your own functions.

## The library

Eleven families, each with **In**, **Out**, and **InOut** variants:

```
Linear   Quad   Cubic   Quart   Quint   Sine   Expo   Circ   Back   Elastic   Bounce
```

- **In** — starts slow, accelerates.
- **Out** — starts fast, decelerates.
- **InOut** — slow at both ends, fast in the middle.

## Naming an easing

Pass the name as a **string** in the form `"Family.Variant"`:

```lua
RoMotion.to(part, { Position = goal }, { ease = "Back.Out" }):play()
RoMotion.to(part, { Position = goal }, { ease = "Elastic.InOut" }):play()
```

- The default when `ease` is omitted is **`"Quad.InOut"`**.
- `"Linear"` (bare) is accepted as an alias for `"Linear.InOut"` — all three linear variants are identical.
- An unknown name raises an error naming the offending string.

## Using the library directly

`RoMotion.Easing` exposes every function for direct use, both nested and via `resolve`:

```lua
local Easing = RoMotion.Easing

local f = Easing.Quad.InOut        -- a function: (t) -> easedT
print(f(0), f(0.5), f(1))          -- 0, 0.5-ish, 1

-- resolve turns a name (or function, or nil) into a concrete function:
local g = Easing.resolve("Bounce.Out")
local h = Easing.resolve(nil)      -- returns Quad.InOut (the default)
```

Every library function returns **exactly 0 at t = 0** and **exactly 1 at t = 1**, so endpoints are pixel‑perfect regardless of floating‑point drift.

## Custom easing functions

Any function that maps a normalized time `t` (in `0..1`) to an eased progress value can be used as `ease`. Your function **may return values outside `0..1`** to overshoot (that's how `Back`/`Elastic` work).

```lua
-- Smoothstep by hand.
RoMotion.to(part, { Position = goal }, {
    ease = function(t) return t * t * (3 - 2 * t) end,
}):play()

-- A stepped easing (snaps in 4 steps).
RoMotion.to(part, { Position = goal }, {
    ease = function(t) return math.floor(t * 4) / 4 end,
}):play()
```

If a custom easing returns a non‑number, RoMotion raises a clear error rather than corrupting the animation.

> 📎 **Networked tweens:** custom easing functions cannot be sent over the network, so [global tweens](global-tweens.md) require a **named** easing string.

## Per‑keyframe easing

Each keyframe in a [keyframe tween](keyframes.md) can specify its own `ease`, letting a single tween change its feel between segments. Segments without an `ease` fall back to `Quad.InOut`.

## Choosing an easing

| You want… | Try |
| --- | --- |
| Snappy UI that settles | `Quad.Out`, `Cubic.Out` |
| Playful overshoot | `Back.Out` |
| Springy, energetic | `Elastic.Out` |
| A ball dropping | `Bounce.Out` |
| Smooth two‑sided motion | `Sine.InOut`, `Quad.InOut` |
| Mechanical / constant | `"Linear"` |

Next: [Keyframes](keyframes.md).
