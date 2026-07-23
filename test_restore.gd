extends SceneTree
# Headless test: backup listing + calibration-section splice on scratch copies.
func _init() -> void:
	var n := Node3D.new()
	n.set_script(load("res://main.gd"))
	assert(n._load_ini())
	var real_ini: String = n.ini_path
	# scratch "current" file with a MODIFIED calibration + a marker settings line
	var scratch_dir: String = OS.get_environment("TEMP").replace("\\", "/") + "/calibtool_restore_test"
	DirAccess.make_dir_recursive_absolute(scratch_dir)
	var cur_path := scratch_dir + "/GameUserSettings.ini"
	var txt := FileAccess.get_file_as_string(real_ini)
	var modified := txt.replace("13.034524", "99.999999").replace("PlayerHeight=183", "PlayerHeight=170")
	var f := FileAccess.open(cur_path, FileAccess.WRITE)
	f.store_string(modified)
	f.close()
	n.ini_path = cur_path
	# backup dir with a copy of the REAL (good) file as a backup
	DirAccess.make_dir_recursive_absolute(n._backup_dir())
	DirAccess.copy_absolute(real_ini, n._backup_dir() + "/GameUserSettings-2026-07-23_10-00-00.ini")
	var lst: Array = n._list_backups()
	print("backup listed: ", lst.size() == 1)
	# splice: should restore calibration (99.9 -> 13.03) but KEEP PlayerHeight=170
	var ok: bool = n._splice_calib_from_backup(lst[0])
	var after := FileAccess.get_file_as_string(cur_path)
	print("splice ok: ", ok)
	print("calibration restored: ", after.contains("13.034524") and not after.contains("99.999999"))
	print("settings untouched: ", after.contains("PlayerHeight=170"))
	print("row count intact: ", after.count("GunTransforms=") == 6)
	n.free()
	quit()
