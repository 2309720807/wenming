class_name MilitaryMeshes

## 军事设施/单位 3D 程序化建模契约（Team Lead 冻结，工人只读共享）
## 规则：军事基地（military_view.gd）与副本（instance_view.gd）的 3D 化必须调用本文件生成模型。

static func build_unit_model(unit_id: String, cell: float, level: int = 1) -> Node3D:
	var root := Node3D.new()
	match unit_id:
		"turret":
			_build_turret(root, cell)
		"wall":
			_build_wall(root, cell)
		"barracks":
			_build_barracks(root, cell)
		"aa":
			_build_aa(root, cell)
		"armory":
			_build_armory(root, cell)
		"bunker":
			_build_bunker(root, cell)
		"swordsman":
			_build_swordsman(root, cell)
		"archer":
			_build_archer(root, cell)
		"cavalry":
			_build_cavalry(root, cell)
		"battering_ram":
			_build_ram(root, cell)
		"catapult":
			_build_catapult(root, cell)
		_:
			_build_box(root, Vector3(cell * 0.8, cell * 0.8, cell * 0.8), Color(0.5, 0.55, 0.7), Vector3.ZERO)
	return root


static func _build_turret(root: Node3D, c: float) -> void:
	_build_cyl(root, c * 0.36, c * 0.36, c * 0.22, Color(0.55, 0.3, 0.28), Vector3(0, c * 0.11, 0))
	_build_box(root, Vector3(c * 0.5, c * 0.3, c * 0.5), Color(0.7, 0.35, 0.3), Vector3(0, c * 0.37, 0))
	_build_cyl(root, c * 0.1, c * 0.1, c * 0.55, Color(0.35, 0.22, 0.2), Vector3(0, c * 0.42, c * 0.3))
	_build_sphere(root, c * 0.08, Color(1.0, 0.85, 0.45), Vector3(0, c * 0.56, 0))


static func _build_wall(root: Node3D, c: float) -> void:
	_build_box(root, Vector3(c * 0.9, c * 0.7, c * 0.4), Color(0.48, 0.5, 0.56), Vector3(0, c * 0.35, 0))
	for i: int in range(4):
		_build_box(root, Vector3(c * 0.14, c * 0.16, c * 0.4), Color(0.55, 0.57, 0.63), Vector3((i - 1.5) * c * 0.22, c * 0.78, 0))


static func _build_barracks(root: Node3D, c: float) -> void:
	_build_box(root, Vector3(c * 1.5, c * 0.7, c * 1.1), Color(0.35, 0.45, 0.75), Vector3(0, c * 0.35, 0))
	_build_box(root, Vector3(c * 1.6, c * 0.24, c * 1.2), Color(0.28, 0.36, 0.6), Vector3(0, c * 0.82, 0))
	_build_box(root, Vector3(c * 0.5, c * 0.5, c * 0.08), Color(0.15, 0.2, 0.35), Vector3(0, c * 0.25, c * 0.56))


static func _build_aa(root: Node3D, c: float) -> void:
	_build_box(root, Vector3(c * 0.6, c * 0.18, c * 0.6), Color(0.5, 0.4, 0.3), Vector3(0, c * 0.09, 0))
	for s: int in range(2):
		var mi := MeshInstance3D.new()
		mi.mesh = _make_cyl_mesh(c * 0.07, c * 0.07, c * 0.7)
		mi.material_override = _make_std(Color(0.75, 0.5, 0.2))
		mi.position = Vector3((s - 0.5) * c * 0.2, c * 0.3, -c * 0.1)
		mi.rotation_degrees = Vector3(-30, 0, 0)
		root.add_child(mi)


static func _build_armory(root: Node3D, c: float) -> void:
	_build_box(root, Vector3(c * 1.5, c * 0.65, c * 1.2), Color(0.45, 0.35, 0.6), Vector3(0, c * 0.33, 0))
	for ix: int in range(2):
		for iz: int in range(2):
			_build_box(root, Vector3(c * 0.16, c * 0.75, c * 0.16), Color(0.35, 0.28, 0.48),
					Vector3((ix - 0.5) * c * 1.4, c * 0.38, (iz - 0.5) * c * 1.05))
	_build_cyl(root, c * 0.02, c * 0.02, c * 0.4, Color(0.85, 0.85, 0.9), Vector3(0, c * 0.95, 0))
	_build_box(root, Vector3(c * 0.28, c * 0.18, c * 0.04), Color(0.9, 0.3, 0.35), Vector3(c * 0.14, c * 1.08, 0))


static func _build_bunker(root: Node3D, c: float) -> void:
	_build_cyl(root, c * 0.7, c * 0.7, c * 1.6, Color(0.3, 0.6, 0.5), Vector3(0, c * 0.45, 0), Vector3(0, 0, 90))
	_build_box(root, Vector3(c * 0.5, c * 0.6, c * 0.1), Color(0.2, 0.4, 0.35), Vector3(0, c * 0.3, c * 0.82))


static func _build_swordsman(root: Node3D, c: float) -> void:
	_build_box(root, Vector3(c * 0.3, c * 0.5, c * 0.2), Color(0.35, 0.55, 0.85), Vector3(0, c * 0.35, 0))
	_build_sphere(root, c * 0.14, Color(0.9, 0.8, 0.7), Vector3(0, c * 0.72, 0))
	_build_box(root, Vector3(c * 0.05, c * 0.45, c * 0.05), Color(0.8, 0.82, 0.9), Vector3(c * 0.22, c * 0.55, 0))


static func _build_archer(root: Node3D, c: float) -> void:
	_build_box(root, Vector3(c * 0.28, c * 0.45, c * 0.18), Color(0.3, 0.6, 0.35), Vector3(0, c * 0.33, 0))
	_build_sphere(root, c * 0.13, Color(0.9, 0.8, 0.7), Vector3(0, c * 0.66, 0))
	_build_cyl(root, c * 0.02, c * 0.02, c * 0.5, Color(0.65, 0.5, 0.3), Vector3(c * 0.24, c * 0.4, 0), Vector3(0, 0, 20))


static func _build_cavalry(root: Node3D, c: float) -> void:
	_build_box(root, Vector3(c * 0.7, c * 0.35, c * 0.3), Color(0.5, 0.38, 0.28), Vector3(0, c * 0.5, 0))
	_build_box(root, Vector3(c * 0.22, c * 0.2, c * 0.2), Color(0.45, 0.34, 0.25), Vector3(c * 0.45, c * 0.68, 0))
	for i: int in range(4):
		_build_box(root, Vector3(c * 0.08, c * 0.4, c * 0.08), Color(0.4, 0.3, 0.22),
				Vector3((int(i / 2) - 0.5) * c * 0.5, c * 0.2, ((i % 2) - 0.5) * c * 0.14))
	_build_box(root, Vector3(c * 0.2, c * 0.35, c * 0.18), Color(0.6, 0.25, 0.25), Vector3(0, c * 0.9, 0))
	_build_sphere(root, c * 0.1, Color(0.9, 0.8, 0.7), Vector3(0, c * 1.15, 0))


static func _build_ram(root: Node3D, c: float) -> void:
	for s: int in range(2):
		for j: int in range(2):
			_build_box(root, Vector3(c * 0.1, c * 0.7, c * 0.1), Color(0.45, 0.35, 0.25),
					Vector3((s - 0.5) * c * 0.5, c * 0.35, (j - 0.5) * c * 0.4))
	_build_cyl(root, c * 0.16, c * 0.16, c * 0.9, Color(0.35, 0.28, 0.2), Vector3(0, c * 0.6, 0), Vector3(0, 0, 90))


static func _build_catapult(root: Node3D, c: float) -> void:
	_build_box(root, Vector3(c * 0.8, c * 0.16, c * 0.5), Color(0.5, 0.4, 0.3), Vector3(0, c * 0.24, 0))
	for i: int in range(2):
		_build_cyl(root, c * 0.16, c * 0.16, c * 0.1, Color(0.3, 0.24, 0.18),
				Vector3((i - 0.5) * c * 0.5, c * 0.16, 0), Vector3(0, 0, 90))
	_build_cyl(root, c * 0.05, c * 0.05, c * 0.7, Color(0.6, 0.48, 0.35), Vector3(0, c * 0.5, -c * 0.15), Vector3(-40, 0, 0))
	_build_sphere(root, c * 0.12, Color(0.35, 0.35, 0.4), Vector3(0, c * 0.72, -c * 0.4))


static func _build_box(root: Node3D, size: Vector3, color: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(maxf(size.x, 0.02), maxf(size.y, 0.02), maxf(size.z, 0.02))
	mi.mesh = box
	mi.position = pos
	mi.material_override = _make_std(color)
	root.add_child(mi)


static func _build_cyl(root: Node3D, r_top: float, r_bot: float, h: float, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	mi.mesh = cm
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = _make_std(color)
	root.add_child(mi)


static func _build_sphere(root: Node3D, r: float, color: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.position = pos
	mi.material_override = _make_std(color)
	root.add_child(mi)


static func _make_cyl_mesh(r_top: float, r_bot: float, h: float) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	return cm


static func _make_std(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.75
	m.metallic = 0.05
	return m
