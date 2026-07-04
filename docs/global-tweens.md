# Global (Networked) Tweens

Global tweens solve a classic Roblox problem: **you want everyone to see an animation on a shared object, but you don't want the server replicating that object's properties every single frame.**

With `RoMotion.global`, the **server broadcasts one small packet** describing the tween, and **every client renders it locally** — perfectly synchronized to server time, with automatic late‑join support. The result is smooth, shared animation with essentially **zero sustained network cost**.

## The idea

- **Normal server tween:** server changes the property each frame → Roblox replicates the new value to every client each frame → sustained bandwidth proportional to (objects × frame rate).
- **Global tween:** server sends the start/end/timing **once** → each client computes the animation itself with RoMotion's local scheduler → the property changes locally, never replicating per frame.

## API

Only callable from the **server**. Calling it on a client raises a clear error.

```lua
RoMotion.global.to(target, props, config?)          -> GlobalHandle
RoMotion.global.from(target, props, config?)         -> GlobalHandle
RoMotion.global.fromTo(target, fromProps, toProps, config?) -> GlobalHandle
```

- `target` — a server‑owned `Instance`, or an ordered list of them, that is replicated to clients.
- `props` — a Property Map (same as normal tweens; relative `"+=X"` strings are supported and resolved on the server).
- `config` — a subset of [Tween_Config](configuration.md): `duration`, `ease` **(must be a string)**, `delay`, `["repeat"]`, `repeatDelay`, `yoyo`, `stagger`.

The returned **GlobalHandle** has:

```lua
handle:Stop()   -- tells every client to stop and remove its local copy
handle.Id       -- the numeric id of this broadcast
```

### Example

```lua
-- On the SERVER:
local RoMotion = require(game.ReplicatedStorage.RoMotion)

local handle = RoMotion.global.to(workspace.Beacon, { Orientation = Vector3.new(0, 180, 0) }, {
    duration = 1,
    ease = "Sine.InOut",
    yoyo = true,
    ["repeat"] = -1,
})

-- Later, stop it everywhere:
-- handle:Stop()
```

Every client — including players who join while it's running — sees the beacon spinning, in sync.

## How synchronization works

1. When you call `global.to`, the server:
   - resolves a concrete **start** value (the instance's current value) and **end** value per property, so every client animates identical numbers;
   - sets the instance to its **final resting value** immediately (so the authoritative state matches where clients end, and late joiners after completion see the correct result);
   - stamps `startTime = workspace:GetServerTimeNow()`;
   - broadcasts the packet to all clients.
2. Each client builds a local tween and computes `elapsed = workspace:GetServerTimeNow() - startTime`, then **seeks** the tween to `elapsed` before playing.

Because `GetServerTimeNow()` is synchronized across the server and all clients, **every client shows the same frame at the same real moment**, regardless of ping.

## Late join

The server keeps a registry of still‑active global tweens. When a new player joins, the server re‑sends each active packet **only to that player**, who seeks to the current elapsed time and joins the animation already in progress.

- **Finite** tweens auto‑expire from the registry once they'd have finished on every client. A player joining after that simply sees the final resting value (already set on the server).
- **Infinite** tweens stay in the registry until you `:Stop()` them.

You don't have to do anything — late join is automatic.

## When to use it

✅ Great for:

- Ambient/world animation everyone should see: rotating beacons, floating pickups, pulsing lights, opening doors, moving platforms (visual), environmental motion.
- Any cosmetic animation of **anchored**, server‑owned instances.

❌ Not for:

- **Gameplay‑authoritative** motion the server must validate (hitboxes, projectiles that deal damage by position). The server does not simulate the motion frame‑by‑frame; it only knows the start and resting states.
- **Unanchored / physics** parts (network ownership conflicts).
- Cases needing **custom easing functions** or **keyframes** — these can't be networked. Use a named easing; keyframes are unsupported for global tweens.
- **Lifecycle callbacks** — global tweens don't fire `onStart`/`onUpdate`/etc. (each client runs independently).

## Why this is fast

For, say, 200 rotating beacons:

- **Server InfiniteYoyo (normal):** 200 CFrame/Orientation updates replicated every frame → constant, significant bandwidth.
- **`global.to` with a target list:** **one** packet describing all 200 → then zero sustained replication; each client animates locally.

You can see this directly in the demo place: run "Srv: Global (networked)" vs "Srv: InfiniteYoyo" and compare the server's outgoing Kbps and the client's received Kbps.

## Requirements & caveats

- The target instance must be **replicated to a client** for that client to animate it. If it hasn't arrived yet on some client, that client skips it (no error).
- Global tweens are best on **anchored** instances so the client's local writes aren't fought by physics/ownership.
- The server sets the property to the **final resting value** immediately; this is the value non‑participating or post‑completion clients will see.

Next: [Performance](performance.md).
