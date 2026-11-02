# Dandys World + Creatures of Sonaria — APEX

Multi-script hub for two games, both using the **APEX_SYS V3.7 PLUS** terminal interface and the same shared UI profile.

## Scripts

### Dandy's World

Full APEX migration with movement, teleports, automation, player ESP, and cleanup.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/DrayFKYT/DandysWorld-Apex/main/DandysWorld_Apex.lua"))()
```

Tabs: `MAIN`, `VISUALS`, `TELEPORTS`, `AUTOMATION`, `PLAYERS`, `CONFIG`.

### Creatures of Sonaria

APEX migration of **Drk_Duck's** original Cos menu. Every original feature is preserved: instant-menu drop, outline ESP, minimap ESP, wall climber, infinite stamina/oxygen/moisture, scent hide, aggro/cower, speed attributes, exploit fly, staff detection, and OOB remote removal.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/DrayFKYT/DandysWorld-Apex/main/Cos_Apex.lua"))()
```

Tabs: `MAIN`, `MOVEMENT`, `SURVIVAL`, `ESP`, `ANIMATION`, `CONFIG`.

The `ANIMATION` tab adds a live animation swapper:

- Search the full game catalog (477 species, 7,293 animation assets, 40 unique animation names)
- Scope the search to the current creature or all creatures
- Filter results with the `TYPE` dropdown: broad groups (`ALL`, `MOVE`, `SWIM`, `POSE`) plus each remaining animation type (`AGGRESSION`, `AMBUSH`, `BITE`, `COWER`, `DRINK`, `EAT`, `ENRAGED`, `HEADBUT`, `TAIL`)
- Random preview button plus an `N` hotkey that cycles the filtered results
- Preview current-creature animations through COS's own fake-state system
- Preview foreign animations on the current rig through the creature `Animator`
- Loop toggle, reset to the current creature's original animation, and catalog refresh
- Automatic preview cleanup on species change, respawn, or script unload

The same tab has `RAGDOLL` and `UNRAGDOLL` action rows. Ragdoll tumbles the rig with a client-side roll and small hops; unragdoll rights it and returns control to COS. Both rows have optional programmable keybinds, defaulting to `R` and `U`; press the adjacent `X` to clear a binding to `NONE`.

The instant-menu drop timing is fixed at 1 second and 1,111,111 studs/second. `DROP_DURATION` and `DROP_SPEED` are no longer editable controls and are not read from the config file.

Exploit Fly speed accepts values from `1` to `100000`.

Turning `WALK_SWIM_SPEED`, `SPRINT_SPEED`, or `FLY_SPEED` off restores the value the current creature had before the toggle was enabled. Baselines are tracked per creature, so changing species or respawning uses that creature's own values. The input box keeps its configured number.

`ALWAYS_WALL_CLIMBER` only forces the `Climber` attribute while it is enabled. Creatures that spawn with wall climb keep it when the toggle is off; creatures without it only climb while the toggle is on, and lose it again when turned off.

While `INFINITE_OXYGEN` is enabled the `BREATH` HUD bar is hidden; while `INFINITE_MOISTURE` is enabled the `MOISTURE` HUD bar is hidden. Both bars return to their normal state when the toggles are turned off or the script is cleaned up.

The `CONFIG` tab's `OPEN / CLOSE MENU` row is a keybind-only row: clicking the key chip rebinds it, the binding cannot be cleared, and it shows neither an `X` nor a toggle button.

## Library

The interface is provided by [Apex-Gui-library](https://github.com/DrayFKYT/Apex-Gui-library):

```text
https://raw.githubusercontent.com/DrayFKYT/Apex-Gui-library/main/ApexLibraryPlus.lua
```

Both scripts download revision 11 of the library on startup, with a local `ApexLibraryPlus.lua` fallback for development. Revision 11 adds `Tab:CreateKeybindButton` rows with optional action buttons and clear buttons; `ShowAction = false` leaves a keybind-only row.

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
- `Cos_Apex_Config.json` — Creatures of Sonaria toggles, speeds, animation preferences, and ragdoll keybinds

## Notes

- Default menu keybind: `RightControl` (mandatory, no clear button)
- Default ragdoll keybinds: `R` to ragdoll, `U` to unragdoll (optional, clearable)
- Every script includes a fixed `KILL SCRIPT & CLEANUP` action in `CONFIG`
- Original Creatures of Sonaria gameplay logic and credit belong to **Drk_Duck**
