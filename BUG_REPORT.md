# GERONIMO — Gunstock calibration does not persist the off-hand (translation) axes

## Summary
When calibrating a rifle's gunstock, the **left/right and up/down translation** the player
sets is **not written to the saved calibration**. Only the **forward/aft distance and pitch**
survive. The gun visibly snaps back to a default pose the instant the save chord (both triggers)
is pulled, and the calibration does not carry into normal gameplay. This affects all users who
rely on a physical VR gunstock.

## Environment
- Retail Steam build, UE 5.7, Windows.
- Physical VR gunstock (both controllers mounted), `VRGripMode=Oculus`.
- `bUseVirtualStock=False`, `bUseGunSmoothing=False` (i.e. reproduces with those OFF).

## Where the calibration is stored
`%LOCALAPPDATA%\Geronimo\Saved\Config\Windows\GameUserSettings.ini`, section
`[DarkWeapons.GunstockCalibration]`. Two index-parallel arrays plus an optional universal key:
```
GunClassPaths=<firearm BP class>            (one line per gun)
GunTransforms=Lx,Ly,Lz|Rp,Ry,Rr|Sx,Sy,Sz    (Translation | Rotation(Euler) | Scale)
UniversalGunClassPath=<firearm BP class>     (optional)
```
Translation is **[Left/Right, Up, Forward]** in cm; Rotation is **[Pitch, Yaw, Roll]** in degrees.

## Steps to reproduce
1. At the gun-customisation station (vice), open gunstock calibration for any rifle.
2. Pick the rifle up one-handed (pistol grip), shoulder it, get a sight picture.
3. Use the **off-hand thumbstick** to set left/right + up/down; use the **main-hand thumbstick**
   to set pitch + forward/aft. Align it perfectly in the preview.
4. Pull both triggers to save.

**Observed:** the gun snaps down/back to a default pose; on next pickup and in gameplay the
left/right + up/down offset is gone (reads ~0). Forward distance and pitch are retained.
**Expected:** the pose shown in the preview at the moment of save is exactly what persists.

## Evidence (real saved rows after in-game saves)
```
CQBR:  GunTransforms=0.000000,0.000000,12.384946 | 0.000000,... | 1,1,1
URGI:  GunTransforms=-0.048936,0.000000,16.537832 | 2.198445,... | 1,1,1
```
Note the **first two translation components collapse to 0.000000** (off-hand axes) while the
3rd (forward) and pitch carry the player's real adjustment. Hand-writing non-zero values into
those first two components **does** apply correctly in gameplay and persists across sessions —
so the read/apply path is fine; only the **save** drops these axes.

## Root-cause analysis (reverse-engineered from the shipping build's reflection data)
The relevant symbols in the `DarkWeapons` module:
`SaveGunstockCalibration`, `SetGunstockCalibrationForGun`, `CurrentGunstockCalibration`,
`GunstockCalibrationPreviewOffset`, `PreviewAxisX`, `PreviewAxisY`,
`SetGunstockCalibrationPreviewOffset`, `ClearGunstockCalibrationPreviewOffset`,
`SecondaryAimPoint`, `SecondaryAimAxis`, `bGunstockCalibrationModeActive`.

Two interacting problems:

1. **Preview offset is never folded into the commit.** The off-hand thumbstick drives
   `GunstockCalibrationPreviewOffset` (`PreviewAxisX/Y`) and is applied only to the *displayed*
   gun. `SaveGunstockCalibration` appears to persist `CurrentGunstockCalibration` **without**
   composing in that preview offset — so the two off-hand axes store their 0 defaults. Classic
   "what you preview isn't what you save."

2. **The only path that would commit translation also corrupts orientation.** Registering the
   off-hand as a second grip (to make its input "count") triggers the two-handed
   `SecondaryAimPoint` re-aim, which rotates the gun and destroys the just-set pitch. So a
   one-handed save keeps pitch but drops translation; a two-handed save can carry translation
   but wrecks pitch. The player can never capture both in one save.

## Suggested fix (small / surgical)
- In `SaveGunstockCalibration`, compose the preview offset before storing:
  `Final = CurrentGunstockCalibration ∘ PreviewOffset(PreviewAxisX, PreviewAxisY)` then
  `SetGunstockCalibrationForGun(Gun, Final)`. (Likely 1–3 lines.)
- While `bGunstockCalibrationModeActive`, suppress the `SecondaryAimPoint`/`SecondaryAimAxis`
  re-aim so the off-hand can register for input without rotating the gun during calibration.
- Defer `ClearGunstockCalibrationPreviewOffset` until **after** the commit succeeds.

## Secondary issues noticed
- **Universal override is sticky and silent.** `UniversalGunClassPath` makes one gun's
  calibration apply to *every* gun; it is easy to enable by accident from the menu and there is
  no clear indication it is active. Recommend an explicit on/off state and a per-gun fallback.
- **No save confirmation.** There is no clear "Saved ✓" feedback, so a failed save looks the
  same as a successful one.

## Impact
High for the physical-gunstock audience: calibration is effectively unusable for translation,
which is the whole point of matching the virtual rifle to a real stock.
