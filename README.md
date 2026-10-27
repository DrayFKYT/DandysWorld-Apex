# Dandys World — APEX

Dandy's World script with the **APEX_SYS V3.7 PLUS** terminal interface.

The UI uses the six-tab layout: `MAIN`, `VISUALS`, `TELEPORTS`, `AUTOMATION`, `PLAYERS`, and `CONFIG`. The window title is `Dandys World // Menu`. If a script adds more than six tabs, the tab bar scrolls horizontally with `<` / `>` arrows; selecting a tab scrolls it into view. The script downloads the APEX library from its public repo on startup, with a local file fallback for development.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/DrayFKYT/DandysWorld-Apex/main/DandysWorld_Apex.lua"))()
```

## Library

The interface is provided by [Apex-Gui-library](https://github.com/DrayFKYT/Apex-Gui-library):

```text
https://raw.githubusercontent.com/DrayFKYT/Apex-Gui-library/refs/heads/main/ApexLibraryPlus.lua
```

## Movement

All teleports use the same incremental CFrame flight: capped steps and orientation preserved. Static walls are routed with `PathfindingService`; the local fallback follows wall faces with three-ray probes instead of crossing them. Monsters and hazards are steered around with a clearance radius, so passing near them is allowed but touching is not.

Autofarm safety runs away from the current attacker (or the combined direction of all attackers). Monsters behind walls cannot see the player, so cover can end a chase. Escape points are wall-clamped, refreshed when danger gets close, and prefer breaking line of sight. Safety holds for 2.5 seconds at a 12-stud altitude and relocates the resumed generator at most once per floor.

## Notes

- Default toggle key: `RightControl`
- Settings are saved as `ApexLibrary_Config.json`
- `CONFIG` also contains the fixed `KILL SCRIPT & CLEANUP` button
