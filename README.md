# Dandys World + Creatures of Sonaria — APEX

Multi-script hub for two games, both using the **APEX_SYS V3.7 PLUS** terminal interface and the same shared UI profile.

## Scripts

### Dandy's World

Full APEX migration with movement, teleports, automation, player ESP, and cleanup.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/DrayFKYT/DandysWorld-Apex/refs/heads/main/DandysWorld_Apex.lua"))()
```

Tabs: `MAIN`, `VISUALS`, `TELEPORTS`, `AUTOMATION`, `PLAYERS`, `CONFIG`.

### Creatures of Sonaria

APEX migration of **Drk_Duck's** original Cos menu. Every original feature is preserved: instant-menu drop, outline ESP, minimap ESP, wall climber, infinite stamina/oxygen/moisture, scent hide, aggro/cower, speed attributes, exploit fly, staff detection, and OOB remote removal.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/DrayFKYT/DandysWorld-Apex/refs/heads/main/Cos_Apex.lua"))()
```

Tabs: `MAIN`, `MOVEMENT`, `SURVIVAL`, `ESP`, `ANIMATION`, `CONFIG`.

The `ANIMATION` tab adds a live animation swapper:

- Search the full game catalog (477 species, 7,293 animation assets, 40 unique animation names)
- Scope the search to the current creature or all creatures
- Preview current-creature animations through COS's own fake-state system
- Preview foreign animations on the current rig through the creature `Animator`
- Loop toggle, reset to the current creature's original animation, and catalog refresh
- Automatic preview cleanup on species change, respawn, or script unload

While `INFINITE_OXYGEN` is enabled the `BREATH` HUD bar is hidden; while `INFINITE_MOISTURE` is enabled the `MOISTURE` HUD bar is hidden. Both bars return to their normal state when the toggles are turned off or the script is cleaned up.

## Library

The interface is provided by [Apex-Gui-library](https://github.com/DrayFKYT/Apex-Gui-library):

```text
https://raw.githubusercontent.com/DrayFKYT/Apex-Gui-library/refs/heads/main/ApexLibraryPlus.lua
```

Both scripts download revision 9 of the library on startup, with a local `ApexLibraryPlus.lua` fallback for development.

## Documentation

Full API reference for tabs, buttons, toggles, inputs, color pickers, lists, keybinds, themes, and cleanup:

```text
https://github.com/DrayFKYT/Apex-Gui-library#readme
```

## Dandy's World movement

All teleports use the same incremental CFrame flight: capped steps and orientation preserved. Static walls are routed with `PathfindingService`; the local fallback follows wall faces with three-ray probes instead of crossing them. Monsters and hazards are steered around with a clearance radius, so passing near them is allowed but touching is not.

Autofarm safety runs away from the current attacker (or the combined direction of all attackers). Monsters behind walls cannot see the player, so cover can end a chase. Escape points are wall-clamped, refreshed when danger gets close, and prefer breaking line of sight. Safety holds for 2.5 seconds at a 12-stud altitude and relocates the resumed generator at most once per floor.

## Config files

- `ApexLibrary_Config.json` — shared APEX UI settings (accent color, hide key, mobile lock, mobile button position)
- `DandysWorld_Apex_Config.json` — Dandy's World toggles and ESP colors
- `Cos_Apex_Config.json` — Creatures of Sonaria toggles, speeds, and animation preferences

## Notes

- Default hide key: `RightControl`
- Every script includes a fixed `KILL SCRIPT & CLEANUP` action in `CONFIG`
- Original Creatures of Sonaria gameplay logic and credit belong to **Drk_Duck**
