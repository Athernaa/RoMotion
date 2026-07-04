# Playback Control

Every Animation — Tween or Timeline — exposes the same control surface. Almost all methods **return the Animation** so you can chain them; the exceptions are `kill` (returns nothing) and `progress()` called with no argument (returns the current fraction).

## The control surface

| Method | Description |
| --- | --- |
| `play()` | Set direction forward and start/continue advancing from the current position. |
| `pause()` | Stop advancing, keeping the current position and direction. |
| `resume()` | Continue advancing from the retained position and direction. |
| `restart()` | Reset position to 0, direction to forward, and play. Lifecycle callbacks can fire again. |
| `reverse()` | Set direction backward and advance toward the beginning. |
| `seek(seconds)` | Jump to an absolute time (clamped to `[0, duration]`), re‑render, keep playing/paused state. |
| `progress(fraction?)` | With a fraction (`0..1`): jump to that fraction of the duration. With no argument: **return** the current fraction. |
| `setTimeScale(scale)` | Set playback speed (e.g. `2` = double, `0.5` = half). On timelines this propagates to descendants. |
| `kill()` | Stop, detach from the scheduler, and release target references. Terminal. |

## Playing, pausing, resuming

```lua
local t = RoMotion.to(part, { Position = goal }, { duration = 2 })
t:play()
task.wait(0.5)
t:pause()      -- freezes in place
task.wait(0.5)
t:resume()     -- continues from where it froze
```

## Reversing

`reverse()` flips direction; the animation eases back toward its start. When it reaches position 0 going backward, it halts there.

```lua
t:reverse()
```

## Restart

`restart()` resets to the beginning and plays forward again, re‑firing `onStart` and (for finite tweens) `onComplete`/`onRepeat` on the new run.

```lua
t:restart()
```

## Seeking and progress

`seek` uses **seconds**; `progress` uses a **0..1 fraction**. Both update all target properties immediately and preserve whether the animation was playing or paused.

```lua
t:seek(1.0)       -- jump to 1 second in
t:progress(0.25)  -- jump to a quarter of the way through
local p = t:progress()  -- read the current fraction (no argument)
```

Out‑of‑range values are clamped: `seek` to `[0, duration]`, `progress` to `[0, 1]`.

## Time scale

```lua
t:setTimeScale(2)    -- twice as fast
t:setTimeScale(0.25) -- quarter speed (slow motion)
```

On a **timeline**, `setTimeScale` scales every child and nested descendant, and rejects values `≤ 0` (keeping the previous scale). On a plain tween it sets the multiplier you provide; use values `> 0`.

## Kill

`kill()` permanently stops an animation, removes it from the scheduler, and releases its references to targets so they can be garbage‑collected. **After `kill`, all control calls are no‑ops** (they do nothing and raise no error) — so it's always safe to call them on a possibly‑dead animation.

```lua
t:kill()
t:play() -- safe no-op; nothing happens
```

> A **naturally completed** tween (finite repeat that finished) detaches from the scheduler but keeps its data, so you can still `restart()` it and it holds its final value. A **killed** tween is terminal.

## Playback state

You can read an animation's state fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `position` | `number` | Current local time in seconds. |
| `duration` | `number` | Total length in seconds. |
| `direction` | `number` | `1` = forward, `-1` = backward. |
| `timeScale` | `number` | Current speed multiplier. |
| `state` | `string` | `"idle"`, `"playing"`, `"paused"`, `"completed"`, or `"killed"`. |
| `started` | `boolean` | Whether the active phase has begun since creation/restart. |

```lua
if t.state == "playing" then t:pause() else t:resume() end
```

## Chaining

Because controls return the Animation:

```lua
RoMotion.to(part, { Position = goal }, { duration = 1 })
    :setTimeScale(1.5)
    :play()
```

Next: [Lifecycle Callbacks](callbacks.md).
