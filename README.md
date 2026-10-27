# Dandys World — APEX

Dandy's World script with the **APEX_SYS V3.7 PLUS** terminal interface.

The UI uses the six-tab layout: `MAIN`, `VISUALS`, `TELEPORTS`, `AUTOMATION`, `PLAYERS`, and `CONFIG`. The script downloads the APEX library from its public repo on startup, with a local file fallback for development.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/DrayFKYT/DandysWorld-Apex/refs/heads/main/DandysWorld_Apex.lua"))()
```

## Library

The interface is provided by [Apex-Gui-library](https://github.com/DrayFKYT/Apex-Gui-library):

```text
https://raw.githubusercontent.com/DrayFKYT/Apex-Gui-library/refs/heads/main/ApexLibraryPlus.lua
```

## Notes

- Default toggle key: `RightControl`
- Settings are saved as `ApexLibrary_Config.json`
- `CONFIG` also contains the fixed `KILL SCRIPT & CLEANUP` button
