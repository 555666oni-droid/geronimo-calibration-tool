extends SceneTree
# Headless test: backup listing + calibration-section splice on scratch copies.
func _init() -> void:
	var n := Node3D.new()
	n.set_script(load("res://main.gd"))
	assert(n._load_ini())
	var real_ini: String = n.ini_path
	var txt := FileAccess.get_file_as_string(real_ini)
	# grab the first GunTransforms line as the marker to corrupt
	var marker := ""
	for l in txt.split("\n"):
		if l.strip_edges().begins_with("GunTransforms="):
			marker = l.strip_edges()
			break
	assert(marker != "")
	# scratch "current" file: corrupted calibration + a changed settings line
	var scratch_dir: String = OS.get_environment("TEMP").replace("\\", "/") + "/calibtool_restore_test"
	DirAccess.make_dir_recursive_absolute(scratch_dir)
	var cur_path := scratch_dir + "/GameUserSettings.ini"
	var modified := txt.replace(marker, "GunTransforms=99.000000,99.000000,99.000000|0.000000,0.000000,0.000000|1.000000,1.000000,1.000000")
	modified = modified.replace("PlayerHeight=", "PlayerHeight=17")   # 183 -> 17183 marker
	var f := FileAccess.open(cur_path, FileAccess.WRITE)
	f.store_string(modified)
	f.close()
	n.ini_path = cur_path
	# backup dir with a copy of the REAL (good) file as a backup
	DirAccess.make_dir_recursive_absolute(n._backup_dir())
	DirAccess.copy_absolute(real_ini, n._backup_dir() + "/GameUserSettings-2026-07-24_10-00-00.ini")
	var lst: Array = n._list_backups()
	print("backup listed: ", lst.size() >= 1)
	var ok: bool = n._splice_calib_from_backup(lst[0])
	var after := FileAccess.get_file_as_string(cur_path)
	print("splice ok: ", ok)
	print("calibration restored: ", after.contains(marker) and not after.contains("99.000000,99.000000"))
	print("settings untouched by restore: ", after.contains("PlayerHeight=17"))
	print("row counts equal original: ", after.count("GunTransforms=") == txt.count("GunTransforms="))
	n.free()
	quit()
