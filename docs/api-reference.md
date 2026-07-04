# API Reference

A complete, compact reference for every public function, method, field, and type. For explanations and examples, follow the links to the topic pages.

## The `RoMotion` table

```lua
local RoMotion = require(game.ReplicatedStorage.RoMotion)
```

| Member | Kind | Summary |
| --- | --- | --- |
| `RoMotion.to` | function | Create a [tween](tweens.md) from current → destination. |
| `RoMotion.from` | function | Create a tween from a source → current. |
| `RoMotion.fromTo` | function | Create a tween between two explicit values. |
| `RoMotion.timeline` | function | Create a [Timeline](timelines.md). |
| `RoMotion.Easing` | table | The [easing library](easing.md) + `resolve`. |
| `RoMotion.global` | table | [Networked tweens](global-tweens.md) (server‑only factories). |

Requiring RoMotion multiple times returns the **same table** and the **same scheduler state**.

## Factories

```lua
RoMotion.to(target, props, config?)              -> Tween
RoMotion.from(target, props, config?)            -> Tween
RoMotion.fromTo(target, fromProps, toProps, config?) -> Tween
RoMotion.timeline(config?)                        -> Timeline
```

- `target`: `Instance` | plain table | ordered list of targets (for stagger).
- `props` / `fromProps` / `toProps`: `PropertyMap`.
- `config`: `Tween_Config` (optional).
- Factories **do not auto‑play**; call `:play()`.

## `Tween_Config` fields

| Field | Type | Default | Range |
| --- | --- | --- | --- |
| `duration` | `number` | `0.5` | `> 0` |
| `ease` | `string` \| `(t:number)->number` | `"Quad.InOut"` | library name or function |
| `delay` | `number` | `0` | `0`–`86400` |
| `["repeat"]` | `number` | `0` | integer `0`–`1000000`, or `-1` |
| `repeatDelay` | `number` | `0` | `0`–`86400` |
| `yoyo` | `boolean` | `false` | — |
| `stagger` | `number` | `0` | `0`–`3600` |
| `keyframes` | `{ Keyframe }` | `nil` | see [Keyframes](keyframes.md) |
| `onStart` | `(anim)->()` | `nil` | — |
| `onUpdate` | `(anim, progress:number)->()` | `nil` | `progress` in `0..1` |
| `onRepeat` | `(anim, iterationIndex:number)->()` | `nil` | 0‑based index |
| `onComplete` | `(anim)->()` | `nil` | not fired for `["repeat"] == -1` |

## `Keyframe`

```lua
{
    position: number,                  -- 0..1
    values: PropertyMap,
    ease: (string | (t)->number)?,     -- default "Quad.InOut"
}
```

## Animation control surface

Shared by **Tween** and **Timeline**. Returns `self` unless noted.

| Method | Returns | Notes |
| --- | --- | --- |
| `play()` | self | Forward; start/continue. |
| `pause()` | self | Freeze, keep position & direction. |
| `resume()` | self | Continue from retained state. |
| `restart()` | self | Reset to 0, forward, play. |
| `reverse()` | self | Backward. |
| `seek(seconds)` | self | Absolute time, clamped `[0, duration]`. |
| `progress(fraction?)` | self **or** number | Set fraction (`0..1`), or return current fraction if no arg. |
| `setTimeScale(scale)` | self | Speed multiplier. Timelines validate `> 0` and propagate. |
| `kill()` | *(nothing)* | Terminal; releases targets; controls become no‑ops. |

## Animation state fields

| Field | Type | Meaning |
| --- | --- | --- |
| `position` | `number` | Current local time (seconds). |
| `duration` | `number` | Total length (seconds). |
| `direction` | `number` | `1` forward, `-1` backward. |
| `timeScale` | `number` | Speed multiplier. |
| `state` | `string` | `"idle"` \| `"playing"` \| `"paused"` \| `"completed"` \| `"killed"`. |
| `started` | `boolean` | Active phase begun since create/restart. |

## Timeline methods

```lua
timeline:add(child: Animation, position: Position_Parameter?) -> Timeline
timeline:addLabel(name: string, time: number)                 -> Timeline
```

`Position_Parameter`:

| Value | Meaning |
| --- | --- |
| *(omitted)* | append at current end |
| `number ≥ 0` | absolute seconds |
| `"+=X"` / `"-=X"` | relative to current end (clamped ≥ 0) |
| `"<"` / `">"` | start / end of most recent child (or 0 if none) |
| label name | that label's time |

## Easing

```lua
RoMotion.Easing.<Family>.<Variant>   -- e.g. RoMotion.Easing.Quad.InOut  (a function)
RoMotion.Easing.resolve(ease: (string | function)?) -> function
```

Families: `Linear, Quad, Cubic, Quart, Quint, Sine, Expo, Circ, Back, Elastic, Bounce`. Variants: `In, Out, InOut`. Name strings: `"Family.Variant"` (e.g. `"Bounce.Out"`); `"Linear"` is an alias for `"Linear.InOut"`.

## Global (server‑only)

```lua
RoMotion.global.to(target, props, config?)              -> GlobalHandle
RoMotion.global.from(target, props, config?)            -> GlobalHandle
RoMotion.global.fromTo(target, fromProps, toProps, config?) -> GlobalHandle
```

- `config` accepts `duration`, `ease` (**string only**), `delay`, `["repeat"]`, `repeatDelay`, `yoyo`, `stagger`. No `keyframes`, no function easing, no callbacks.
- Client calls raise an error.

`GlobalHandle`:

| Member | Notes |
| --- | --- |
| `handle:Stop()` | Stops the tween on every client and removes it from the late‑join registry. |
| `handle.Id` | Numeric broadcast id. |

## Exported types

Accessible as fields of the required module for annotations:

```lua
type RoMotion.Animation
type RoMotion.Tween
type RoMotion.Timeline
type RoMotion.Tween_Config
type RoMotion.Easing_Function   -- (t: number) -> number
type RoMotion.Target            -- Instance | { [string]: any }
type RoMotion.PropertyMap       -- { [string]: any }
type RoMotion.Keyframe
type RoMotion.Position_Parameter -- number | string
```

```lua
local t: RoMotion.Tween = RoMotion.to(part, { Transparency = 1 })
```

## Supported value types

`number`, `Vector2`, `Vector3`, `UDim`, `UDim2`, `Color3`, `CFrame`. (CFrame = position lerp + rotation slerp.)

Next: [Troubleshooting & FAQ](troubleshooting.md).
