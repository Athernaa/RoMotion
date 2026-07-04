# Configuration Reference (`Tween_Config`)

Every optional field you can pass in the `config` table of `to` / `from` / `fromTo`. All fields are optional; omit any to use its default.

```lua
RoMotion.to(target, props, {
    duration = 1,
    ease = "Back.Out",
    delay = 0.25,
    ["repeat"] = 2,
    repeatDelay = 0.1,
    yoyo = true,
    stagger = 0.05,
    keyframes = { ... },
    onStart = function(anim) end,
    onUpdate = function(anim, progress) end,
    onRepeat = function(anim, iterationIndex) end,
    onComplete = function(anim) end,
})
```

## Field reference

| Field | Type | Default | Range / Notes |
| --- | --- | --- | --- |
| `duration` | `number` | `0.5` | Seconds. Must be **> 0**. |
| `ease` | `string` \| `function` | `"Quad.InOut"` | A library name (e.g. `"Elastic.Out"`) or a custom function `(t: number) -> number`. See [Easing](easing.md). |
| `delay` | `number` | `0` | Seconds to wait before the first interpolation. Range `0`–`86400`. |
| `["repeat"]` | `number` | `0` | Extra iterations after the first. `N` → `N+1` total. `-1` → infinite. Integer, range `0`–`1000000` (or `-1`). |
| `repeatDelay` | `number` | `0` | Seconds to wait **between** iterations (never after the last). Range `0`–`86400`. |
| `yoyo` | `boolean` | `false` | Alternate direction each iteration (forward, reverse, forward, …). |
| `stagger` | `number` | `0` | Per‑target start offset when animating a list of targets. Range `0`–`3600`. See [Stagger](stagger.md). |
| `keyframes` | `{ Keyframe }` | `nil` | Multi‑step path. See [Keyframes](keyframes.md). |
| `onStart` | `(anim) -> ()` | `nil` | Fires once when the active phase begins. |
| `onUpdate` | `(anim, progress) -> ()` | `nil` | Fires each rendered frame; `progress` is `0`–`1`. |
| `onRepeat` | `(anim, iterationIndex) -> ()` | `nil` | Fires at each iteration boundary; index is 0‑based. |
| `onComplete` | `(anim) -> ()` | `nil` | Fires once at natural completion (never when `["repeat"] == -1`). |

> ⚠️ **`["repeat"]` bracket syntax:** `repeat` is a Luau reserved word, so it must be written `["repeat"] = 3` inside the table.

## Duration semantics

`duration` is the length of **one iteration** (one forward or one reverse pass). The full run time of a tween is:

```
delay + duration * (repeat + 1) + repeatDelay * repeat
```

Add `(n - 1) * stagger` when animating `n` targets with a stagger.

## Delay vs repeatDelay

- **`delay`** happens once, before the very first iteration.
- **`repeatDelay`** happens between consecutive iterations only — never before the first and never after the last.

```lua
-- 0.5s wait, then 3 pulses of 0.4s each with 0.2s gaps between them.
RoMotion.to(part, { Size = big }, {
    duration = 0.4,
    delay = 0.5,
    ["repeat"] = 2,      -- 3 iterations total
    repeatDelay = 0.2,   -- gaps only between the 3
    yoyo = true,
}):play()
```

## Repeat and yoyo

- `["repeat"] = N` (N ≥ 0) plays the interpolation `N + 1` times.
- `["repeat"] = -1` repeats forever until you stop it. `onComplete` never fires; `onRepeat` fires every iteration.
- `yoyo = true` reverses direction on each subsequent iteration, so the object ping‑pongs.

```lua
-- Infinite gentle bob.
RoMotion.to(part, { Position = up }, {
    duration = 1,
    ["repeat"] = -1,
    yoyo = true,
    ease = "Sine.InOut",
}):play()
```

## Validation

Every field is validated at creation time. Out‑of‑range or wrong‑typed values raise a descriptive error and **no tween is created**. For example, `["repeat"] = 2.5` (non‑integer) or `delay = -1` will throw. See [Troubleshooting](troubleshooting.md).

Next: [Easing](easing.md).
