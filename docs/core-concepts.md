# Core Concepts

Understanding these five ideas makes everything else in RoMotion obvious.

## 1. Everything is an Animation

Both a **Tween** and a **Timeline** are *Animations*. They share one control surface:

```
play · pause · resume · restart · reverse · seek · progress · setTimeScale · kill
```

Because they share it, you control a 20‑step timeline exactly the same way you control a single fade. This is the same uniformity GSAP is loved for.

## 2. Factories build, `:play()` starts

The factories — `RoMotion.to`, `from`, `fromTo`, `timeline` — **create and return** an Animation but do not start it. You start it with `:play()`.

```lua
local t = RoMotion.to(part, { Transparency = 1 }) -- built, not running
t:play()                                          -- now running
```

This separation lets you pre‑build animations, store them, add them to timelines, and start them precisely when you want.

## 3. The single shared scheduler

All active animations are advanced by **one** `RunService.Heartbeat` connection — the *Scheduler*, a process‑wide singleton.

- When the number of active animations goes from 0 → 1, the connection is established.
- When it drops back to 0, the connection is disconnected, so **zero per‑frame work happens when nothing is animating**.
- Only *root* animations are scheduled. A timeline advances its own children, so a child tween is driven by its parent, not the scheduler directly.

You never interact with the scheduler; it is fully automatic.

## 4. Local time, frame‑rate independence

Every Animation tracks a `position` (its local time in seconds) and a `direction`. Each frame the scheduler feeds a **clamped** delta time (capped at 1 second, so a lag spike can't teleport an animation), and each animation advances its own clock scaled by its `timeScale`.

Because progress is derived from elapsed time, animations look the same at 30 FPS or 240 FPS, and `seek`/`progress` are trivial: set the position and re‑render.

## 5. Client‑local computation

When an animation runs **on the client**, RoMotion computes and applies the property changes locally, every frame. Those changes are **not** transmitted per frame over the network. This is the key difference from server‑driven `TweenService` usage, where tweened properties replicate.

- **Client** → cheap, no network traffic, perfect for cosmetic/visual motion.
- **Server** → property changes replicate normally (that's just how Roblox works). For shared world animation without per‑frame replication, use [Global (networked) tweens](global-tweens.md).

## Supported data types

RoMotion interpolates these value types:

| Type | How it interpolates |
| --- | --- |
| `number` | linear |
| `Vector2` | component‑wise linear |
| `Vector3` | component‑wise linear |
| `UDim` | Scale & Offset linear |
| `UDim2` | Scale & Offset of both axes linear |
| `Color3` | per‑channel (R/G/B) linear |
| `CFrame` | position **lerp** + rotation **slerp** |

Any property whose value is one of these types can be animated. Trying to animate an unsupported type raises a clear error and leaves the target unchanged.

## Targets

A **target** can be:

- a Roblox **Instance** (a `Part`, a `Frame`, a `Model`, …), or
- a plain **table** whose fields you want to animate (useful for animating arbitrary numeric state).

You can also pass an **ordered list of targets** to animate many objects at once — see [Stagger](stagger.md).

```lua
-- Instance
RoMotion.to(workspace.Part, { Transparency = 1 }):play()

-- Plain table
local state = { alpha = 0 }
RoMotion.to(state, { alpha = 1 }, {
    duration = 1,
    onUpdate = function() print(state.alpha) end,
}):play()
```

Next: [Tweens](tweens.md).
