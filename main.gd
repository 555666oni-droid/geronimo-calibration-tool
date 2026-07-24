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
#   RIGHT A / B                       = next / previous gun (all 23 game guns)
#   RIGHT STICK CLICK                 = cycle optic: rifles get irons/EXPS3/dot at
#                                       LOW-TALL-UNITY-GBRS mount heights/ACOG;
#                                       pistols get irons/slide dot (SRO)
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
var gun_paths: Array[String] = []  # full class paths, parallel with gun_names
var gun_in_ini: Array[bool] = []   # false = not yet written to the game's INI
var offsets: Array = []          # [{up, lr, fwd, pitch}] parallel with gun_names
var saved_vals: Array = []       # last loaded/saved values (dirty marker)
var cur := 0

# Full weapon roster (from the game files). "verified" paths were confirmed from a
# real INI written by the game; the rest are best-guess candidates (the game's
# content store is compressed, so they can't be confirmed statically). The tool
# merges by CLASS NAME, so if the game ever writes a gun's true path (a single
# both-triggers pull in its in-game calibration is enough), that path wins
# automatically and your saved values are kept.
const KNOWN_GUNS := [
	{"path": "/Game/Weapons/AK74M/Blueprints/Firearm_Rifle_AK74M.Firearm_Rifle_AK74M_C", "verified": true},
	{"path": "/Game/Weapons/HK416a5/Blueprints/Firearm_Rifle_HK416A5_279mm.Firearm_Rifle_HK416A5_279mm_C", "verified": true},
	{"path": "/Game/Weapons/HK416a5/Blueprints/Firearm_Rifle_HK416A5_368mm.Firearm_Rifle_HK416A5_368mm_C", "verified": false},
	{"path": "/Game/Weapons/M4A1_URGI/Blueprint/Firearm_Rifle_M4A1_BlockIICQBR.Firearm_Rifle_M4A1_BlockIICQBR_C", "verified": true},
	{"path": "/Game/Weapons/M4A1_URGI/Blueprint/Firearm_Rifle_M4A1_URGI.Firearm_Rifle_M4A1_URGI_C", "verified": true},
	{"path": "/Game/Weapons/MCX_LT/Blueprint/Firearm_Rifle_MCX_LT_CSAW.Firearm_Rifle_MCX_LT_CSAW_C", "verified": true},
	{"path": "/Game/Weapons/MCX_LT/Blueprint/Firearm_Rifle_MCX_LT_Rattler.Firearm_Rifle_MCX_LT_Rattler_C", "verified": true},
	{"path": "/Game/Weapons/G28/Blueprints/Firearm_Rifle_G28.Firearm_Rifle_G28_C", "verified": false},
	{"path": "/Game/Weapons/KAC/Blueprints/Firearm_Rifle_KAC_KS1.Firearm_Rifle_KAC_KS1_C", "verified": false},
	{"path": "/Game/Weapons/KAC/Blueprints/Firearm_Rifle_KAC_M110.Firearm_Rifle_KAC_M110_C", "verified": false},
	{"path": "/Game/Weapons/KAC/Blueprints/Firearm_Rifle_KAC_SR25.Firearm_Rifle_KAC_SR25_C", "verified": false},
	{"path": "/Game/Weapons/Tavor_X95/Blueprints/Firearm_Rifle_Tavor_X95.Firearm_Rifle_Tavor_X95_C", "verified": false},
	{"path": "/Game/Weapons/MP5/Blueprints/Firearm_SMG_MP5_A5.Firearm_SMG_MP5_A5_C", "verified": false},
	{"path": "/Game/Weapons/MP5/Blueprints/Firearm_SMG_MP5SD.Firearm_SMG_MP5SD_C", "verified": false},
	{"path": "/Game/Weapons/MP7/Blueprints/Firearm_SMG_MP7A2.Firearm_SMG_MP7A2_C", "verified": false},
	{"path": "/Game/Weapons/Remington700/Blueprints/Firearm_BoltAction_Remington700.Firearm_BoltAction_Remington700_C", "verified": false},
	{"path": "/Game/Weapons/Remington700/Blueprints/Firearm_BoltAction_R700_MDTESS.Firearm_BoltAction_R700_MDTESS_C", "verified": false},
	{"path": "/Game/Weapons/PKP/Blueprints/Firearm_LMG_PKP.Firearm_LMG_PKP_C", "verified": false},
	{"path": "/Game/Weapons/870MCS/Blueprints/Firearm_Shotgun_870MCS.Firearm_Shotgun_870MCS_C", "verified": false},
	{"path": "/Game/Weapons/G19_Gen5/Blueprints/Firearm_Pistol_G19_Gen5.Firearm_Pistol_G19_Gen5_C", "verified": false},
	{"path": "/Game/Weapons/P320/Blueprints/Firearm_Pistol_P320.Firearm_Pistol_P320_C", "verified": false},
	{"path": "/Game/Weapons/Staccato/Blueprints/Firearm_Pistol_Staccato.Firearm_Pistol_Staccato_C", "verified": false},
	{"path": "/Game/Weapons/USP45/Blueprints/Firearm_Pistol_USP45.Firearm_Pistol_USP45_C", "verified": false},
]

# Optic tiers matching the game's real mounts (heights = optical centre over rail):
# Short/lower-1/3 1.42", Tall 1.93", Unity FAST 2.26", GBRS Mount1 2.91".
const RIFLE_OPTICS := [
	{"name": "IRON SIGHTS", "node": "irons"},
	{"name": "EOTECH EXPS3", "node": "exps3"},
	{"name": "RED DOT - LOW 1.42\"", "node": "dot_low"},
	{"name": "RED DOT - TALL 1.93\"", "node": "dot_tall"},
	{"name": "RED DOT - UNITY 2.26\"", "node": "dot_unity"},
	{"name": "RED DOT - GBRS 2.91\"", "node": "dot_gbrs"},
	{"name": "ACOG 4x", "node": "acog"},
]
const PISTOL_OPTICS := [
	{"name": "IRON SIGHTS", "node": "p_irons"},
	{"name": "SLIDE DOT (SRO)", "node": "p_sro"},
]
var optic_choice: Array = []     # per-gun optic index, parallel with gun_names
var optic_nodes := {}            # node-key -> Node3D
var rifle_body: Node3D
var pistol_body: Node3D

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

	# ---- long-gun body (rifles / SMGs / shotguns / LMG / bolt) ----
	rifle_body = Node3D.new()
	rifle.add_child(rifle_body)
	# origin = pistol grip. -Z is forward.
	_add_box(rifle_body, Vector3(0.045, 0.060, 0.30), Vector3(0.0, 0.070, -0.050), mid)     # receiver
	_add_box(rifle_body, Vector3(0.040, 0.050, 0.22), Vector3(0.0, 0.080, -0.310), dark)    # handguard
	_add_box(rifle_body, Vector3(0.035, 0.090, 0.050), Vector3(0.0, -0.005, 0.010), dark)   # grip
	_add_box(rifle_body, Vector3(0.040, 0.050, 0.20), Vector3(0.0, 0.055, 0.150), dark)     # stock
	_add_box(rifle_body, Vector3(0.045, 0.110, 0.020), Vector3(0.0, 0.045, 0.255), mid)     # buttpad
	_add_box(rifle_body, Vector3(0.035, 0.110, 0.060), Vector3(0.0, -0.010, -0.110), mid)   # magazine
	var barrel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.011
	cyl.bottom_radius = 0.011
	cyl.height = 0.30
	barrel.mesh = cyl
	barrel.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	barrel.position = Vector3(0.0, 0.085, -0.500)
	barrel.material_override = _mat(dark)
	rifle_body.add_child(barrel)

	# rifle iron sights
	var irons := Node3D.new()
	rifle_body.add_child(irons)
	optic_nodes["irons"] = irons
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.006
	tor.outer_radius = 0.011
	ring.mesh = tor
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	ring.position = Vector3(0.0, 0.125, 0.030)
	ring.material_override = _mat(Color.BLACK)
	irons.add_child(ring)
	_add_box(irons, Vector3(0.004, 0.018, 0.004), Vector3(0.0, 0.122, -0.640), Color(1.0, 0.45, 0.05))
	_add_box(irons, Vector3(0.020, 0.014, 0.010), Vector3(0.0, 0.105, -0.640), dark)

	# rifle optics (heights = optical centre above rail at y 0.100)
	_build_exps3()
	optic_nodes["dot_low"] = _build_dot(0.036, Color(0.10, 0.10, 0.11))     # 1.42"
	optic_nodes["dot_tall"] = _build_dot(0.049, Color(0.10, 0.10, 0.11))    # 1.93"
	optic_nodes["dot_unity"] = _build_dot(0.057, Color(0.35, 0.30, 0.22))   # Unity FAST 2.26"
	optic_nodes["dot_gbrs"] = _build_dot(0.074, Color(0.35, 0.30, 0.22))    # GBRS Mount1 2.91"
	optic_nodes["acog"] = _build_acog()

	# ---- pistol body ----
	_build_pistol()
	_apply_optic()


func _build_pistol() -> void:
	pistol_body = Node3D.new()
	rifle.add_child(pistol_body)
	var dark := Color(0.13, 0.13, 0.14)
	var mid := Color(0.22, 0.22, 0.24)
	# origin = grip, -Z forward. Slide top ~0.10 to keep sight lines comparable.
	_add_box(pistol_body, Vector3(0.032, 0.100, 0.048), Vector3(0.0, 0.010, 0.008), dark)   # grip
	_add_box(pistol_body, Vector3(0.032, 0.028, 0.170), Vector3(0.0, 0.068, -0.045), mid)   # frame
	_add_box(pistol_body, Vector3(0.034, 0.032, 0.190), Vector3(0.0, 0.086, -0.045), dark)  # slide
	_add_box(pistol_body, Vector3(0.026, 0.006, 0.052), Vector3(0.0, 0.046, -0.062), dark)  # trigger guard
	# pistol irons
	var pi := Node3D.new()
	pistol_body.add_child(pi)
	optic_nodes["p_irons"] = pi
	_add_box(pi, Vector3(0.006, 0.008, 0.004), Vector3(-0.006, 0.106, 0.044), dark)         # rear notch L
	_add_box(pi, Vector3(0.006, 0.008, 0.004), Vector3(0.006, 0.106, 0.044), dark)          # rear notch R
	_add_box(pi, Vector3(0.0035, 0.008, 0.0035), Vector3(0.0, 0.105, -0.135), Color(0.2, 1.0, 0.4))  # front dot
	# slide-mounted SRO
	var sro := Node3D.new()
	pistol_body.add_child(sro)
	optic_nodes["p_sro"] = sro
	_add_box(sro, Vector3(0.028, 0.006, 0.045), Vector3(0.0, 0.105, 0.030), Color(0.10, 0.10, 0.11))
	var win := MeshInstance3D.new()
	var wt := TorusMesh.new()
	wt.inner_radius = 0.0105
	wt.outer_radius = 0.0135
	win.mesh = wt
	win.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	win.position = Vector3(0.0, 0.122, 0.018)
	win.material_override = _mat(Color(0.10, 0.10, 0.11))
	sro.add_child(win)
	var dot := _add_box(sro, Vector3(0.0018, 0.0018, 0.001), Vector3(0.0, 0.122, 0.018), Color(1.0, 0.12, 0.08))
	dot.material_override = _emat(Color(1.0, 0.12, 0.08))


func _build_dot(h: float, mount_col: Color) -> Node3D:
	# Generic tube red dot (T-2/CompM5/MRO class) with optical centre h above the rail.
	var n := Node3D.new()
	rifle_body.add_child(n)
	var body := Color(0.10, 0.10, 0.11)
	var oc := 0.100 + h
	_add_box(n, Vector3(0.030, 0.012, 0.070), Vector3(0.0, 0.106, -0.020), mount_col)       # base
	if h > 0.024:
		_add_box(n, Vector3(0.024, oc - 0.118, 0.034), Vector3(0.0, 0.112 + (oc - 0.118) * 0.5, -0.020), mount_col)  # tower
	var tube := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.0125
	cy.bottom_radius = 0.0125
	cy.height = 0.062
	tube.mesh = cy
	tube.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	tube.position = Vector3(0.0, oc, -0.020)
	tube.material_override = _mat(body)
	n.add_child(tube)
	for zz in [-0.052, 0.012]:
		var bell := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.0145
		bc.bottom_radius = 0.0145
		bc.height = 0.010
		bell.mesh = bc
		bell.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		bell.position = Vector3(0.0, oc, zz)
		bell.material_override = _mat(body)
		n.add_child(bell)
	var dot := _add_box(n, Vector3(0.0018, 0.0018, 0.001), Vector3(0.0, oc, -0.020), Color(1.0, 0.12, 0.08))
	dot.material_override = _emat(Color(1.0, 0.12, 0.08))
	return n


func _build_acog() -> Node3D:
	# ACOG 4x: stubby scope, optical centre ~1.5" (38 mm) over rail.
	var n := Node3D.new()
	rifle_body.add_child(n)
	var body := Color(0.10, 0.10, 0.11)
	var oc := 0.138
	_add_box(n, Vector3(0.032, 0.016, 0.080), Vector3(0.0, 0.108, -0.020), body)
	var tube := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.019
	cy.bottom_radius = 0.015
	cy.height = 0.13
	tube.mesh = cy
	tube.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	tube.position = Vector3(0.0, oc, -0.030)
	tube.material_override = _mat(body)
	n.add_child(tube)
	# red chevron reticle
	var ch := _add_box(n, Vector3(0.003, 0.0022, 0.001), Vector3(0.0, oc, 0.036), Color(1.0, 0.12, 0.08))
	ch.material_override = _emat(Color(1.0, 0.12, 0.08))
	return n


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
	var exps3_node := Node3D.new()
	rifle_body.add_child(exps3_node)
	optic_nodes["exps3"] = exps3_node
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


func _gun_is_pistol(i: int) -> bool:
	if i < 0 or i >= gun_paths.size():
		return false
	return gun_paths[i].contains("Firearm_Pistol")


func _optic_list(i: int) -> Array:
	return PISTOL_OPTICS if _gun_is_pistol(i) else RIFLE_OPTICS


func _apply_optic() -> void:
	if rifle_body == null:
		return                                   # headless tests: no scene built
	var pistol := _gun_is_pistol(cur)
	rifle_body.visible = not pistol
	pistol_body.visible = pistol
	var lst := _optic_list(cur)
	var idx := 0
	if not optic_choice.is_empty() and cur < optic_choice.size():
		idx = clampi(optic_choice[cur], 0, lst.size() - 1)
	# hide every optic, then show the selected one for the visible body
	for key in optic_nodes:
		optic_nodes[key].visible = false
	optic_nodes[lst[idx]["node"]].visible = true


func _build_hud() -> void:
	hud = Label3D.new()
	hud.font_size = 56
	hud.pixel_size = 0.0004
	hud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hud.no_depth_test = true
	hud.position = Vector3(0.0, 0.09, 0.02)
	left.add_child(hud)


# ---------------------------------------------------------------- INI handling
func _class_of(path: String) -> String:
	return path.get_file().get_slice(".", 0)     # e.g. Firearm_Rifle_M4A1_URGI


func _display_name(cls: String) -> String:
	var n := cls.trim_prefix("Firearm_")
	for cat in ["Rifle_", "Pistol_", "SMG_", "LMG_", "BoltAction_", "Shotgun_"]:
		n = n.trim_prefix(cat)
	return n


func _is_candidate_path(path: String) -> bool:
	for g in KNOWN_GUNS:
		if g["path"] == path and not g["verified"]:
			return true
	return false


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
	gun_paths.clear()
	gun_in_ini.clear()
	offsets.clear()
	var raw_paths: Array[String] = []
	var raw_offsets: Array = []
	for raw in txt.split("\n"):
		var l := raw.strip_edges()
		if l.begins_with("GunClassPaths="):
			raw_paths.append(l.get_slice("=", 1))
		elif l.begins_with("GunTransforms="):
			var v := l.get_slice("=", 1)
			var t := v.get_slice("|", 0).split(",")
			var r := v.get_slice("|", 1).split(",")
			if t.size() >= 3 and r.size() >= 1:
				raw_offsets.append({
					"up": t[0].to_float(), "lr": t[1].to_float(),
					"fwd": t[2].to_float(), "pitch": r[0].to_float()
				})
	if raw_paths.size() != raw_offsets.size():
		return false
	# merge INI rows by class name (game-written paths beat our candidates;
	# calibrated values beat zeros)
	for i in raw_paths.size():
		var cls := _class_of(raw_paths[i])
		var found := -1
		for j in gun_paths.size():
			if _class_of(gun_paths[j]) == cls:
				found = j
				break
		if found == -1:
			gun_names.append(_display_name(cls))
			gun_paths.append(raw_paths[i])
			gun_in_ini.append(true)
			offsets.append(raw_offsets[i])
		else:
			if _is_candidate_path(gun_paths[found]) and not _is_candidate_path(raw_paths[i]):
				gun_paths[found] = raw_paths[i]   # game-written path wins
			var o: Dictionary = raw_offsets[i]
			if absf(o["up"]) > 0.005 or absf(o["lr"]) > 0.005:
				offsets[found] = o                # calibrated values win
	# seed for new guns: copy an existing calibrated gun (same stock => close
	# start). Prefer the URGI row (typically the best-verified), else the first.
	var seed_off := {"up": 0.0, "lr": 0.0, "fwd": 8.0, "pitch": 0.0}
	for j in gun_paths.size():
		if _class_of(gun_paths[j]) == "Firearm_Rifle_M4A1_URGI":
			seed_off = offsets[j].duplicate()
			break
	if seed_off["fwd"] == 8.0 and not offsets.is_empty():
		seed_off = offsets[0].duplicate()
	# append every known gun not present in the INI yet
	for g in KNOWN_GUNS:
		var cls: String = _class_of(g["path"])
		var present := false
		for j in gun_paths.size():
			if _class_of(gun_paths[j]) == cls:
				present = true
				break
		if not present:
			gun_names.append(_display_name(cls))
			gun_paths.append(g["path"])
			gun_in_ini.append(false)
			offsets.append(seed_off.duplicate())
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
	var lines := Array(txt.split("\n")).map(func(s): return String(s).trim_suffix("\r"))
	# rebuild the calibration section from tool state: every gun already in the
	# INI plus the one being saved now (keeps parallel arrays consistent and
	# compacts any duplicate rows)
	var persist: Array[int] = []
	for i in gun_names.size():
		if gun_in_ini[i] or i == cur:
			persist.append(i)
	var section: Array = [CALIB_SECTION]
	for i in persist:
		section.append("GunClassPaths=" + gun_paths[i])
	for i in persist:
		var o: Dictionary = offsets[i]
		section.append("GunTransforms=%.6f,%.6f,%.6f|%.6f,0.000000,0.000000|1.000000,1.000000,1.000000" \
			% [o["up"], o["lr"], o["fwd"], o["pitch"]])
	var r := _extract_calib_section(lines)
	var merged: Array
	if r[0] == -1:
		merged = lines + [""] + section              # section absent: append at EOF
	else:
		# carry over any other lines the section held (e.g. UniversalGunClassPath)
		for k in range(r[0] + 1, r[1]):
			var l := String(lines[k]).strip_edges()
			if not (l.begins_with("GunClassPaths=") or l.begins_with("GunTransforms=")):
				section.append(String(lines[k]))
		merged = lines.slice(0, r[0]) + section + lines.slice(r[1])
	var joined := ""
	for i in merged.size():
		joined += String(merged[i])
		if i < merged.size() - 1:
			joined += eol
	var f := FileAccess.open(ini_path, FileAccess.WRITE)
	if f == null:
		_flash("WRITE FAILED - file locked?", 5.0, Color(1.0, 0.25, 0.2))
		return
	f.store_string(joined)
	f.close()
	gun_in_ini[cur] = true
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
			var lst := _optic_list(cur)
			optic_choice[cur] = (optic_choice[cur] + 1) % lst.size()
			_apply_optic()
			_save_optics()
			_flash(lst[optic_choice[cur]]["name"], 1.5, Color(0.4, 0.7, 1.0))


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
	var lst := _optic_list(cur)
	var optic_name: String = ""
	if cur < optic_choice.size():
		optic_name = lst[clampi(optic_choice[cur], 0, lst.size() - 1)]["name"]
	var status_line := ""
	if not gun_in_ini[cur]:
		status_line = "NEW - not in game save yet" \
			+ (" (path unverified)" if _is_candidate_path(gun_paths[cur]) else "")
	elif anchor_mode:
		status_line = "MODE: BASE-ADJUST"
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
		status_line
	]
	hud.modulate = Color(1.0, 0.85, 0.4) if dirty else Color.WHITE
