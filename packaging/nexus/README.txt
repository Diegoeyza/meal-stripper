Meal Stripper — REFramework mod for Monster Hunter Wilds
=======================================================

One click removes your ACTIVE canteen meal buff so you can immediately eat a
different meal (swap meals / re-roll food skills). Made for speedrunning and
testing. It writes 7 fields on YOUR local hunter's meal state
(app.cHunterMealEffect): it never selects other players, does not modify game
files, and does not talk to the network.

REQUIREMENTS
------------
- Monster Hunter Wilds
- REFramework for MH Wilds (install dinput8.dll first)

INSTALL (Vortex or manual)
--------------------------
The archive is already laid out for the game folder.

Manual:
  1. Install REFramework if you have not already.
  2. Extract this archive into your game folder so you get
        <game>\reframework\autorun\buff_stripper.lua
     Default Steam path:
        ...\steamapps\common\MonsterHunterWilds\
  3. Launch the game; open the REFramework menu -> "Script Generated UI" ->
     "Meal Stripper" to confirm it loaded.

Vortex:
  Install the archive normally; it maps into the game's reframework folder.

USAGE
-----
  1. Eat a meal as usual.
  2. REFramework menu -> Script Generated UI -> Meal Stripper
     -> "Strip meal now". The meal buff is gone immediately (max HP / stamina
     / attack / defence food bonuses drop).
  3. Eat another meal at the canteen. It applies normally.
  - "Restore last" writes back the 7 tracked fields of the last strip; it is
    an undo, not a meal swap (food skills of a meal eaten in between are not
    touched).
  - The panel shows your current meal state (active / timer / adds).

NOTES
-----
- One-shot strip: the game does not rewrite the stripped fields — verified in
  the hub, the training grounds, and across full real quests.
- Reload the script any time: REFramework menu -> "Script" -> "Reset scripts".
- No hooks, no per-frame work, no config file; nothing runs until you press
  a button.

CREDITS
-------
- REFramework by praydog
- Mod structure follows Hunt Dumper (MIT) by thieleju
- This project: Apache-2.0
