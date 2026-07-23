extends SceneTree
# Headless test: round-trip the save path against a SCRATCH COPY of the INI.
func _init() -> void:
	var n := Node3D.new()
	n.set_script(load("res://main.gd"))
	assert(n._load_ini())
	# redirect writes to a scratch copy
	var scratch: String = OS.get_environment("TEMP").replace("\\", "/") + "/calibtool_test.ini"
	DirAccess.copy_absolute(n.ini_path, scratch)
	n.ini_path = scratch
	n.backed_up = true  # skip backup step in test
	# modify AK74M (index 0): up 2.52 -> 14.52
	n.cur = 0
	n.offsets[0]["up"] = 14.52
	n._save_ini()
	# re-read scratch and verify only that row changed
	var txt := FileAccess.get_file_as_string(scratch)
	print("row written: ", txt.contains("GunTransforms=14.520000,-4.123861,15.001390|0.000000"))
	print("URGI row intact: ", txt.contains("GunTransforms=13.000000,-0.913739,4.230670|-16.456508"))
	print("CRLF preserved: ", txt.contains("\r\n"))
	var orig := FileAccess.get_file_as_string(
		OS.get_environment("LOCALAPPDATA").replace("\\", "/")
		+ "/Geronimo/Saved/Config/Windows/GameUserSettings.ini")
	print("same length +/- edit: orig=%d new=%d" % [orig.length(), txt.length()])
	print("settings preserved: ", txt.contains("PlayerHeight=184") and txt.contains("[ScalabilityGroups]"))
	n.free()
	quit()
