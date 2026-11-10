# Nexus page — Meal Stripper v1.0.0

Upload `dist/MealStripper-1.0.0.zip` as the main file.

The Nexus mod description field uses **BBCode** (not Markdown). Paste the block
below straight into the Description field (BBCode/source view).

---

**Title:**

```
Meal Stripper — Swap Canteen Meals (REFramework)
```

**Short description:**

```
One click removes your active canteen meal buff so you can immediately eat a different meal. For speedruns and re-rolling food skills.
```

**Full description (BBCode — paste as-is):**

```
[size=6][b]Meal Stripper[/b][/size]

One click removes your [b]active canteen meal buff[/b], so you can immediately eat a different meal — swap meals, or re-roll your food skills without leaving the camp.

Made for speedrunning and testing.

[line]

[size=5][b]What it does[/b][/size]

The meal (its timer, its active flag, and the max HP / max stamina it adds) lives in a small state block on your hunter. Meal Stripper clears that block, the food bonuses drop off immediately, and the canteen lets you eat again right away.

[list]
[*][b]Strip meal now[/b] — removes the active meal buff. Max HP, max stamina and the food attack/defence bonuses drop immediately.
[*][b]Restore last[/b] — writes the previous values back. This is an [b]undo[/b], not a meal swap: it restores the exact values that were stripped.
[*]The panel also shows your current meal state, so you can see whether a meal is active before and after.
[/list]

[line]

[size=5][b]How to use[/b][/size]

[list=1]
[*]Install REFramework, then extract this archive into your game folder (Vortex: install normally). You should end up with:
[code]<game>\reframework\autorun\buff_stripper.lua[/code]
[*]Eat a meal as usual.
[*]In game, press [b]Insert[/b] to open REFramework → [b]Script Generated UI[/b] → [b]Meal Stripper[/b] → [b]Strip meal now[/b].
[*]Eat another meal at the canteen. It applies normally.
[/list]

Default Steam path:
[code]...\steamapps\common\MonsterHunterWilds\[/code]

[line]

[size=5][b]Notes[/b][/size]

[list]
[*][b]One-shot strip.[/b] The game does not rewrite the stripped fields, so the buff stays off until you eat again. Verified in the hub, in the training grounds, and across full real quests.
[*][b]Your hunter only.[/b] It only ever touches your own character's meal state - other players are never selected or modified.
[*][b]Restore is an undo.[/b] If you ate a different meal in the meantime, Restore will not replace that meal; it only puts back the values it removed.
[*]Reload any time: REFramework menu → Script → [b]Reset scripts[/b], or restart the game.
[/list]

[line]

[size=5][b]Safety[/b][/size]

[list]
[*]No hooks, no per-frame work, no config file — nothing runs until you press a button.
[*]No game files are modified and nothing talks to the network.
[*]Every SDK call is guarded, so the script never throws into the game.
[/list]

[line]

[size=5][b]Requirements[/b][/size]

[list]
[*]Monster Hunter Wilds
[*][url=https://www.nexusmods.com/monsterhunterwilds]REFramework for MH Wilds[/url] (install [b]dinput8.dll[/b] first)
[/list]

[line]

[size=5][b]Credits[/b][/size]

[list]
[*][url=https://github.com/praydog/REFramework]REFramework[/url] by praydog
[*]Mod structure follows [url=https://github.com/thieleju/HUNT_DUMPER]Hunt Dumper[/url] (MIT) by thieleju
[/list]

Source and issues: [url=https://github.com/Diegoeyza/meal-stripper]github.com/Diegoeyza/meal-stripper[/url]
```
