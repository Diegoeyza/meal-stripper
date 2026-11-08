# Nexus page — Meal Stripper v1.0.0

Upload `dist/MealStripper-1.0.0.zip` as the main file, then paste the fields
below into the mod page.

**Title:**

```
Meal Stripper — Swap Canteen Meals (REFramework)
```

**Short description:**

```
One click removes your active canteen meal buff so you can immediately eat a different meal. For speedruns and re-rolling food skills.
```

**Description (Markdown):**

````markdown
# Meal Stripper

One click removes your **active canteen meal buff** so you can immediately eat a different meal (swap meals / re-roll food skills). Made for speedrunning and testing.

It writes 7 fields on **your** local hunter's meal state (`app.cHunterMealEffect`) — it never selects other players, does not modify game files, and does not talk to the network.

## Requirements

- Monster Hunter Wilds
- [REFramework for MH Wilds](https://www.nexusmods.com/monsterhunterwilds) (install `dinput8.dll` first)

## Install

Extract this archive into your game folder (Vortex: install normally). You should get:

    <game>\reframework\autorun\buff_stripper.lua

Default Steam path: `...\steamapps\common\MonsterHunterWilds\`

## Usage

1. Eat a meal as usual.
2. REFramework menu (Insert) → **Script Generated UI** → **Meal Stripper** → **Strip meal now** — the buff drops immediately (max HP / stamina / attack / defence food bonuses).
3. Eat another meal at the canteen. It applies normally.

The panel also shows your current meal state, and **Restore last** undoes the strip (the 7 tracked fields only — it's an undo, not a meal swap).

## Notes

- **One-shot strip:** the game does not rewrite the stripped fields — verified in the hub, the training grounds, and across full real quests.
- Reload any time: REFramework menu → Script → **Reset scripts**.
- No hooks, no per-frame work, no config; nothing runs until you press a button.

## Credits

- REFramework by praydog
- Mod structure follows Hunt Dumper (MIT) by thieleju
````
