# Meal Stripper

**A tiny REFramework mod for Monster Hunter Wilds.** One click removes your
**active canteen meal buff**, so you can immediately eat a different meal —
swap meals or re-roll food skills. Made for speedrunning and testing.

## How it works

The meal state lives in `app.cHunterMealEffect` on your local hunter. The mod
writes seven fields on it (`_IsTimerActive`, `_IsEffectActive`,
`_DurationTimer`, `_MaxHealthAdd`, `_MaxStaminaAdd`, `_TempIsTimerActive`,
`_TempIsEffectActive`) and the game does **not** rewrite them afterwards — so
a one-shot strip sticks and eating a new meal works normally. Verified in the
hub, the training grounds, and across full real quests.

- No hooks, no per-frame work, no config file — a single UI callback, and
  nothing runs until you press a button.
- Only your own (user-controlled) hunter is ever selected; other players are
  never touched. No game files are modified and nothing talks to the network.
- Everything is `pcall`-guarded: the script never throws into the game.

## Requirements

- Monster Hunter Wilds
- [REFramework for MH Wilds](https://www.nexusmods.com/monsterhunterwilds) (install `dinput8.dll` first)

## Install

1. Install REFramework if you have not already.
2. Copy `reframework/buff_stripper.lua` to
   `<game>\reframework\autorun\buff_stripper.lua`
   (Steam: `...\steamapps\common\MonsterHunterWilds\reframework\autorun\`)
3. Launch the game → REFramework menu (Insert) → **Script Generated UI** →
   **Meal Stripper** confirms it loaded.

Release zips (`./package.sh` → `dist/`) come in two shapes: a flat bundle and
a `MealStripper-<version>.zip` laid out for the game folder (Nexus/Vortex).

## Usage

1. Eat a meal as usual.
2. REFramework menu → Script Generated UI → Meal Stripper → **Strip meal now**
   — the food bonuses drop immediately (max HP / stamina / attack / defence).
3. Eat another meal at the canteen. It applies normally.

**Restore last** writes back the seven tracked fields of the last strip; it is
an undo, not a meal swap (food skills of a meal eaten in between are not
touched).

Reload the script any time: REFramework menu → Script → **Reset scripts**.

## Development

- `reframework/meal_probe.lua` is the development probe this mod was built
  with (type dumps, state snapshots, strip/restore with +15/+120-frame
  verification). It is not included in release bundles.
- `./package.sh` builds both release zips into `dist/`.
- The field set was established on the 2026-11 build via the probe; if a game
  patch renames a field, the strip logs a per-field miss instead of erroring.

## Credits & license

- [REFramework](https://github.com/praydog/REFramework) by praydog
- Mod structure follows [Hunt Dumper](https://github.com/thieleju/HUNT_DUMPER) (MIT) by thieleju
- Licensed under Apache-2.0 (see `LICENSE`)
