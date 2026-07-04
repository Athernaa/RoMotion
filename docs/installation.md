# Installation

RoMotion is a single, self‑contained module (a folder‑style `ModuleScript`). It has **no dependencies**.

## Option 1 — Roblox Creator Store (recommended)

1. Get RoMotion from the Creator Store.
2. In Studio, open the toolbox and insert it into your place.
3. Move the `RoMotion` model into a shared location — **`ReplicatedStorage`** is recommended so both server and client can require it.

## Option 2 — GitHub

1. Download the latest release from the GitHub repository.
2. Drag the `RoMotion` folder into `ReplicatedStorage` (or build the `.rbxm` and insert it).

## Option 3 — Rojo

If you use [Rojo](https://rojo.space/), point a path at the `src/shared/RoMotion` folder in your `*.project.json`, for example:

```json
{
  "name": "MyGame",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "RoMotion": { "$path": "path/to/RoMotion" }
    }
  }
}
```

## Requiring the module

Wherever you placed it, require it once per script that needs it:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RoMotion = require(ReplicatedStorage.RoMotion)
```

RoMotion caches itself per Luau VM, so **every `require` returns the same table and the same scheduler state**. You never need to create or manage a singleton yourself.

## Where to run it

- **Client** (`LocalScript` / client `Script`): the intended place for most animation. Property changes are computed locally and are **not** replicated per frame.
- **Server** (`Script`): fully supported. Note that changing a server‑owned instance's properties replicates normally, so for shared world animation you usually want either client‑side tweens or [Global (networked) tweens](global-tweens.md).

## Type checking

RoMotion is authored with `--!strict` and exports public Luau types. To get autocomplete and type checking, you can annotate values:

```lua
local tween: RoMotion.Tween = RoMotion.to(part, { Transparency = 1 })
```

See [API Reference › Exported types](api-reference.md#exported-types).

Next: [Getting Started](getting-started.md).
