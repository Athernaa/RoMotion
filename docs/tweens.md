# Tweens: `to` / `from` / `fromTo`

A **Tween** interpolates one or more properties of one or more targets from a start value to an end value over a duration, shaped by an easing function.

All three factories share the same shape and return a `Tween` you must `:play()`.

```lua
RoMotion.to(target, properties, config?)          -> Tween
RoMotion.from(target, properties, config?)        -> Tween
RoMotion.fromTo(target, fromProps, toProps, config?) -> Tween
```

- `target` — an `Instance`, a plain table, or an **ordered list** of either (for [staggering](stagger.md)).
- `properties` / `fromProps` / `toProps` — a **Property Map** (see below).
- `config` — an optional [Tween_Config](configuration.md). If omitted, defaults are used.

## `to` — animate to a destination

Interpolates each property from the target's **current** value to the value you give. The start value is captured **the moment the tween begins its active phase** (i.e. when it starts playing, after any `delay`).

```lua
RoMotion.to(part, {
    Position = part.Position + Vector3.new(0, 10, 0),
    Transparency = 0.5,
}, { duration = 1, ease = "Quad.Out" }):play()
```

## `from` — animate from a source into place

Interpolates each property from the value you give **to the target's current value**. When the active phase begins, the source value is applied first, then the tween eases toward the captured current value. Perfect for entrance animations.

```lua
-- Frame flies in from off-screen to its current position.
RoMotion.from(Frame, { Position = UDim2.fromScale(1.5, 0.5) }, {
    duration = 0.5,
    ease = "Back.Out",
}):play()
```

## `fromTo` — explicit start and end

Interpolates between two values you supply. The start and end property maps **must contain the same set of property names**.

```lua
RoMotion.fromTo(part,
    { Position = pointA, Transparency = 1 },  -- start
    { Position = pointB, Transparency = 0 },  -- end
    { duration = 1.2 }
):play()
```

## Property Maps

A Property Map is a table of `propertyName = value`:

```lua
{
    Position = UDim2.fromScale(0.5, 0.5),
    BackgroundColor3 = Color3.fromRGB(255, 0, 0),
    BackgroundTransparency = 0.2,
}
```

The property must exist on the target and its value must be a [supported type](core-concepts.md#supported-data-types). Values can also be **relative strings** (see below).

## Relative values

For **number** properties, a value can be a relative string:

| Syntax | Meaning |
| --- | --- |
| `"+=X"` | current value **plus** X |
| `"-=X"` | current value **minus** X |

The delta is resolved against the value captured when the tween begins its active phase. Whitespace around the operator/number is tolerated.

```lua
-- Fade a part by 0.5 more transparent, relative to whatever it is now.
RoMotion.to(part, { Transparency = "+=0.5" }, { duration = 1 }):play()

-- Spin a UI element 90 degrees further.
RoMotion.to(Frame, { Rotation = "+=90" }, { duration = 0.4 }):play()
```

Relative values only apply to number‑typed properties. Applying `"+=..."` to a non‑number property raises an error.

## Default duration

If you omit `duration`, RoMotion uses **0.5 seconds**.

```lua
RoMotion.to(part, { Transparency = 1 }):play() -- 0.5s, Quad.InOut
```

## Errors you can rely on

RoMotion validates eagerly at creation time, so a bad configuration never yields a half‑built tween. It raises a clear error when:

- the target is `nil`;
- the property map is empty or `nil`;
- a named property does not exist on the target;
- `fromTo` start/end key sets differ;
- `duration` is provided but not a number greater than 0;
- a value type is unsupported, or start/end types differ;
- a relative string is malformed or applied to a non‑number.

See [Troubleshooting](troubleshooting.md) for the full list and messages.

Next: [Configuration Reference](configuration.md).
