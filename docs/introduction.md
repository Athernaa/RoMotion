# Introduction

**RoMotion** is a GSAP‑inspired animation and tweening library for Roblox, written entirely in strict Luau and delivered as a single, dependency‑free module.

If you have ever used [GSAP](https://gsap.com/) on the web, RoMotion will feel immediately familiar: the naming, the argument shapes, and the mental model deliberately mirror GSAP, while adapting cleanly to Roblox data types (`Vector3`, `UDim2`, `Color3`, `CFrame`, and more).

## What RoMotion gives you

| Capability | TweenService | RoMotion |
| --- | :---: | :---: |
| Tween properties to a target value | ✅ | ✅ |
| Easing styles (In/Out/InOut) | ✅ | ✅ |
| Repeat, reverse (yoyo), delay | ✅ | ✅ |
| **`from` / `fromTo` tweens** | ❌ | ✅ |
| **Relative values (`"+=100"`)** | ❌ | ✅ |
| **Keyframes (multi‑step paths)** | ❌ | ✅ |
| **Stagger across many objects** | ❌ | ✅ |
| **Timelines, labels, position params** | ❌ | ✅ |
| **Nested timelines & recursive timeScale** | ❌ | ✅ |
| **Custom easing functions** | ❌ | ✅ |
| **Pause / resume / reverse / seek / progress** | Partial | ✅ |
| **Lifecycle callbacks (start/update/complete/repeat)** | Partial | ✅ |
| **Networked tweens (broadcast once, render locally)** | ❌ | ✅ |
| **Single shared update loop** | Internal | ✅ (one connection) |

## Design principles

1. **One shared scheduler.** Every active animation is advanced by a single `RunService.Heartbeat` connection. There is no coroutine per tween and no connection sprawl.
2. **Client‑local by default.** When you run an animation on the client, property changes are computed locally each frame and are **not** replicated per frame across the network — avoiding the traffic amplification that native `TweenService` can cause.
3. **Pure, testable cores.** Interpolation, easing, and relative‑value parsing are pure functions, making the mathematically rich parts predictable and fast.
4. **Composable animations.** Both a `Tween` and a `Timeline` are *Animations* and share the exact same control surface (play, pause, seek, …), so you can control a whole choreography the same way you control a single tween.

## Who is it for?

- Developers who want **GSAP‑level expressiveness** on Roblox.
- Anyone animating **many objects at once** and worried about performance or network cost.
- Teams who want **readable, chainable** animation code instead of `TweenInfo` boilerplate.

## A quick taste

```lua
local RoMotion = require(game.ReplicatedStorage.RoMotion)

-- A timeline that slides a menu in, bounces a button, then fades a hint.
local tl = RoMotion.timeline()

tl:add(RoMotion.to(Menu, { Position = UDim2.fromScale(0.5, 0.5) }, { duration = 0.4, ease = "Quad.Out" }))
tl:add(RoMotion.to(Button, { Size = UDim2.fromScale(0.25, 0.12) }, { duration = 0.3, ease = "Back.Out" }), "-=0.1")
tl:add(RoMotion.to(Hint, { TextTransparency = 0 }, { duration = 0.5 }))

tl:play()
```

Continue to [Installation](installation.md) to add RoMotion to your game.
