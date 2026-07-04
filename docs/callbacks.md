# Lifecycle Callbacks

Callbacks let you run code at key moments of an animation — to chain logic, play sounds, spawn effects, or clean up. Set them in the [config](configuration.md).

## The four callbacks

| Callback | Signature | When it fires |
| --- | --- | --- |
| `onStart` | `(anim)` | Once, when the active phase begins (after any `delay`). |
| `onUpdate` | `(anim, progress)` | Every rendered frame; `progress` is `0`–`1`. |
| `onRepeat` | `(anim, iterationIndex)` | At each iteration boundary; `iterationIndex` is 0‑based. |
| `onComplete` | `(anim)` | Once, at natural completion. **Never** when `["repeat"] == -1`. |

Every callback receives the animation instance as its first argument, so you can control it from inside the callback.

```lua
RoMotion.to(part, { Position = goal }, {
    duration = 1,
    onStart    = function(anim) print("started", anim) end,
    onUpdate   = function(anim, p) bar.Size = UDim2.fromScale(p, 1) end,
    onComplete = function(anim) print("done") end,
}):play()
```

## Firing order

When several callbacks come due on the same frame, they fire in a fixed order:

```
onStart  →  onUpdate  →  onRepeat / onComplete
```

## Progress in `onUpdate`

`onUpdate`'s `progress` is always within `0`–`1` (it is the un‑eased, normalized position within the current iteration), so it's safe to drive a progress bar or lerp UI directly with it — even when using an overshooting easing like `Back` or `Elastic`.

## Repeats and completion

- For a finite tween with `["repeat"] = N`, `onRepeat` fires with indices `0, 1, …, N-1`, and `onComplete` fires once at the very end.
- For an infinite tween (`["repeat"] = -1`), `onRepeat` fires at every iteration boundary and `onComplete` **never** fires.

```lua
RoMotion.to(part, { Rotation = "+=360" }, {
    duration = 1,
    ["repeat"] = -1,
    onRepeat = function(_, i) print("loop", i) end, -- 0, 1, 2, ...
}):play()
```

## Chaining animations with callbacks

`onComplete` is a simple way to run one animation after another (though a [Timeline](timelines.md) is usually cleaner):

```lua
RoMotion.to(door, { CFrame = openCF }, {
    duration = 0.5,
    onComplete = function()
        RoMotion.to(light, { Brightness = 5 }, { duration = 0.3 }):play()
    end,
}):play()
```

## Error isolation

If a callback raises an error, RoMotion **contains it**: the scheduler keeps advancing every other active animation without interruption, and the animation whose callback threw keeps its current state and progress. One buggy callback never freezes your whole game's animation.

## A note on performance

Callbacks are entirely optional. A tween with **no** callbacks takes an even faster internal path (RoMotion skips per‑frame callback bookkeeping and error isolation for it). If you're animating hundreds of objects and don't need callbacks, simply omit them.

> 📎 [Global (networked) tweens](global-tweens.md) do **not** fire lifecycle callbacks, because each client renders the animation independently and callbacks are not sent over the network.

Next: [Global (Networked) Tweens](global-tweens.md).
