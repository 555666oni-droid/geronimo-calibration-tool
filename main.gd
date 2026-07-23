extends Node3D
# ============================================================================
# GERONIMO external gunstock calibration tool
#
# Runs in SteamVR (Geronimo must be CLOSED). Shows a generic rifle attached to
# your RIGHT controller. Adjust the same four values Geronimo stores, with live
# numbers, then pull BOTH TRIGGERS to write them to Geronimo's INI (with backup
# and a big SAVED confirmation).
#
# INI format (proven by experiment 2026-07-22):
#   GunTransforms = Up, LeftRight, Forward | Pitch, Yaw, Roll | Scale
#   (cm / degrees, positive = up / right / forward)
#
# CONTROLS
#   LEFT stick   Y = Up/Down          X = Left/Right
#   RIGHT stick  Y = Forward/Back     X = Pitch
#   hold either GRIP                  = fine adjust (15% speed)
#   RIGHT A / B                       = next / previous gun
#   RIGHT STICK CLICK                 = cycle optic (irons / EXPS3 / T-2 Hydra)
#   LEFT STICK CLICK                  = backup RESTORE menu (stick up/down =
#                                       select, RIGHT A = restore, B = cancel)
#   LEFT  X                           = toggle BASE-ADJUST (anchor) mode
#   LEFT  Y                           = revert current gun to last saved values
#
# The tool snapshots the INI into CalibToolBackups\ (next to the INI) on every
# launch; the restore menu splices a backup's calibration section back in
# (graphics/audio settings in the current file are left untouched).
#   BOTH TRIGGERS                     = SAVE (writes INI; in BASE-ADJUST mode
#                                       saves the anchor pose instead)
# ============================================================================

const INI_REL := "Geronimo/Saved/Config/Windows/GameUserSettings.ini"
const GAME_EXE := "Geronimo-Win64-Shipping.exe"
const BASE_CFG := "user://basepose.cfg"
const BACKUP_DIRNAME := "CalibToolBackups"
const MAX_BACKUPS := 30
const CALIB_SECTION := "[DarkWeapons.GunstockCalibration]"

const MOVE_CMPS := 6.0        # cm per second at full stick deflection
const PITCH_DPS := 12.0       # degrees per second
const FINE := 0.15            # speed multiplier while a grip is held
const DEADZONE := 0.15
const TRIG_ON := 0.7
const TRIG_OFF := 0.3
const PITCH_SIGN := 1.0       # flip to -1.0 if pitch direction mismatches Geronimo

var xr: XRInterface
var left: XRController3D
var right: XRController3D
var rifle: Node3D
var hud: Label3D
var board_status: Label3D

var ini_path := ""
var eol := "\r\n"
var gun_names: Array[String] = []
var offsets: Array = []          # [{up, lr, fwd, pitch}] parallel with gun_names
var saved_vals: Array = []       # last loaded/saved values (dirty marker)
var cur := 0

const OPTIC_NAMES := ["IRON SIGHTS", "EOTECH EXPS3", "T-2 on GBRS HYDRA"]
var optic_choice: Array = []     # per-gun optic index, parallel with gun_names
var irons_node: Node3D
var exps3_node: Node3D
var t2_node: Node3D

var base_pos := Vector3(0.0, -0.02, 0.0)
var base_pitch := 0.0
var anchor_mode := false
var save_latch := false
var backed_up := false
var flash_t := 0.0
var flash_msg := ""

var restore_mode := false
var backup_files: Array[String] = []
var restore_sel := 0
var nav_cd := 0.0


func _ready() -> void:
	_build_environment()
	_build_xr_rig()
	_build_rifle()
	_build_hud()
	_load_base_pose()
	if _load_ini():
		_backup_on_launch()
	else:
		_flash("INI NOT FOUND - is Geronimo installed?", 10.0)
	_start_xr()


# ---------------------------------------------------------------- XR startup
func _start_xr() -> void:
	xr = XRServer.find_interface("OpenXR")
	if xr and xr.initialize():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	else:
		# Desktop fallback so the tool still opens without SteamVR.
		var cam := Camera3D.new()
		cam.position = Vector3(0.0, 1.7, 1.2)
		add_child(cam)
		cam.look_at(Vector3(0.0, 1.2, -1.0))
		var cl := CanvasLayer.new()
		add_child(cl)
		var lbl := Label.new()
		lbl.text = "SteamVR / OpenXR not detected.\nStart SteamVR, then relaunch this tool."
		lbl.position = Vector2(40, 40)
		cl.add_child(lbl)


func _build_xr_rig() -> void:
	var origin := XROrigin3D.new()
	add_child(origin)
	var cam := XRCamera3D.new()
	origin.add_child(cam)

	left = XRController3D.new()
	left.tracker = "left_hand"
	origin.add_child(left)
	left.button_pressed.connect(_on_left_button)

	right = XRController3D.new()
	right.tracker = "right_hand"
	origin.add_child(right)
	right.button_pressed.connect(_on_right_button)

	for c in [left, right]:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.03, 0.03, 0.10)
		m.mesh = box
		m.material_override = _mat(Color(0.25, 0.28, 0.33))
		c.add_child(m)


# ---------------------------------------------------------------- environment
func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(col)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	add_child(sun)

	# floor
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20.0, 20.0)
	fl.mesh = pm
	fl.material_override = _mat(Color(0.35, 0.37, 0.35))
	add_child(fl)

	# target board 5 m ahead with aiming marks at three heights
	_add_box(self, Vector3(1.2, 2.2, 0.05), Vector3(0.0, 1.1, -5.0), Color(0.82, 0.78, 0.66))
	for h in [1.2, 1.5, 1.7]:
		var t := Label3D.new()
		t.text = "-◎-"
		t.font_size = 160
		t.pixel_size = 0.001
		t.modulate = Color(0.75, 0.1, 0.1)
		t.position = Vector3(0.0, h, -4.97)
		add_child(t)

	# status + instruction text on the board
	board_status = Label3D.new()
	board_status.font_size = 220
	board_status.pixel_size = 0.001
	board_status.position = Vector3(0.0, 2.35, -4.95)
	board_status.modulate = Color(0.2, 1.0, 0.3)
	add_child(board_status)

	var help := Label3D.new()
	help.font_size = 72
	help.pixel_size = 0.001
	help.modulate = Color(0.1, 0.1, 0.12)
	help.position = Vector3(0.0, 0.55, -4.95)
	help.text = "LEFT stick: Up/Down + Left/Right      RIGHT stick: Fwd/Back + Pitch
GRIP = fine   A/B = change gun   LEFT-X = base mode   LEFT-Y = revert
BOTH TRIGGERS = SAVE to Geronimo INI"
	add_child(help)


# ---------------------------------------------------------------- rifle model
func _build_rifle() -> void:
	rifle = Node3D.new()
	right.add_child(rifle)

	var dark := Color(0.13, 0.13, 0.14)
	var mid := Color(0.2, 0.2, 0.22)
	# origin = pistol grip. -Z is forward.
	_add_box(rifle, Vector3(0.045, 0.060, 0.30), Vector3(0.0, 0.070, -0.050), mid)      # receiver
	_add_box(rifle, Vector3(0.040, 0.050, 0.22), Vector3(0.0, 0.080, -0.310), dark)     # handguard
	_add_box(rifle, Vector3(0.035, 0.090, 0.050), Vector3(0.0, -0.005, 0.010), dark)    # grip
	_add_box(rifle, Vector3(0.040, 0.050, 0.20), Vector3(0.0, 0.055, 0.150), dark)      # stock
	_add_box(rifle, Vector3(0.045, 0.110, 0.020), Vector3(0.0, 0.045, 0.255), mid)      # buttpad
	_add_box(rifle, Vector3(0.035, 0.110, 0.060), Vector3(0.0, -0.010, -0.110), mid)    # magazine

	var barrel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.011
	cyl.bottom_radius = 0.011
	cyl.height = 0.30
	barrel.mesh = cyl
	barrel.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	barrel.position = Vector3(0.0, 0.085, -0.500)
	barrel.material_override = _mat(dark)
	rifle.add_child(barrel)

	irons_node = Node3D.new()
	rifle.add_child(irons_node)
	# rear peep ring
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.006
	tor.outer_radius = 0.011
	ring.mesh = tor
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	ring.position = Vector3(0.0, 0.125, 0.030)
	ring.material_override = _mat(Color.BLACK)
	irons_node.add_child(ring)
	# front post (bright tip for easy sight picture)
	_add_box(irons_node, Vector3(0.004, 0.018, 0.004), Vector3(0.0, 0.122, -0.640), Color(1.0, 0.45, 0.05))
	_add_box(irons_node, Vector3(0.020, 0.014, 0.010), Vector3(0.0, 0.105, -0.640), dark)  # front sight base

	_build_exps3()
	_build_t2_hydra()
	_apply_optic()


func _emat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _build_exps3() -> void:
	# EOTech EXPS3: boxy holographic sight on the receiver rail.
	# Rail top y=0.100; optical centre ~36 mm above rail -> y ~0.136.
	exps3_node = Node3D.new()
	rifle.add_child(exps3_node)
	var body := Color(0.10, 0.10, 0.11)
	_add_box(exps3_node, Vector3(0.048, 0.016, 0.098), Vector3(0.0, 0.108, -0.020), body)  # QD mount base
	_add_box(exps3_node, Vector3(0.052, 0.040, 0.062), Vector3(0.0, 0.134, 0.000), body)   # rear body / hood
	# forward window frame: four thin bars forming the rectangle
	var wz := -0.052
	_add_box(exps3_node, Vector3(0.050, 0.005, 0.006), Vector3(0.0, 0.156, wz), body)      # top bar
	_add_box(exps3_node, Vector3(0.050, 0.005, 0.006), Vector3(0.0, 0.116, wz), body)      # bottom bar
	_add_box(exps3_node, Vector3(0.005, 0.045, 0.006), Vector3(-0.024, 0.136, wz), body)   # left bar
	_add_box(exps3_node, Vector3(0.005, 0.045, 0.006), Vector3(0.024, 0.136, wz), body)    # right bar
	# reticle: 68 MOA ring + centre dot, red, floating in the window plane
	var ret := MeshInstance3D.new()
	var rt := TorusMesh.new()
	rt.inner_radius = 0.0085
	rt.outer_radius = 0.0100
	ret.mesh = rt
	ret.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	ret.position = Vector3(0.0, 0.136, wz)
	ret.material_override = _emat(Color(1.0, 0.12, 0.08))
	exps3_node.add_child(ret)
	var dot := _add_box(exps3_node, Vector3(0.0018, 0.0018, 0.001), Vector3(0.0, 0.136, wz), Color(1.0, 0.12, 0.08))
	dot.material_override = _emat(Color(1.0, 0.12, 0.08))


func _build_t2_hydra() -> void:
	# Aimpoint Micro T-2 on a GBRS Hydra 2.91" mount.
	# Rail top y=0.100; 2.91" = 74 mm to optical centre -> y ~0.174 (head-up height).
	t2_node = Node3D.new()
	rifle.add_child(t2_node)
	var mount_col := Color(0.35, 0.30, 0.22)   # FDE-ish
	var body := Color(0.10, 0.10, 0.11)
	_add_box(t2_node, Vector3(0.030, 0.014, 0.070), Vector3(0.0, 0.107, -0.020), mount_col)  # mount base
	_add_box(t2_node, Vector3(0.024, 0.052, 0.034), Vector3(0.0, 0.140, -0.020), mount_col)  # riser tower
	var tube := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.0125
	cy.bottom_radius = 0.0125
	cy.height = 0.062
	tube.mesh = cy
	tube.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	tube.position = Vector3(0.0, 0.174, -0.020)
	tube.material_override = _mat(body)
	t2_node.add_child(tube)
	for zz in [-0.052, 0.012]:                                          # objective / ocular bells
		var bell := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.0145
		bc.bottom_radius = 0.0145
		bc.height = 0.010
		bell.mesh = bc
		bell.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		bell.position = Vector3(0.0, 0.174, zz)
		bell.material_override = _mat(body)
		t2_node.add_child(bell)
	# 2 MOA red dot floating mid-tube
	var dot := _add_box(t2_node, Vector3(0.0018, 0.0018, 0.001), Vector3(0.0, 0.174, -0.020), Color(1.0, 0.12, 0.08))
	dot.material_override = _emat(Color(1.0, 0.12, 0.08))


func _apply_optic() -> void:
	var idx := 0
	if not optic_choice.is_empty() and cur < optic_choice.size():
		idx = optic_choice[cur]
	if irons_node:
		irons_node.visible = idx == 0
	if exps3_node:
		exps3_node.visible = idx == 1
	if t2_node:
		t2_node.visible = idx == 2


func _build_hud() -> void:
	hud = Label3D.new()
	hud.font_size = 56
	hud.pixel_size = 0.0004
	hud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hud.no_depth_test = true
	hud.position = Vector3(0.0, 0.09, 0.02)
	left.add_child(hud)


# ---------------------------------------------------------------- INI handling
func _load_ini() -> bool:
	var lad := OS.get_environment("LOCALAPPDATA")
	if lad == "":
		return false
	ini_path = lad.replace("\\", "/") + "/" + INI_REL
	if not FileAccess.file_exists(ini_path):
		return false
	var txt := FileAccess.get_file_as_string(ini_path)
	eol = "\r\n" if txt.contains("\r\n") else "\n"
	gun_names.clear()
	offsets.clear()
	for raw in txt.split("\n"):
		var l := raw.strip_edges()
		if l.begins_with("GunClassPaths="):
			var n := l.get_slice("=", 1).get_file().get_slice(".", 0)
			gun_names.append(n.replace("Firearm_Rifle_", ""))
		elif l.begins_with("GunTransforms="):
			var v := l.get_slice("=", 1)
			var t := v.get_slice("|", 0).split(",")
			var r := v.get_slice("|", 1).split(",")
			if t.size() >= 3 and r.size() >= 1:
				offsets.append({
					"up": t[0].to_float(), "lr": t[1].to_float(),
					"fwd": t[2].to_float(), "pitch": r[0].to_float()
				})
	if gun_names.is_empty() or gun_names.size() != offsets.size():
		return false
	saved_vals = offsets.duplicate(true)
	for i in gun_names.size():
		if gun_names[i] == "M4A1_URGI":
			cur = i
	# per-gun optic choice, restored from the tool's config
	var cfg := ConfigFile.new()
	cfg.load(BASE_CFG)
	optic_choice.clear()
	for i in gun_names.size():
		optic_choice.append(int(cfg.get_value("optics", gun_names[i], 0)))
	_apply_optic()
	return true


func _save_optics() -> void:
	var cfg := ConfigFile.new()
	cfg.load(BASE_CFG)
	for i in gun_names.size():
		cfg.set_value("optics", gun_names[i], optic_choice[i])
	cfg.save(BASE_CFG)


# ---------------------------------------------------------------- backups
func _backup_dir() -> String:
	return ini_path.get_base_dir() + "/" + BACKUP_DIRNAME


func _backup_on_launch() -> void:
	if ini_path == "" or not FileAccess.file_exists(ini_path):
		return
	DirAccess.make_dir_recursive_absolute(_backup_dir())
	var ts := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	DirAccess.copy_absolute(ini_path, _backup_dir() + "/GameUserSettings-%s.ini" % ts)
	_prune_backups()


func _prune_backups() -> void:
	var names := _list_backups()
	while names.size() > MAX_BACKUPS:
		var oldest: String = names.pop_back()      # list is newest-first
		DirAccess.remove_absolute(_backup_dir() + "/" + oldest)


func _list_backups() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(_backup_dir())
	if d == null:
		return out
	for f in d.get_files():
		if f.begins_with("GameUserSettings-") and f.ends_with(".ini"):
			out.append(f)
	out.sort()
	out.reverse()                                  # newest first (timestamp names)
	return out


func _extract_calib_section(lines: Array) -> Array:
	# returns [start, end) line indices of the calibration section, or [-1, -1]
	var start := -1
	for i in lines.size():
		if String(lines[i]).strip_edges() == CALIB_SECTION:
			start = i
			break
	if start == -1:
		return [-1, -1]
	var end := lines.size()
	for j in range(start + 1, lines.size()):
		var l := String(lines[j]).strip_edges()
		if l.begins_with("[") and l != CALIB_SECTION:
			end = j
			break
	return [start, end]


func _splice_calib_from_backup(backup_name: String) -> bool:
	var btxt := FileAccess.get_file_as_string(_backup_dir() + "/" + backup_name)
	var ctxt := FileAccess.get_file_as_string(ini_path)
	if btxt == "" or ctxt == "":
		return false
	var blines := Array(btxt.split("\n")).map(func(s): return String(s).trim_suffix("\r"))
	var clines := Array(ctxt.split("\n")).map(func(s): return String(s).trim_suffix("\r"))
	var br := _extract_calib_section(blines)
	if br[0] == -1:
		return false
	var section := blines.slice(br[0], br[1])
	var cr := _extract_calib_section(clines)
	var merged: Array
	if cr[0] == -1:
		merged = clines + section                  # section absent: append it
	else:
		merged = clines.slice(0, cr[0]) + section + clines.slice(cr[1])
	var f := FileAccess.open(ini_path, FileAccess.WRITE)
	if f == null:
		return false
	var out := ""
	for i in merged.size():
		out += String(merged[i])
		if i < merged.size() - 1:
			out += eol
	f.store_string(out)
	f.close()
	return true


func _do_restore() -> void:
	if _game_running():
		_flash("GERONIMO IS RUNNING - close it first!", 5.0, Color(1.0, 0.25, 0.2))
		return
	if backup_files.is_empty():
		return
	var name := backup_files[restore_sel]
	if _splice_calib_from_backup(name):
		_load_ini()                                # refresh tool state from restored file
		restore_mode = false
		_flash("RESTORED  " + name.trim_prefix("GameUserSettings-").trim_suffix(".ini"), 4.0)
	else:
		_flash("RESTORE FAILED - backup unreadable", 5.0, Color(1.0, 0.25, 0.2))


func _game_running() -> bool:
	var out: Array = []
	OS.execute("tasklist", ["/FI", "IMAGENAME eq " + GAME_EXE, "/FO", "CSV", "/NH"], out)
	for line in out:
		if String(line).contains(GAME_EXE.get_basename()):
			return true
	return false


func _save_ini() -> void:
	if ini_path == "" or offsets.is_empty():
		_flash("NOTHING LOADED - cannot save", 4.0, Color(1.0, 0.25, 0.2))
		return
	if _game_running():
		_flash("GERONIMO IS RUNNING - close it first!", 5.0, Color(1.0, 0.25, 0.2))
		return
	if not backed_up:
		DirAccess.copy_absolute(ini_path, ini_path.get_base_dir() + "/GameUserSettings.pre-GodotTool.ini")
		backed_up = true
	var txt := FileAccess.get_file_as_string(ini_path)
	var lines := txt.split("\n")
	var n := -1
	for i in lines.size():
		if lines[i].strip_edges().begins_with("GunTransforms="):
			n += 1
			if n == cur:
				var o: Dictionary = offsets[cur]
				lines[i] = "GunTransforms=%.6f,%.6f,%.6f|%.6f,0.000000,0.000000|1.000000,1.000000,1.000000" \
					% [o["up"], o["lr"], o["fwd"], o["pitch"]]
				break
	if n != cur:
		_flash("ROW NOT FOUND - save aborted", 5.0, Color(1.0, 0.25, 0.2))
		return
	var joined := ""
	for i in lines.size():
		joined += lines[i].trim_suffix("\r")
		if i < lines.size() - 1:
			joined += eol
	var f := FileAccess.open(ini_path, FileAccess.WRITE)
	if f == null:
		_flash("WRITE FAILED - file locked?", 5.0, Color(1.0, 0.25, 0.2))
		return
	f.store_string(joined)
	f.close()
	saved_vals[cur] = offsets[cur].duplicate()
	_flash("SAVED  " + gun_names[cur], 3.0)


# ---------------------------------------------------------------- base pose
func _load_base_pose() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(BASE_CFG) == OK:
		base_pos = cfg.get_value("base", "pos", base_pos)
		base_pitch = cfg.get_value("base", "pitch", base_pitch)


func _save_base_pose() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("base", "pos", base_pos)
	cfg.set_value("base", "pitch", base_pitch)
	cfg.save(BASE_CFG)
	_flash("BASE POSE SAVED", 3.0)


# ---------------------------------------------------------------- input
func _on_right_button(bname: String) -> void:
	if restore_mode:
		if bname == "ax_button":
			_do_restore()
		elif bname == "by_button":
			restore_mode = false
			_flash("RESTORE CANCELLED", 1.5, Color(1.0, 0.8, 0.2))
		return
	if bname == "ax_button":
		_switch_gun(1)
	elif bname == "by_button":
		_switch_gun(-1)
	elif bname == "primary_click":
		if not optic_choice.is_empty():
			optic_choice[cur] = (optic_choice[cur] + 1) % OPTIC_NAMES.size()
			_apply_optic()
			_save_optics()
			_flash(OPTIC_NAMES[optic_choice[cur]], 1.5, Color(0.4, 0.7, 1.0))


func _on_left_button(bname: String) -> void:
	if bname == "primary_click":
		restore_mode = not restore_mode
		if restore_mode:
			anchor_mode = false
			backup_files = _list_backups()
			restore_sel = 0
			if backup_files.is_empty():
				restore_mode = false
				_flash("NO BACKUPS YET", 2.0, Color(1.0, 0.8, 0.2))
		return
	if restore_mode:
		return
	if bname == "ax_button":
		anchor_mode = not anchor_mode
		_flash("BASE-ADJUST %s" % ("ON" if anchor_mode else "OFF"), 2.0, Color(1.0, 0.8, 0.2))
	elif bname == "by_button":
		if not offsets.is_empty():
			offsets[cur] = saved_vals[cur].duplicate()
			_flash("REVERTED " + gun_names[cur], 2.0, Color(1.0, 0.8, 0.2))


func _switch_gun(dir: int) -> void:
	if gun_names.is_empty():
		return
	cur = (cur + dir + gun_names.size()) % gun_names.size()
	_apply_optic()
	_flash(gun_names[cur], 1.5, Color(0.4, 0.7, 1.0))


func _stick(c: XRController3D) -> Vector2:
	if c == null:
		return Vector2.ZERO
	var v: Vector2 = c.get_vector2("primary")
	if v.length() < DEADZONE:
		return Vector2.ZERO
	return v


func _process(delta: float) -> void:
	if flash_t > 0.0:
		flash_t -= delta
		if flash_t <= 0.0:
			flash_msg = ""

	var speed := 1.0
	if left.get_float("grip") > 0.5 or right.get_float("grip") > 0.5:
		speed = FINE
	var ls := _stick(left)
	var rs := _stick(right)

	if restore_mode:
		nav_cd -= delta
		if absf(ls.y) > 0.6 and nav_cd <= 0.0:
			restore_sel = clampi(restore_sel + (1 if ls.y < 0.0 else -1), 0, backup_files.size() - 1)
			nav_cd = 0.25
		_update_hud()
		return

	if anchor_mode:
		base_pos.x += ls.x * MOVE_CMPS * 0.01 * speed * delta
		base_pos.y += ls.y * MOVE_CMPS * 0.01 * speed * delta
		base_pos.z += -rs.y * MOVE_CMPS * 0.01 * speed * delta
		base_pitch += rs.x * PITCH_DPS * speed * delta
	elif not offsets.is_empty():
		var o: Dictionary = offsets[cur]
		o["lr"] += ls.x * MOVE_CMPS * speed * delta
		o["up"] += ls.y * MOVE_CMPS * speed * delta
		o["fwd"] += rs.y * MOVE_CMPS * speed * delta
		o["pitch"] += rs.x * PITCH_DPS * speed * delta

	# apply pose: INI [up, lr, fwd] cm -> Godot metres (X right, Y up, -Z fwd)
	if not offsets.is_empty():
		var o2: Dictionary = offsets[cur]
		rifle.position = base_pos + Vector3(o2["lr"], o2["up"], -o2["fwd"]) * 0.01
		rifle.rotation_degrees = Vector3(base_pitch + PITCH_SIGN * o2["pitch"], 0.0, 0.0)

	# save chord
	var lt := left.get_float("trigger")
	var rt := right.get_float("trigger")
	if lt > TRIG_ON and rt > TRIG_ON:
		if not save_latch:
			save_latch = true
			if anchor_mode:
				_save_base_pose()
			else:
				_save_ini()
	elif lt < TRIG_OFF and rt < TRIG_OFF:
		save_latch = false

	_update_hud()


# ---------------------------------------------------------------- HUD
func _flash(msg: String, secs: float, col: Color = Color(0.2, 1.0, 0.3)) -> void:
	flash_msg = msg
	flash_t = secs
	if board_status:
		board_status.modulate = col


func _update_hud() -> void:
	if board_status:
		board_status.text = flash_msg
	if hud == null:
		return
	if restore_mode:
		var t := "RESTORE BACKUP  (stick=select  A=restore  B=cancel)\n"
		var lo: int = clampi(restore_sel - 3, 0, maxi(0, backup_files.size() - 7))
		for i in range(lo, mini(lo + 7, backup_files.size())):
			var nm := backup_files[i].trim_prefix("GameUserSettings-").trim_suffix(".ini")
			t += ("> %s\n" if i == restore_sel else "  %s\n") % nm
		hud.text = t
		hud.modulate = Color(0.5, 0.85, 1.0)
		return
	if offsets.is_empty():
		hud.text = "NO DATA - Geronimo INI not loaded"
		return
	var o: Dictionary = offsets[cur]
	var s: Dictionary = saved_vals[cur]
	var dirty := absf(o["up"] - s["up"]) > 0.005 or absf(o["lr"] - s["lr"]) > 0.005 \
		or absf(o["fwd"] - s["fwd"]) > 0.005 or absf(o["pitch"] - s["pitch"]) > 0.005
	var optic_name: String = OPTIC_NAMES[optic_choice[cur]] if cur < optic_choice.size() else ""
	hud.text = "%s  (%d/%d)%s
UP    %+7.2f cm
LR    %+7.2f cm
FWD   %+7.2f cm
PITCH %+7.2f deg
%s
%s" % [
		gun_names[cur], cur + 1, gun_names.size(),
		"  *UNSAVED*" if dirty else "",
		o["up"], o["lr"], o["fwd"], o["pitch"],
		optic_name,
		"MODE: BASE-ADJUST" if anchor_mode else ""
	]
	hud.modulate = Color(1.0, 0.85, 0.4) if dirty else Color.WHITE
