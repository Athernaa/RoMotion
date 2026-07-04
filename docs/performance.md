# Performance

RoMotion is built to animate **hundreds or thousands** of objects without tanking your frame rate. This page explains how, and how to measure it yourself.

## What makes it fast

### One shared update loop

All active animations are advanced by a **single** `RunService.Heartbeat` connection. There is no coroutine per tween and no per‑tween connection. When nothing is animating, the connection is disconnected, so idle cost is exactly zero.

### Closure‑specialized interpolation

When a tween captures its start/end values, RoMotion builds a **specialized closure** for each property that captures the precomputed per‑component deltas. Every frame it just runs that closure — no `typeof` checks, no type‑dispatch branching, no re‑reading of plan data. The type of each value is resolved **once**, not every frame.

### Native code generation

The hot modules use `--!native` and `--!optimize 2`, so the math‑heavy interpolation and easing compile to native code.

### Cache‑friendly scheduler

Active animations live in a **dense array** (not a hash set), so the per‑frame loop iterates contiguous memory. Removal is O(1) via swap‑with‑last, and the array is preallocated to avoid resizes. Removals triggered mid‑update are deferred until the loop finishes, so slot indices stay stable.

### Conditional error isolation

A tween with **no callbacks** is advanced directly, skipping the per‑frame `pcall` wrapper. Animations that run user callbacks are still wrapped so their errors stay isolated (see [Callbacks](callbacks.md)). You pay the safety cost only where arbitrary code actually runs.

### Frame‑delta clamping

The delta fed to animations is capped at 1 second, so a hitch or a background tab can't make animations teleport.

## Client vs server

- **Client:** property changes are computed locally and are **not** replicated per frame. This is the cheapest, network‑free way to animate.
- **Server:** changing a server‑owned instance's properties replicates normally — that's Roblox, not RoMotion. For shared animation without per‑frame replication, use [Global (networked) tweens](global-tweens.md), where the server sends one packet and clients animate locally.

## Honest expectations

RoMotion computes interpolation in **Luau**, while `TweenService` runs in the engine's **C++**. For raw per‑property interpolation on a single machine, native `TweenService` will generally use less CPU. RoMotion's advantages are:

1. **Expressiveness** — timelines, keyframes, stagger, relative values, real playback control.
2. **Network efficiency** — client‑local animation and networked global tweens avoid the per‑frame replication that server‑side `TweenService` causes.
3. **Unified control** — one API and one control surface for everything.

After the optimizations above, the CPU gap for large object counts is small; choose RoMotion for what it uniquely enables, and prefer client‑side or global tweens to win on network.

## Measuring it yourself

Use Roblox's built‑in tools:

- **MicroProfiler** (`Ctrl`+`F6`) — see per‑frame CPU and where time goes.
- **Developer Console** (`F9`) — the **Server** tab shows server CPU, memory, and outgoing Kbps; watch these while running server vs global tweens.
- **`game:GetService("Stats")`** — `Stats.DataReceiveKbps`, `Stats.DataSendKbps`, and `Stats:GetTotalMemoryUsageMb()` for live network/memory readouts on the client.

A fair benchmark:

1. Animate the same number of objects with the same motion under each approach.
2. Run each approach **separately** (never at once) and read the numbers.
3. Compare client‑side RoMotion (network ~0) against server‑side approaches, and RoMotion global vs a normal server tween for network.

## Tips for large scales

- Prefer **client‑side** tweens for cosmetic effects.
- Use **global tweens** for shared world animation.
- Omit callbacks on high‑count animations you don't need to observe.
- Prefer a single **staggered** call over many individual tweens when animating a group.

Next: [API Reference](api-reference.md).
