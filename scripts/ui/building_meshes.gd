class_name BuildingMeshes
extends RefCounted

## 程序化低多边形建筑模型（以真实建筑为模板）
## 住宅=中国多层住宅楼；办公楼=玻璃幕墙写字楼；学校=校园教学楼+旗杆+钟楼；
## 医院=现代医院大楼+屋顶停机坪；金融中心=分段收分摩天大楼（参考金茂大厦阶梯式塔身）
## 数据驱动：buildings.json 的 id/color/width/height；level 影响层数（升级长高）
## 全部由 BoxMesh/PrismMesh/CylinderMesh/SphereMesh 程序化组合，无需外部模型

const ELF: float = 0.86  # 建筑占地系数（建筑间留缝）


## 主入口：按物品配置生成建筑节点（根节点原点 = 建筑中心格，Y=0 地面）
static func build(item: Dictionary, level: int, cellf: float) -> Node3D:
	var root := Node3D.new()
	var bid := String(item.get("id", ""))
	var base: Color = Color(item.get("color", "#6a7fa8"))
	var w: int = int(item.get("width", 1))
	var h: int = int(item.get("height", 1))
	var total_w: float = w * cellf * ELF
	var total_d: float = h * cellf * ELF
	match bid:
		"residence":
			_build_residence(root, total_w, total_d, cellf, base, level)
		"office":
			_build_office(root, total_w, total_d, cellf, base, level)
		"school":
			_build_school(root, total_w, total_d, cellf, base, level)
		"hospital":
			_build_hospital(root, total_w, total_d, cellf, base, level)
		"finance":
			_build_finance(root, total_w, total_d, cellf, base, level)
		_:
			_build_generic(root, total_w, total_d, cellf, base, level)
	return root


# ========== 住宅：中国多层住宅楼（每层阳台+窗格+坡屋顶+入口门廊） ==========

static func _build_residence(root: Node3D, tw: float, td: float, cellf: float, base: Color, level: int) -> void:
	var floors: int = 2 + mini(level, 4)  # 2~6 层（升级长高）
	var body_h: float = cellf * (0.5 + 0.28 * floors)
	# 主体 + 深色基座
	_add_box(root, tw, body_h, td, base, Vector3(0, body_h * 0.5, 0))
	_add_box(root, tw * 1.02, cellf * 0.18, td * 1.02, base.darkened(0.3), Vector3(0, cellf * 0.09, 0))
	# 每层：正面两窗一阳台、背面两窗、侧面一窗
	for f: int in range(floors):
		var yy: float = cellf * (0.36 + 0.28 * f)
		_add_box(root, tw * 0.16, cellf * 0.13, cellf * 0.05, Color(0.62, 0.8, 0.95),
				Vector3(-tw * 0.27, yy, td * 0.52))
		_add_box(root, tw * 0.16, cellf * 0.13, cellf * 0.05, Color(0.62, 0.8, 0.95),
				Vector3(tw * 0.27, yy, td * 0.52))
		_add_box(root, tw * 0.34, cellf * 0.1, cellf * 0.16, base.lightened(0.25),
				Vector3(0, yy, td * 0.55))
		_add_box(root, tw * 0.16, cellf * 0.13, cellf * 0.05, Color(0.55, 0.72, 0.88),
				Vector3(-tw * 0.27, yy, -td * 0.52))
		_add_box(root, tw * 0.16, cellf * 0.13, cellf * 0.05, Color(0.55, 0.72, 0.88),
				Vector3(tw * 0.27, yy, -td * 0.52))
		_add_box(root, cellf * 0.05, cellf * 0.13, td * 0.16, Color(0.55, 0.72, 0.88),
				Vector3(tw * 0.52, yy, 0))
	# 入口门廊（深色门 + 雨棚）
	_add_box(root, tw * 0.2, cellf * 0.22, cellf * 0.1, Color(0.32, 0.24, 0.2),
			Vector3(0, cellf * 0.11, td * 0.53))
	_add_box(root, tw * 0.26, cellf * 0.04, cellf * 0.18, base.darkened(0.15),
			Vector3(0, cellf * 0.26, td * 0.54))
	# 坡屋顶 + 屋脊
	var roof := _prism(tw * 1.04, cellf * 0.3, td * 1.04, base.darkened(0.22))
	roof.position = Vector3(0, body_h + cellf * 0.15, 0)
	roof.rotation_degrees = Vector3(0, 0, 90)
	root.add_child(roof)
	_add_box(root, tw * 1.04, cellf * 0.06, cellf * 0.08, base.darkened(0.35),
			Vector3(0, body_h + cellf * 0.3, 0))


# ========== 办公楼：玻璃幕墙写字楼（四面幕墙+楼板线+竖向楣条+屋顶机房） ==========

static func _build_office(root: Node3D, tw: float, td: float, cellf: float, base: Color, level: int) -> void:
	var floors: int = 3 + mini(level, 4)  # 3~7 层
	var body_h: float = cellf * (0.4 + 0.24 * floors)
	# 核心筒（比幕墙小一圈）
	_add_box(root, tw * 0.8, body_h, td * 0.8, base, Vector3(0, body_h * 0.5, 0))
	# 玻璃幕墙（四面半透明）
	var glass: StandardMaterial3D = _make_mat(Color(0.6, 0.85, 1.0, 0.5), 0.08, 0.55)
	_add_box_mat(root, tw, body_h, cellf * 0.04, glass, Vector3(0, body_h * 0.5, td * 0.42))
	_add_box_mat(root, tw, body_h, cellf * 0.04, glass, Vector3(0, body_h * 0.5, -td * 0.42))
	_add_box_mat(root, cellf * 0.04, body_h, td, glass, Vector3(tw * 0.42, body_h * 0.5, 0))
	_add_box_mat(root, cellf * 0.04, body_h, td, glass, Vector3(-tw * 0.42, body_h * 0.5, 0))
	# 楼层楼板线
	for f: int in range(floors + 1):
		_add_box(root, tw * 0.86, cellf * 0.045, td * 0.86, base.lightened(0.3),
				Vector3(0, cellf * (0.42 + 0.24 * f), 0))
	# 竖向幕墙楣条（正面 4 根）
	for i: int in range(4):
		var gx: float = (i - 1.5) * tw * 0.22
		_add_box(root, cellf * 0.045, body_h, cellf * 0.05, base.darkened(0.25),
				Vector3(gx, body_h * 0.5, td * 0.45))
	# 顶层设备楼（机房+水箱）
	_add_box(root, tw * 0.5, cellf * 0.3, td * 0.5, base.darkened(0.15),
			Vector3(tw * 0.12, body_h + cellf * 0.15, 0))
	_add_box(root, cellf * 0.2, cellf * 0.2, cellf * 0.2, Color(0.75, 0.78, 0.85),
			Vector3(-tw * 0.18, body_h + cellf * 0.1, td * 0.12))
	# 入口玻璃门厅
	_add_box_mat(root, tw * 0.4, cellf * 0.3, cellf * 0.12, glass, Vector3(0, cellf * 0.15, td * 0.44))


# ========== 学校：校园教学楼（L 形楼体 + 钟楼旗杆 + 操场跑道） ==========

static func _build_school(root: Node3D, tw: float, td: float, cellf: float, base: Color, level: int) -> void:
	var wing_h: float = cellf * (0.55 + 0.18 * mini(level + 1, 4))
	# L 形两翼
	_add_box(root, tw * 0.62, wing_h, td * 0.5, base, Vector3(-tw * 0.17, wing_h * 0.5, -td * 0.2))
	_add_box(root, tw * 0.34, wing_h, td * 0.92, base, Vector3(tw * 0.3, wing_h * 0.5, 0))
	# 每层窗格
	for f: int in range(1 + mini(level, 3)):
		var yy: float = cellf * (0.3 + 0.24 * f)
		for i: int in range(3):
			_add_box(root, cellf * 0.12, cellf * 0.12, cellf * 0.04, Color(0.62, 0.8, 0.95),
					Vector3(-tw * 0.36 + i * tw * 0.19, yy, -td * 0.02))
		_add_box(root, cellf * 0.12, cellf * 0.12, cellf * 0.04, Color(0.62, 0.8, 0.95),
				Vector3(tw * 0.3, yy, td * 0.47))
	# 钟楼（高塔 + 四面钟盘 + 尖顶）
	var tower_h: float = wing_h + cellf * 0.9
	_add_box(root, cellf * 0.3, tower_h, cellf * 0.3, base.lightened(0.12),
			Vector3(-tw * 0.17, tower_h * 0.5, td * 0.2))
	_add_box(root, cellf * 0.16, cellf * 0.14, cellf * 0.03, Color(1, 0.95, 0.6),
			Vector3(-tw * 0.17, wing_h + cellf * 0.5, td * 0.2 + cellf * 0.16))
	_add_box(root, cellf * 0.16, cellf * 0.14, cellf * 0.03, Color(1, 0.95, 0.6),
			Vector3(-tw * 0.17, wing_h + cellf * 0.5, td * 0.2 - cellf * 0.16))
	var spike := _cone(cellf * 0.14, cellf * 0.36, base.darkened(0.2))
	spike.position = Vector3(-tw * 0.17, tower_h + cellf * 0.18, td * 0.2)
	root.add_child(spike)
	# 旗杆 + 红旗
	var pole := _cyl(cellf * 0.02, cellf * 0.02, cellf * 0.7, Color(0.9, 0.9, 0.95))
	pole.position = Vector3(tw * 0.3, cellf * 0.35, -td * 0.32)
	root.add_child(pole)
	_add_box(root, cellf * 0.22, cellf * 0.09, cellf * 0.04, Color(0.88, 0.35, 0.4),
			Vector3(tw * 0.3 + cellf * 0.11, cellf * 0.66, -td * 0.32))
	# 操场跑道（红色矩形环 + 草地）：4 条边框盒
	var hw: float = tw * 0.45
	var hd: float = td * 0.38
	var track_c: float = td * 0.2
	var tr: float = cellf * 0.05
	var track_color := Color(0.85, 0.35, 0.3)
	_add_box(root, hw, cellf * 0.02, tr, track_color, Vector3(0, cellf * 0.03, track_c - hd * 0.5))
	_add_box(root, hw, cellf * 0.02, tr, track_color, Vector3(0, cellf * 0.03, track_c + hd * 0.5))
	_add_box(root, tr, cellf * 0.02, hd, track_color, Vector3(-hw * 0.5, cellf * 0.03, track_c))
	_add_box(root, tr, cellf * 0.02, hd, track_color, Vector3(hw * 0.5, cellf * 0.03, track_c))
	_add_box(root, hw - tr * 2, cellf * 0.02, hd - tr * 2, Color(0.3, 0.62, 0.36),
			Vector3(0, cellf * 0.025, track_c))


# ========== 医院：标准医院大楼（白墙 + 蓝窗带 + 红十字 + 屋顶停机坪） ==========

static func _build_hospital(root: Node3D, tw: float, td: float, cellf: float, base: Color, level: int) -> void:
	var floors: int = 2 + mini(level, 3)  # 2~5 层
	var body_h: float = cellf * (0.55 + 0.26 * floors)
	# 主体 + 基座
	_add_box(root, tw, body_h, td, base, Vector3(0, body_h * 0.5, 0))
	_add_box(root, tw, cellf * 0.2, td, base.darkened(0.1), Vector3(0, cellf * 0.1, 0))
	# 每层蓝色窗带（三面）
	for f: int in range(floors):
		var yy: float = cellf * (0.36 + 0.26 * f)
		_add_box(root, tw * 0.78, cellf * 0.1, cellf * 0.04, Color(0.35, 0.55, 0.85),
				Vector3(0, yy, td * 0.52))
		_add_box(root, tw * 0.78, cellf * 0.1, cellf * 0.04, Color(0.35, 0.55, 0.85),
				Vector3(0, yy, -td * 0.52))
		_add_box(root, cellf * 0.04, cellf * 0.1, td * 0.6, Color(0.35, 0.55, 0.85),
				Vector3(tw * 0.52, yy, 0))
	# 红十字（圆形白底 + 红字）
	var cross_bg := _cyl(cellf * 0.14, cellf * 0.14, cellf * 0.03, Color(0.96, 0.96, 0.98))
	cross_bg.rotation_degrees = Vector3(90, 0, 0)
	cross_bg.position = Vector3(0, body_h * 0.62, td * 0.53)
	root.add_child(cross_bg)
	_add_box(root, cellf * 0.16, cellf * 0.045, cellf * 0.03, Color(0.9, 0.16, 0.2),
			Vector3(0, body_h * 0.62, td * 0.55))
	_add_box(root, cellf * 0.045, cellf * 0.16, cellf * 0.03, Color(0.9, 0.16, 0.2),
			Vector3(0, body_h * 0.62, td * 0.55))
	# 入口雨棚
	_add_box(root, tw * 0.34, cellf * 0.05, cellf * 0.2, base.lightened(0.12),
			Vector3(0, cellf * 0.32, td * 0.52))
	_add_box(root, tw * 0.2, cellf * 0.2, cellf * 0.05, Color(0.3, 0.35, 0.45),
			Vector3(0, cellf * 0.1, td * 0.53))
	# 屋顶停机坪（灰圆盘 + H）
	var pad := _cyl(cellf * 0.4, cellf * 0.4, cellf * 0.02, Color(0.5, 0.52, 0.58))
	pad.position = Vector3(0, body_h + cellf * 0.01, 0)
	root.add_child(pad)
	_add_box(root, cellf * 0.22, cellf * 0.02, cellf * 0.07, Color(0.95, 0.35, 0.3),
			Vector3(0, body_h + cellf * 0.03, 0))
	_add_box(root, cellf * 0.07, cellf * 0.02, cellf * 0.22, Color(0.95, 0.35, 0.3),
			Vector3(0, body_h + cellf * 0.03, 0))


# ========== 金融中心：分段收分摩天大楼（三重塔身 + 玻璃竖条 + 金色尖顶） ==========

static func _build_finance(root: Node3D, tw: float, td: float, cellf: float, base: Color, level: int) -> void:
	# 裙楼
	_add_box(root, tw, cellf * 0.5, td, base.darkened(0.12), Vector3(0, cellf * 0.25, 0))
	# 三阶塔身（下宽上窄阶梯收分，参考金茂大厦）
	var seg_w: Array[float] = [0.86, 0.62, 0.4]
	var seg_h: Array[float] = [cellf * (0.5 + 0.1 * level), cellf * (0.5 + 0.08 * level), cellf * (0.4 + 0.06 * level)]
	var y_pos: float = cellf * 0.5
	for s: int in range(3):
		var sw: float = tw * seg_w[s]
		var sd: float = td * seg_w[s]
		_add_box(root, sw, seg_h[s], sd, base.darkened(0.05 * s), Vector3(0, y_pos + seg_h[s] * 0.5, 0))
		# 每段玻璃竖条（正面）
		var cols: int = 3 + s * 2
		for i: int in range(cols):
			var gx: float = (i - (cols - 1) * 0.5) * (sw * 0.88 / cols)
			_add_box(root, sw * 0.06, seg_h[s] * 0.9, cellf * 0.04, Color(0.75, 0.9, 1.0, 0.75),
					Vector3(gx, y_pos + seg_h[s] * 0.5, sd * 0.51))
		# 分段过渡檐
		_add_box(root, sw * 1.06, cellf * 0.05, sd * 1.06, base.darkened(0.25),
				Vector3(0, y_pos + seg_h[s], 0))
		y_pos += seg_h[s]
	# 顶部金色尖顶 + 球
	var spire := _cone(tw * 0.1, cellf * 0.5, base.lightened(0.4))
	spire.position = Vector3(0, y_pos + cellf * 0.25, 0)
	root.add_child(spire)
	var orb := _sphere(cellf * 0.1, base.lightened(0.55))
	orb.position = Vector3(0, y_pos + cellf * 0.55, 0)
	root.add_child(orb)


# ========== 通用（备用类型） ==========

static func _build_generic(root: Node3D, tw: float, td: float, cellf: float, base: Color, level: int) -> void:
	var body_h: float = cellf * (0.55 + 0.1 * mini(level, 3))
	_add_box(root, tw, body_h, td, base, Vector3(0, body_h * 0.5, 0))
	_add_box(root, tw * 1.04, cellf * 0.08, td * 1.04, base.darkened(0.2),
			Vector3(0, body_h + cellf * 0.04, 0))


# ========== 基础几何工具 ==========

static func _add_box(parent: Node3D, sx: float, sy: float, sz: float, color: Color, pos: Vector3) -> void:
	_add_box_mat(parent, sx, sy, sz, _make_mat(color), pos)


static func _add_box_mat(parent: Node3D, sx: float, sy: float, sz: float, mat: StandardMaterial3D, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(maxf(sx, 0.02), maxf(sy, 0.02), maxf(sz, 0.02))
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


## 标准材质（roughness/metallic 可调；透明度 >1 时启用 ALPHA）
static func _make_mat(color: Color, roughness: float = 0.75, metallic: float = 0.05) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if color.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _prism(sx: float, sy: float, sz: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(sx, sy, sz)
	mi.mesh = prism
	mi.material_override = _make_mat(color)
	return mi


static func _cone(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0
	cyl.bottom_radius = radius
	cyl.height = height
	mi.mesh = cyl
	mi.material_override = _make_mat(color)
	return mi


static func _cyl(rt: float, rb: float, h: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = rt
	cyl.bottom_radius = rb
	cyl.height = h
	mi.mesh = cyl
	mi.material_override = _make_mat(color)
	return mi


static func _sphere(r: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = r
	sp.height = r * 2.0
	mi.mesh = sp
	mi.material_override = _make_mat(color)
	return mi
