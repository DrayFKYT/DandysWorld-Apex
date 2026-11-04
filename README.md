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
- Random and `NEXT PREVIEW` buttons that cycle the filtered results (the old `N` hotkey was removed)
- Preview current-creature animations through COS's own fake-state system
- Preview foreign animations on the current rig through the creature `Animator`
- Loop toggle, reset to the current creature's original animation, and catalog refresh
- Automatic preview cleanup on species change, respawn, or script unload
- `CREATURE ANIMATION PACK` browser: search the full animation library by creature, select a pack, and apply its complete Idle, Walk, Run, Swim, and action set to the current rig until `RESET`
- Sea-only packs without land movement still work on land creatures: their `Swim` becomes `Walk`, `SwimFast` becomes `Run`, and `SwimIdle` becomes `Idle`. Packs that have all land and water states map normally
- The pack status line reports the selected creature, track count, and the animations currently playing on your creature; the swap is reasserted if the game controller replaces the track table

The same tab has `RAGDOLL` and `UNRAGDOLL` action rows. Ragdoll switches the creature to its idle pose, freezes that pose, detaches the game's movement forces, enables collisions, and lets gravity and momentum roll the unanchored body with real physics; control stays disabled until you unragdoll. Unragdoll stands the creature back up at the spot where it rolled to, restores its collisions and animations, reattaches the movement forces, and returns control. Both rows have optional programmable keybinds, defaulting to `R` and `U`; press the adjacent `X` to clear a binding to `NONE`.

The instant-menu drop timing is fixed at 1 second and 1,111,111 studs/second. `DROP_DURATION` and `DROP_SPEED` are no longer editable controls and are not read from the config file.

Exploit Fly speed accepts values from `1` to `100000`.

Turning `WALK_SWIM_SPEED`, `SPRINT_SPEED`, or `FLY_SPEED` off restores the value the current creature had before the toggle was enabled. Baselines are tracked per creature, so changing species or respawning uses that creature's own values. The input box keeps its configured number.

`ALWAYS_WALL_CLIMBER` only forces the `Climber` attribute while it is enabled. Creatures that spawn with wall climb keep it when the toggle is off; creatures without it only climb while the toggle is on, and lose it again when turned off.

While `INFINITE_OXYGEN` is enabled the `BREATH` HUD bar is hidden; while `INFINITE_MOISTURE` is enabled the `MOISTURE` HUD bar is hidden. Both bars return to their normal state when the toggles are turned off or the script is cleaned up.

The `CONFIG` tab's `OPEN / CLOSE MENU` row is a keybind-only row: clicking the key chip rebinds it, the binding cannot be cleared, and it shows neither an `X` nor a toggle button.

## Library

The interface is provided by [Apex-Gui-library](https://github.com/DrayFKYT/Apex-Gui-library):

```text
https://raw.githubusercontent.com/DrayFKYT/Apex-Gui-library/refs/heads/main/ApexLibraryPlus.lua
```

Both scripts download revision 13 of the library on startup, with a local `ApexLibraryPlus.lua` fallback for development. Revision 13 makes fullscreen a centered panel that is 50% of the usable screen width and 70% of its height, and shows two tab panes side by side: the active tab on the left and the previously viewed tab on the right. Clicking a tab moves the old left pane to the right, and wide fullscreen panels fit more tabs before the tab bar scrolls. The window still animates between layouts and the mobile claw toggle stays layered above it. Revision 12 added the animated header fullscreen glyph; revision 11 added `Tab:CreateKeybindButton` rows with optional action buttons and clear buttons, and `ShowAction = false` leaves a keybind-only row.

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
