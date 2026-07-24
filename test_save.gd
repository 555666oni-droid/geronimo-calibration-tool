extends SceneTree
# Headless test: round-trip the save path against a SCRATCH COPY of the INI.
func _init() -> void:
	var n := Node3D.new()
	n.set_script(load("res://main.gd"))
	assert(n._load_ini())
	var ini_gun_count := 0
	for b in n.gun_in_ini:
		if b:
			ini_gun_count += 1
	print("guns total/in-ini: %d/%d" % [n.gun_names.size(), ini_gun_count])
	# redirect writes to a scratch copy
	var scratch: String = OS.get_environment("TEMP").replace("\\", "/") + "/calibtool_test.ini"
	DirAccess.copy_absolute(n.ini_path, scratch)
	var orig := FileAccess.get_file_as_string(scratch)
	n.ini_path = scratch
	n.backed_up = true
	# find AK74M (in-ini) and a reference gun to verify untouched afterwards
	var ak: int = n.gun_names.find("AK74M")
	var urgi: int = n.gun_names.find("M4A1_URGI")
	var urgi_before: Dictionary = n.offsets[urgi].duplicate()
	n.cur = ak
	n.offsets[ak]["up"] = 14.52
	n._save_ini()
	var txt := FileAccess.get_file_as_string(scratch)
	var ak_row := "GunTransforms=%.6f,%.6f,%.6f|%.6f," % [14.52, n.offsets[ak]["lr"], n.offsets[ak]["fwd"], n.offsets[ak]["pitch"]]
	var urgi_row := "GunTransforms=%.6f,%.6f,%.6f|%.6f," % [urgi_before["up"], urgi_before["lr"], urgi_before["fwd"], urgi_before["pitch"]]
	print("edited row written: ", txt.contains(ak_row))
	print("other row intact: ", txt.contains(urgi_row))
	print("CRLF preserved: ", txt.contains("\r\n") == orig.contains("\r\n"))
	print("row count unchanged: ", txt.count("GunTransforms=") == orig.count("GunTransforms="))
	var ph := ""
	for l in orig.split("\n"):
		if l.strip_edges().begins_with("PlayerHeight="):
			ph = l.strip_edges()
	print("settings preserved: ", ph != "" and txt.contains(ph) and txt.contains("[ScalabilityGroups]"))
	# NEW-GUN save: pick a gun not in the INI, save it, expect one extra row pair
	var newgun: int = n.gun_in_ini.find(false)
	if newgun != -1:
		n.cur = newgun
		n.offsets[newgun]["up"] = 9.99
		n._save_ini()
		var txt2 := FileAccess.get_file_as_string(scratch)
		print("new gun appended: ", txt2.count("GunTransforms=") == orig.count("GunTransforms=") + 1
			and txt2.count("GunClassPaths=") == orig.count("GunClassPaths=") + 1
			and txt2.contains(n.gun_paths[newgun]))
		print("class/transform counts match: ", txt2.count("GunTransforms=") == txt2.count("GunClassPaths="))
	n.free()
	quit()
