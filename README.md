# Geronimo External Gunstock Calibration Tool

Calibrate your physical VR gunstock for **GERONIMO** outside the game, in a simple
SteamVR scene — live numbers, optic-height references, working saves, automatic
backups, and in-VR restore.

**[⬇ Download the latest release](../../releases/latest)** — standalone exe, no install.

## Why this exists

GERONIMO's in-game gunstock calibration has a save bug: the **up/down and left/right**
position you set with the off-hand thumbstick is never written to disk (the game
saves `0.000000` for those axes), so the gun "snaps back" when you pull both triggers
and the calibration never carries into gameplay. Forward distance and pitch *do* save.

Full reverse-engineered root cause, reproduction steps, and a suggested code fix for
the developers: **[BUG_REPORT.md](BUG_REPORT.md)**.

The game's *read* path works perfectly, so this tool simply writes correct values
into the same file the game reads:
`%LOCALAPPDATA%\Geronimo\Saved\Config\Windows\GameUserSettings.ini`
(section `[DarkWeapons.GunstockCalibration]`, format `Up,LR,Fwd|Pitch,Yaw,Roll|Scale`
in cm/degrees — axis order proven by experiment).

## Quick start

1. **Close Geronimo** (it rewrites the INI on exit; the tool refuses to save while it runs).
2. Start **SteamVR**, run `GeronimoCalibTool.exe`, put on the headset.
   *(Windows SmartScreen will warn — unsigned hobby tool → "More info → Run anyway".)*
3. One-time: shoulder your stock, press **LEFT X** (base-adjust), align the virtual
   sights to your natural eye line, pull **both triggers**, LEFT X to exit.
4. Per gun: select with **A/B**, shoulder, adjust with the sticks, **both triggers** = save.
5. Verify in Geronimo; expect at most one small trim pass per gun.

No in-game calibration is ever needed. **Never** use Geronimo's own calibration menu
afterwards — the in-game save bug will zero your vertical again (restore from a
backup if it happens).

## Controls

| Input | Action |
|---|---|
| LEFT stick | Up/Down + Left/Right |
| RIGHT stick | Forward/Back + Pitch |
| hold either GRIP | fine adjust (15% speed) |
| RIGHT A / B | next / previous gun |
| RIGHT stick click | cycle optic: irons / EOTech EXPS3 / T-2 on GBRS Hydra 2.91" |
| LEFT stick click | backup **restore menu** (stick = select, A = restore, B = cancel) |
| LEFT X | cycle mode: offset / base-adjust / **two-hand capture** (hold stock two-handed, pull both triggers → full calibration in one shot, foregrip point placed on your front controller) |
| LEFT Y | revert current gun to last saved values |
| BOTH TRIGGERS | **save** to the Geronimo INI |

## Safety

- On every launch the tool snapshots your INI to `CalibToolBackups\` next to it
  (newest 30 kept).
- The restore menu splices back **only the calibration section** — graphics/audio
  settings are never touched by a restore.
- Saves are refused while Geronimo is running, and a `GameUserSettings.pre-GodotTool.ini`
  backup is written before the first save of each session.
- Only the selected gun's `GunTransforms` line is modified; every other byte of the
  file is preserved (verified by round-trip test).

## Building / hacking on it

The whole tool is one commented GDScript file: [`main.gd`](main.gd).

1. Install [Godot 4.6.3](https://godotengine.org/download) (free, ~50 MB).
2. Open `project.godot`, edit, **F5** to run.
3. Headless tests (no VR needed):
   ```
   godot --headless --path . --script test_ini.gd      # INI parsing
   godot --headless --path . --script test_save.gd     # save round-trip (scratch copy)
   godot --headless --path . --script test_restore.gd  # backup splice/restore
   ```
4. Export exe: `godot --headless --path . --export-release "Windows Desktop" dist/GeronimoCalibTool.exe`
   (install export templates when prompted).

Known rough edges / good first contributions: primitive-based rifle and optic models;
`PITCH_SIGN` constant if pitch feels inverted on some setups; per-gun base poses inside
Geronimo differ slightly so an in-game verify pass is still recommended; more optic
models; Index vs Touch button mapping feedback.

## License & disclaimer

MIT — see [LICENSE](LICENSE). Not affiliated with the GERONIMO developers. The tool
modifies only the settings INI in your own user profile, never game files.
