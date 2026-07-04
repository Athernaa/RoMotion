# Troubleshooting & FAQ

## My tween isn't animating

**You probably forgot `:play()`.** Factories build a tween but do not start it:

```lua
RoMotion.to(part, { Transparency = 1 }) -- built, NOT running
RoMotion.to(part, { Transparency = 1 }):play() -- ✅
```

Also check:

- The property name is spelled correctly and exists on the target.
- The `duration` is greater than 0.
- The target still exists (a destroyed target is dropped automatically).

## Error messages and what they mean

RoMotion validates eagerly and raises clear, descriptive errors. Common ones:

| Message (abridged) | Cause | Fix |
| --- | --- | --- |
| `invalid argument Target (nil)` | Target is `nil`. | Pass a valid Instance/table. |
| `invalid argument Property_Map` | Empty or `nil` property map. | Include at least one property. |
| `invalid property … does not exist on Target` | Property name not on target. | Check spelling / target type. |
| `fromTo start/end Property_Map key mismatch` | `fromTo` maps have different keys. | Use the same keys in both. |
| `invalid Tween_Config.duration` | Duration not a number > 0. | Use a positive number. |
| `type mismatch for property …` | Start/end values are different types. | Make both the same type. |
| `unsupported type for property …` | Value type isn't supported. | Use a supported type. |
| `unknown easing …` | `ease` string isn't in the library. | Use a valid name (e.g. `"Quad.Out"`). |
| `invalid custom easing return value` | Custom easing returned a non‑number. | Return a number. |
| `invalid Tween_Config["repeat"]` | Not `-1` or an integer `0`–`1000000`. | Use a valid repeat count. |
| `invalid Tween_Config.delay / repeatDelay` | Negative or `> 86400`. | Use `0`–`86400`. |
| `invalid Relative_Value …` | Malformed `"+=X"`/`"-=X"`. | Fix the string. |
| `invalid Relative_Value target …` | Relative value on a non‑number property. | Only use on numbers. |
| `invalid Keyframe … position` | Keyframe position outside `0`–`1`. | Keep positions in range. |
| `invalid keyframes list` | Empty list or duplicate positions. | Provide distinct positions. |
| `invalid Timeline timeScale` | Timeline `setTimeScale` ≤ 0. | Use a value `> 0`. |
| `cyclic Timeline nesting detected` | Added a timeline to itself/descendant. | Don't create a cycle. |
| `invalid Timeline child` | Added a non‑Animation. | Add a Tween/Timeline. |
| `unknown label …` | Position parameter names a missing label. | Add the label first. |
| `invalid Position_Parameter` | Numeric position `< 0`. | Use `≥ 0`. |
| `invalid Tween_Config.stagger` | Not a number in `0`–`3600`. | Use a valid stagger. |
| `invalid argument Targets` | Empty targets list. | Provide at least one target. |

## `["repeat"]` looks wrong

`repeat` is a reserved word in Luau. Always write it in brackets:

```lua
{ ["repeat"] = 3 }
```

## Animation snaps back at the end (server)

If you animate a **server‑owned** instance on the **client**, the server's authoritative value can override your local changes. For shared world animation, use [Global (networked) tweens](global-tweens.md), which set the server's resting value correctly and render locally on every client.

## Global tween does nothing on a client

- Confirm you're calling `RoMotion.global.*` on the **server** (client calls error).
- Confirm the target is **server‑owned** and replicated to that client.
- Confirm `ease` is a **string** (functions can't be networked), and you're not passing `keyframes` (unsupported for global).

## Global tween isn't perfectly in sync

Sync uses `workspace:GetServerTimeNow()`. Ensure you're not overriding the animated property elsewhere. Extremely high‑latency clients seek to the correct elapsed on arrival, so they should still match.

## Does RoMotion work in plugins / edit mode?

RoMotion targets runtime game usage. The scheduler binds to `RunService.Heartbeat` while the game is running.

## Can I animate a plain table?

Yes. A target can be a table; RoMotion writes the interpolated values to its fields. Use `onUpdate` to react:

```lua
local state = { alpha = 0 }
RoMotion.to(state, { alpha = 1 }, { duration = 1, onUpdate = function() print(state.alpha) end }):play()
```

## Is it type‑safe?

RoMotion is `--!strict` and exports public types. Annotate values with `RoMotion.Tween`, `RoMotion.Timeline`, etc. See [API Reference › Exported types](api-reference.md#exported-types).

## How do I stop everything?

Call `:kill()` on each animation you hold. Killed animations detach from the scheduler and release their targets. There is no global "kill all" — keep references to animations you may need to stop, or group them in a timeline and kill the timeline.

---

Still stuck? Open an issue on the GitHub repository or post on the Roblox Creator Forum thread.
