GERONIMO EXTERNAL GUNSTOCK CALIBRATION TOOL  (community fix, v1.0)
===================================================================

WHAT THIS IS
------------
GERONIMO's in-game gunstock calibration has a save bug: the vertical / left-right
position you set with the off-hand thumbstick is never written to disk (the game
saves 0 for those axes), which is why the gun "snaps back" when you pull both
triggers and never carries into gameplay. The forward distance and pitch DO save.

This tool calibrates OUTSIDE the game, in a simple SteamVR scene, and writes the
result directly into the same file the game reads:
  %LOCALAPPDATA%\Geronimo\Saved\Config\Windows\GameUserSettings.ini
  section [DarkWeapons.GunstockCalibration]
The game's read path works perfectly, so values saved here apply in-game and stick.

Not affiliated with the GERONIMO developers. No game files are modified — only the
settings INI in your user profile, and a backup copy is made before the first save.

REQUIREMENTS
------------
- Windows PC + SteamVR (any OpenXR headset)
- GERONIMO installed and run at least once
- GERONIMO must be CLOSED while you calibrate (the tool enforces this; the game
  rewrites the INI on exit and would overwrite your work)

HOW TO USE  (no in-game calibration needed - ever)
----------
You never need to touch Geronimo's own calibration menu. Everything is done here.

1. Close Geronimo. Start SteamVR. Run GeronimoCalibTool.exe. Put on the headset.
2. A generic rifle hangs on your RIGHT controller; a panel above your LEFT hand
   shows the selected gun and its live numbers. Guns are read from YOUR save file.
3. ONE-TIME ANCHOR (first use): shoulder your physical stock, press LEFT X
   (BASE-ADJUST mode), use the sticks to align the virtual rifle's sights to your
   natural eye line - exactly like checking the fit of a real rifle. Pull BOTH
   TRIGGERS to store it, press LEFT X again to exit. Lining up the rear peep and
   front post while shouldered is what sets the pitch and height correctly; your
   body does the aiming, same as a real gun.
4. Calibrate: select a gun (A/B), shoulder your stock, adjust with the sticks
   until the sight picture is right, pull BOTH TRIGGERS. Big green SAVED = done.
5. Launch Geronimo and verify. Small residual error? Close the game, nudge in the
   tool (hold GRIP for fine adjust), save again. Usually 1 trim pass is enough.

TIP: numbers are a property of your STOCK + CONTROLLER TYPE, not your body. If
someone with the same stock and controllers shares their calibration section, you
can paste it into your INI (game closed) and skip calibrating entirely.

CONTROLS
--------
  LEFT stick   : Up/Down + Left/Right
  RIGHT stick  : Forward/Back + Pitch
  hold GRIP    : fine adjustment (15% speed)
  RIGHT A / B  : next / previous gun - ALL 23 game guns are available (rifles,
                 SMGs, pistols, shotgun, LMG, bolt guns), not just ones you've
                 calibrated before. New guns start from your best existing
                 calibration and show "NEW" until you save them.
  RIGHT STICK CLICK : cycle optic (remembered per gun) - rifles: iron sights /
                      EOTech EXPS3 / red dot at the game's four mount heights
                      (LOW 1.42" / TALL 1.93" / UNITY 2.26" / GBRS 2.91") / ACOG.
                      Pistols: irons / slide dot (SRO).
  LEFT STICK CLICK  : backup RESTORE menu (stick up/down = select,
                      RIGHT A = restore, RIGHT B = cancel)
  LEFT X       : toggle BASE-ADJUST (anchor) mode
  LEFT Y       : revert current gun to last saved values
  BOTH TRIGGERS: SAVE

BACKUPS
-------
Every launch, the tool snapshots your INI into:
  %LOCALAPPDATA%\Geronimo\Saved\Config\Windows\CalibToolBackups\
(newest 30 kept). The RESTORE menu (left stick click) splices a backup's
CALIBRATION SECTION back into your current file - your graphics/audio settings
are never touched by a restore. Experiment freely; you can always walk it back.

A NOTE ON "PATH UNVERIFIED" GUNS
--------------------------------
Guns you've never calibrated in-game are added using best-guess internal class
paths (the game's files are compressed, so they can't all be confirmed from
outside). If a gun you calibrated here doesn't respond in-game: open the game's
own calibration on that gun once, pull both triggers (ignore the snap-back), and
quit. The game writes the gun's TRUE path; this tool detects it on next launch,
adopts it automatically, and keeps your saved values. Save that gun once more in
the tool and it's fixed permanently.

IMPORTANT
---------
- NEVER use Geronimo's own gunstock calibration menu after calibrating a gun here —
  the in-game save bug will zero your vertical again. If it happens, recalibrate
  here or restore the backup:
  GameUserSettings.pre-GodotTool.ini  (written next to the INI on first save)
- Avoid the in-game "set as universal" option; it forces one gun's calibration
  onto every gun (that's the "all guns in the same wrong spot" bug).
- The INI transform format, for the curious:
  GunTransforms = Up, LeftRight, Forward | Pitch, Yaw, Roll | Scale  (cm / degrees,
  positive = up / right / forward).

SOURCE CODE / IMPROVING THIS TOOL
---------------------------------
The full source ships in the source\ folder of this package (MIT licensed - see
LICENSE.txt). It is one GDScript file. To modify it:
  1. Download Godot 4.6.3 (free, ~50 MB): https://godotengine.org/download
  2. Open source\project.godot in the editor, edit main.gd, press F5 to test.
  3. To rebuild the exe: Editor > Export > Windows Desktop (install the export
     templates when prompted), or run headless:
     godot --headless --path source --export-release "Windows Desktop" GeronimoCalibTool.exe
Headless tests (no VR needed): test_ini.gd, test_save.gd, test_restore.gd, e.g.
     godot --headless --path source --script test_save.gd
Known rough edges worth improving: the rifle/optic models are primitive-based
approximations; PITCH_SIGN in main.gd flips pitch if your setup feels inverted;
per-gun base poses inside Geronimo differ slightly, so one verify pass in-game
is still recommended after calibrating. Share improvements back to the thread!

