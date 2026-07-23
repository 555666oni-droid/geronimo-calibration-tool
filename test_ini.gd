extends SceneTree
# Headless test: verify the tool parses Geronimo's real INI correctly.
func _init() -> void:
	var n := Node3D.new()
	n.set_script(load("res://main.gd"))
	var ok: bool = n._load_ini()
	print("INI loaded: ", ok)
	if ok:
		for i in n.gun_names.size():
			var o: Dictionary = n.offsets[i]
			print("%d  %-22s up=%+7.2f lr=%+7.2f fwd=%+7.2f pitch=%+7.2f" \
				% [i + 1, n.gun_names[i], o["up"], o["lr"], o["fwd"], o["pitch"]])
		print("default selected: ", n.gun_names[n.cur])
	n.free()
	quit()
