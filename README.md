<div align="center">

# RoMotion

**A GSAP‑inspired animation & tweening library for Roblox, written in strict Luau.**

Everything `TweenService` does — and a lot more — through one fluent, high‑performance API.

</div>

---

## Why RoMotion?

`TweenService` is great until you need timelines, keyframes, staggering, relative values, real playback control, or lag‑free animation for hundreds of objects. RoMotion gives you all of that with a single, tiny module and no dependencies.

- **Fluent, GSAP‑style API** — `RoMotion.to`, `from`, `fromTo`, `timeline`.
- **Full easing library** — 11 families × In/Out/InOut, plus custom easing functions.
- **Timelines** — sequence animations with labels and GSAP‑style position parameters (`"+=0.5"`, `"<"`, `">"`), nesting, and recursive time‑scaling.
- **Keyframes** — multi‑step property paths in a single tween.
- **Stagger** — cascade one animation across many objects with one call.
- **Relative values** — `"+=100"`, `"-=0.5"`.
- **Delay, repeat, yoyo, repeatDelay, infinite loops.**
- **Rich playback control** — play, pause, resume, reverse, restart, seek, progress, timeScale, kill.
- **Lifecycle callbacks** — `onStart`, `onUpdate`, `onComplete`, `onRepeat`.
- **Networked "global" tweens** — the server broadcasts one small packet and every client renders locally, with automatic late‑join and time synchronization. No per‑frame replication.
- **Blazing fast** — one shared update loop, closure‑specialized interpolation, native codegen, a cache‑friendly scheduler.

## 30‑second example

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RoMotion = require(ReplicatedStorage.RoMotion)

-- Slide a part up and fade a GUI, both eased, in one line each.
RoMotion.to(workspace.Part, { Position = workspace.Part.Position + Vector3.new(0, 10, 0) }, {
    duration = 1,
    ease = "Back.Out",
}):play()

RoMotion.to(script.Parent.Frame, { BackgroundTransparency = 1 }, { duration = 0.5 }):play()
```

## Documentation

Full documentation lives in [`docs/`](docs/) and is organized for GitBook:

- [Introduction](docs/introduction.md)
- [Installation](docs/installation.md)
- [Getting Started](docs/getting-started.md)
- [Core Concepts](docs/core-concepts.md)
- [Tweens: to / from / fromTo](docs/tweens.md)
- [Configuration Reference](docs/configuration.md)
- [Easing](docs/easing.md)
- [Keyframes](docs/keyframes.md)
- [Stagger](docs/stagger.md)
- [Timelines](docs/timelines.md)
- [Playback Control](docs/playback-control.md)
- [Lifecycle Callbacks](docs/callbacks.md)
- [Global (Networked) Tweens](docs/global-tweens.md)
- [Performance](docs/performance.md)
- [API Reference](docs/api-reference.md)
- [Troubleshooting & FAQ](docs/troubleshooting.md)

## License

Free and open source. See [`LICENSE`](LICENSE).
