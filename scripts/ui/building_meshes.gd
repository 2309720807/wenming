class_name BuildingMeshes
extends RefCounted

## 程序化低多边形建筑模型（以真实建筑为模板）
## 住宅=中国多层住宅楼；办公楼=玻璃幕墙写字楼；学校=校园教学楼+旗杆+钟楼；
## 医院=现代医院大楼+屋顶停机坪；金融中心=分段收分摩天大楼（参考金茂大厦阶梯式塔身）
## 数据驱动：buildings.json 的 id/color/width/height；level 影响层数（升级长高）
## 全部由 BoxMesh/PrismMesh/CylinderMesh/SphereMesh 程序化组合，无需外部模型

const ELF: float = 0.86  # 建筑占地系数（建筑间留缝）

# === 程序化墙面纹理缓存（同图案同色复用，避免每建筑重建 Image） ===
static var _tex_cache: Dictionary = {}


## 生成砖墙纹理（深灰砖缝 + 浅色砖块，交错排列），256×256
static func _brick_texture(brick: Color, mortar: Color) -> ImageTexture:
	var key: String = "brick|%s|%s" % [brick, mortar]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(mortar)
	var bw: int = 64   # 砖块宽（像素）
	var bh: int = 32   # 砖块高
	for row: int in range(256 / bh):
		var off: int = bw / 2 if row % 2 == 1 else 0
		for col: int in range(256 / bw + 1):
			var x: int = col * bw - off
			img.fill_rect(Rect2i(x, row * bh + 1, bw - 2, bh - 2), brick)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


## 生成瓷砖墙面纹理（细缝网格，白色/浅色瓷砖），256×256
static func _tile_texture(tile: Color, seam: Color) -> ImageTexture:
	var key: String = "tile|%s|%s" % [tile, seam]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(seam)
	var tw: int = 32
	for row: int in range(256 / tw + 1):
		for col: int in range(256 / tw + 1):
			img.fill_rect(Rect2i(col * tw + 1, row * tw + 1, tw - 2, tw - 2), tile)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


## 生成玻璃幕墙纹理（竖向窗格条纹，深色玻璃 + 亮竖条），256×256
static func _curtain_texture(glass: Color, mullion: Color) -> ImageTexture:
	var key: String = "curtain|%s|%s" % [glass, mullion]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(glass)
	var mw: int = 16  # 竖楣条宽
	for col: int in range(256 / mw + 1):
		img.fill_rect(Rect2i(col * mw, 0, 3, 256), mullion)
	# 横向楼板线
	for row: int in range(16):
		img.fill_rect(Rect2i(0, row * 40 + 38, 256, 3), mullion)
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


## 带纹理的标准材质（albedo_texture + 基色调制）
static func _make_tex_mat(color: Color, tex: ImageTexture, metallic: float = 0.05, roughness: float = 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = tex
	m.metallic = metallic
	m.roughness = roughness
	if color.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


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
	# 多色调色板（真实中国多层住宅楼配色）：
	# 主墙=识别绿 base；白窗框+蓝玻璃；米白阳台；深灰基座；木棕门；砖红屋顶
	var frame_c := Color(0.93, 0.94, 0.96)  # 白窗框
	var glass_c := Color(0.6, 0.78, 0.95)   # 蓝玻璃
	var balcony_c := Color(0.88, 0.84, 0.72)  # 米白阳台
	var base_c := Color(0.35, 0.37, 0.42)   # 深灰基座
	var door_c := Color(0.42, 0.28, 0.18)   # 木棕门
	var roof_c := Color(0.56, 0.34, 0.28)   # 砖红屋顶
	var floors: int = 2 + mini(level, 4)  # 2~6 层（升级长高）
	var body_h: float = cellf * (0.5 + 0.28 * floors)
	# 主体（绿墙砖纹）+ 深灰基座
	_add_box_tex(root, tw, body_h, td, base, _brick_texture(base.lightened(0.18), base.darkened(0.32)), Vector3(0, body_h * 0.5, 0))
	_add_box_tex(root, tw * 1.02, cellf * 0.18, td * 1.02, base_c, _brick_texture(base_c.lightened(0.1), base_c.darkened(0.2)), Vector3(0, cellf * 0.09, 0))
	# 每层：正面两窗（白框+蓝玻）一阳台、背面两窗、侧面一窗
	for f: int in range(floors):
		var yy: float = cellf * (0.36 + 0.28 * f)
		_add_box(root, tw * 0.2, cellf * 0.17, cellf * 0.03, frame_c,
				Vector3(-tw * 0.27, yy, td * 0.51))
		_add_box(root, tw * 0.16, cellf * 0.13, cellf * 0.05, glass_c,
				Vector3(-tw * 0.27, yy, td * 0.52))
		_add_box(root, tw * 0.2, cellf * 0.17, cellf * 0.03, frame_c,
				Vector3(tw * 0.27, yy, td * 0.51))
		_add_box(root, tw * 0.16, cellf * 0.13, cellf * 0.05, glass_c,
				Vector3(tw * 0.27, yy, td * 0.52))
		_add_box(root, tw * 0.34, cellf * 0.1, cellf * 0.16, balcony_c,
				Vector3(0, yy, td * 0.55))
		_add_box(root, tw * 0.2, cellf * 0.17, cellf * 0.03, frame_c,
				Vector3(-tw * 0.27, yy, -td * 0.51))
		_add_box(root, tw * 0.16, cellf * 0.13, cellf * 0.05, Color(0.55, 0.72, 0.88),
				Vector3(-tw * 0.27, yy, -td * 0.52))
		_add_box(root, tw * 0.2, cellf * 0.17, cellf * 0.03, frame_c,
				Vector3(tw * 0.27, yy, -td * 0.51))
		_add_box(root, tw * 0.16, cellf * 0.13, cellf * 0.05, Color(0.55, 0.72, 0.88),
				Vector3(tw * 0.27, yy, -td * 0.52))
		_add_box(root, cellf * 0.05, cellf * 0.13, td * 0.16, Color(0.55, 0.72, 0.88),
				Vector3(tw * 0.52, yy, 0))
	# 入口门廊（木棕门 + 雨棚）
	_add_box(root, tw * 0.2, cellf * 0.22, cellf * 0.1, door_c,
			Vector3(0, cellf * 0.11, td * 0.53))
	_add_box(root, tw * 0.26, cellf * 0.04, cellf * 0.18, base.darkened(0.15),
			Vector3(0, cellf * 0.26, td * 0.54))
	# 双坡人字形屋顶（屋脊沿 X，SurfaceTool 手工构建，法线朝外）
	# 抬高 1% 格防止与楼体顶面共面 z-fighting（视觉上仍贴合楼顶）
	var roof := _gable_roof(tw * 1.04, td * 1.04, cellf * 0.3, roof_c)
	roof.position = Vector3(0, body_h + cellf * 0.01, 0)
	root.add_child(roof)


# ========== 办公楼：玻璃幕墙写字楼（四面幕墙+楼板线+竖向楣条+屋顶机房） ==========

static func _build_office(root: Node3D, tw: float, td: float, cellf: float, base: Color, level: int) -> void:
	# 多色调色板（现代玻璃幕墙写字楼）：深蓝灰核心筒/蓝玻璃幕墙/银灰楣条/白楼板/灰白设备
	var core_c := base.darkened(0.12)          # 核心筒深蓝灰
	var glass: StandardMaterial3D = _make_mat(Color(0.58, 0.8, 0.98, 0.55), 0.08, 0.55)
	var mullion_c := Color(0.74, 0.78, 0.85)   # 银灰楣条
	var slab_c := Color(0.93, 0.94, 0.96)      # 白色楼板线
	var mech_c := Color(0.72, 0.75, 0.8)       # 设备楼灰
	var tank_c := Color(0.6, 0.72, 0.85)       # 水箱蓝灰
	var floors: int = 3 + mini(level, 4)  # 3~7 层
	var body_h: float = cellf * (0.4 + 0.24 * floors)
	# 核心筒（比幕墙小一圈，玻璃幕墙纹理）
	_add_box_tex(root, tw * 0.8, body_h, td * 0.8, core_c,
			_curtain_texture(core_c.lightened(0.12), core_c.darkened(0.3)), Vector3(0, body_h * 0.5, 0))
	# 玻璃幕墙（四面半透明）
	_add_box_mat(root, tw, body_h, cellf * 0.04, glass, Vector3(0, body_h * 0.5, td * 0.42))
	_add_box_mat(root, tw, body_h, cellf * 0.04, glass, Vector3(0, body_h * 0.5, -td * 0.42))
	_add_box_mat(root, cellf * 0.04, body_h, td, glass, Vector3(tw * 0.42, body_h * 0.5, 0))
	_add_box_mat(root, cellf * 0.04, body_h, td, glass, Vector3(-tw * 0.42, body_h * 0.5, 0))
	# 楼层楼板线（白）
	for f: int in range(floors + 1):
		_add_box(root, tw * 0.86, cellf * 0.045, td * 0.86, slab_c,
				Vector3(0, cellf * (0.42 + 0.24 * f), 0))
	# 竖向幕墙楣条（银灰，正面 4 根）
	for i: int in range(4):
		var gx: float = (i - 1.5) * tw * 0.22
		_add_box(root, cellf * 0.045, body_h, cellf * 0.05, mullion_c,
				Vector3(gx, body_h * 0.5, td * 0.45))
	# 顶层设备楼（灰机房 + 蓝灰水箱）
	_add_box(root, tw * 0.5, cellf * 0.3, td * 0.5, mech_c,
			Vector3(tw * 0.12, body_h + cellf * 0.15, 0))
	_add_box(root, cellf * 0.2, cellf * 0.2, cellf * 0.2, tank_c,
			Vector3(-tw * 0.18, body_h + cellf * 0.1, td * 0.12))
	# 入口玻璃门厅
	_add_box_mat(root, tw * 0.4, cellf * 0.3, cellf * 0.12, glass, Vector3(0, cellf * 0.15, td * 0.44))


# ========== 学校：校园教学楼（L 形楼体 + 钟楼旗杆 + 操场跑道） ==========

static func _build_school(root: Node3D, tw: float, td: float, cellf: float, base: Color, level: int) -> void:
	# 多色调色板（校园配色）：米黄主楼/红砖裙线/白窗框蓝窗/深灰塔帽/金钟盘/红跑道/绿球场
	var wall_c := Color(0.9, 0.84, 0.66)      # 米黄教学楼
	var brick_c := Color(0.72, 0.42, 0.32)    # 红砖腰线
	var frame_c := Color(0.95, 0.95, 0.94)    # 白窗框
	var glass_c := Color(0.6, 0.78, 0.95)     # 蓝玻璃
	var tower_c := Color(0.45, 0.35, 0.5)     # 钟楼深紫灰
	var cap_c := Color(0.3, 0.32, 0.38)       # 深灰塔帽
	var clock_c := Color(1.0, 0.92, 0.55)     # 金色钟盘
	var wing_h: float = cellf * (0.55 + 0.18 * mini(level + 1, 4))
	# L 形两翼（米黄砖纹）+ 红砖腰线
	_add_box_tex(root, tw * 0.62, wing_h, td * 0.5, wall_c,
			_brick_texture(wall_c.lightened(0.06), wall_c.darkened(0.22)), Vector3(-tw * 0.17, wing_h * 0.5, -td * 0.2))
	_add_box_tex(root, tw * 0.34, wing_h, td * 0.92, wall_c,
			_brick_texture(wall_c.lightened(0.06), wall_c.darkened(0.22)), Vector3(tw * 0.3, wing_h * 0.5, 0))
	_add_box(root, tw * 0.62, cellf * 0.12, td * 0.52, brick_c, Vector3(-tw * 0.17, cellf * 0.06, -td * 0.2))
	# 每层窗格（白框+蓝玻）
	for f: int in range(1 + mini(level, 3)):
		var yy: float = cellf * (0.3 + 0.24 * f)
		for i: int in range(3):
			_add_box(root, cellf * 0.16, cellf * 0.16, cellf * 0.03, frame_c,
					Vector3(-tw * 0.36 + i * tw * 0.19, yy, -td * 0.02))
			_add_box(root, cellf * 0.12, cellf * 0.12, cellf * 0.04, glass_c,
					Vector3(-tw * 0.36 + i * tw * 0.19, yy, -td * 0.03))
		_add_box(root, cellf * 0.16, cellf * 0.16, cellf * 0.03, frame_c,
				Vector3(tw * 0.3, yy, td * 0.46))
		_add_box(root, cellf * 0.12, cellf * 0.12, cellf * 0.04, glass_c,
				Vector3(tw * 0.3, yy, td * 0.47))
	# 钟楼（深紫灰高塔 + 金色钟盘 + 深灰尖顶）
	var tower_h: float = wing_h + cellf * 0.9
	_add_box(root, cellf * 0.3, tower_h, cellf * 0.3, tower_c,
			Vector3(-tw * 0.17, tower_h * 0.5, td * 0.2))
	_add_box(root, cellf * 0.16, cellf * 0.14, cellf * 0.03, clock_c,
			Vector3(-tw * 0.17, wing_h + cellf * 0.5, td * 0.2 + cellf * 0.16))
	_add_box(root, cellf * 0.16, cellf * 0.14, cellf * 0.03, clock_c,
			Vector3(-tw * 0.17, wing_h + cellf * 0.5, td * 0.2 - cellf * 0.16))
	var spike := _cone(cellf * 0.14, cellf * 0.36, cap_c)
	spike.position = Vector3(-tw * 0.17, tower_h + cellf * 0.18, td * 0.2)
	root.add_child(spike)
	# 旗杆 + 红旗
	var pole := _cyl(cellf * 0.02, cellf * 0.02, cellf * 0.7, Color(0.9, 0.9, 0.95))
	pole.position = Vector3(tw * 0.3, cellf * 0.35, -td * 0.32)
	root.add_child(pole)
	_add_box(root, cellf * 0.22, cellf * 0.09, cellf * 0.04, Color(0.88, 0.35, 0.4),
			Vector3(tw * 0.3 + cellf * 0.11, cellf * 0.66, -td * 0.32))
	# 操场跑道（红色矩形环 + 绿色球场内场）
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
	# 多色调色板（医院配色）：白墙主楼/浅蓝窗带/浅灰基座/红十字红/蓝白雨棚/灰停机坪
	var wall_c := Color(0.94, 0.95, 0.96)     # 白墙
	var window_c := Color(0.42, 0.62, 0.88)   # 浅蓝窗带
	var sill_c := Color(0.72, 0.75, 0.8)      # 浅灰基座
	var cross_red := Color(0.9, 0.16, 0.2)    # 红十字红
	var canopy_c := Color(0.45, 0.62, 0.85)   # 蓝白雨棚
	var pad_c := Color(0.45, 0.47, 0.52)      # 停机坪灰
	var floors: int = 2 + mini(level, 3)  # 2~5 层
	var body_h: float = cellf * (0.55 + 0.26 * floors)
	# 白墙主体（瓷砖纹理）+ 浅灰基座
	_add_box_tex(root, tw, body_h, td, wall_c,
			_tile_texture(wall_c.lightened(0.02), wall_c.darkened(0.12)), Vector3(0, body_h * 0.5, 0))
	_add_box_tex(root, tw, cellf * 0.2, td, sill_c,
			_tile_texture(sill_c.lightened(0.03), sill_c.darkened(0.15)), Vector3(0, cellf * 0.1, 0))
	# 每层浅蓝窗带（三面）+ 白色窗台线
	for f: int in range(floors):
		var yy: float = cellf * (0.36 + 0.26 * f)
		_add_box(root, tw * 0.78, cellf * 0.1, cellf * 0.04, window_c,
				Vector3(0, yy, td * 0.52))
		_add_box(root, tw * 0.78, cellf * 0.1, cellf * 0.04, window_c,
				Vector3(0, yy, -td * 0.52))
		_add_box(root, cellf * 0.04, cellf * 0.1, td * 0.6, window_c,
				Vector3(tw * 0.52, yy, 0))
	# 红十字（圆形白底 + 红字）
	var cross_bg := _cyl(cellf * 0.14, cellf * 0.14, cellf * 0.03, Color(0.96, 0.96, 0.98))
	cross_bg.rotation_degrees = Vector3(90, 0, 0)
	cross_bg.position = Vector3(0, body_h * 0.62, td * 0.53)
	root.add_child(cross_bg)
	_add_box(root, cellf * 0.16, cellf * 0.045, cellf * 0.03, cross_red,
			Vector3(0, body_h * 0.62, td * 0.55))
	_add_box(root, cellf * 0.045, cellf * 0.16, cellf * 0.03, cross_red,
			Vector3(0, body_h * 0.62, td * 0.55))
	# 入口蓝白雨棚 + 深蓝门
	_add_box(root, tw * 0.34, cellf * 0.05, cellf * 0.2, canopy_c,
			Vector3(0, cellf * 0.32, td * 0.52))
	_add_box(root, tw * 0.2, cellf * 0.2, cellf * 0.05, Color(0.3, 0.36, 0.5),
			Vector3(0, cellf * 0.1, td * 0.53))
	# 屋顶停机坪（深灰圆盘 + 红色 H）
	var pad := _cyl(cellf * 0.4, cellf * 0.4, cellf * 0.02, pad_c)
	pad.position = Vector3(0, body_h + cellf * 0.01, 0)
	root.add_child(pad)
	_add_box(root, cellf * 0.22, cellf * 0.02, cellf * 0.07, cross_red,
			Vector3(0, body_h + cellf * 0.03, 0))
	_add_box(root, cellf * 0.07, cellf * 0.02, cellf * 0.22, cross_red,
			Vector3(0, body_h + cellf * 0.03, 0))


# ========== 金融中心：分段收分摩天大楼（三重塔身 + 玻璃竖条 + 金色尖顶） ==========

static func _build_finance(root: Node3D, tw: float, td: float, cellf: float, base: Color, level: int) -> void:
	# 多色调色板（金融中心配色）：金褐裙楼/金塔身/深蓝玻璃竖条/深灰檐/亮金顶球
	var podium_c := Color(0.38, 0.34, 0.3)    # 深褐金裙楼
	var glass_dark := Color(0.25, 0.38, 0.62, 0.85)  # 深蓝玻璃幕
	var ledge_c := Color(0.3, 0.3, 0.34)      # 深灰檐
	var gold_c := base                          # 金主色
	# 裙楼（深褐金砖纹）
	_add_box_tex(root, tw, cellf * 0.5, td, podium_c,
			_brick_texture(podium_c.lightened(0.1), podium_c.darkened(0.25)), Vector3(0, cellf * 0.25, 0))
	# 三阶塔身（下宽上窄阶梯收分，参考金茂大厦）
	var seg_w: Array[float] = [0.86, 0.62, 0.4]
	var seg_h: Array[float] = [cellf * (0.5 + 0.1 * level), cellf * (0.5 + 0.08 * level), cellf * (0.4 + 0.06 * level)]
	var y_pos: float = cellf * 0.5
	for s: int in range(3):
		var sw: float = tw * seg_w[s]
		var sd: float = td * seg_w[s]
		_add_box_tex(root, sw, seg_h[s], sd, gold_c.darkened(0.05 * s),
				_curtain_texture(gold_c.darkened(0.02 * s), gold_c.darkened(0.3)), Vector3(0, y_pos + seg_h[s] * 0.5, 0))
		# 每段深蓝玻璃竖条（正面）
		var cols: int = 3 + s * 2
		for i: int in range(cols):
			var gx: float = (i - (cols - 1) * 0.5) * (sw * 0.88 / cols)
			_add_box(root, sw * 0.06, seg_h[s] * 0.9, cellf * 0.04, glass_dark,
					Vector3(gx, y_pos + seg_h[s] * 0.5, sd * 0.51))
		# 分段过渡檐（深灰）
		_add_box(root, sw * 1.06, cellf * 0.05, sd * 1.06, ledge_c,
				Vector3(0, y_pos + seg_h[s], 0))
		y_pos += seg_h[s]
	# 顶部金色尖顶 + 金球
	var spire := _cone(tw * 0.1, cellf * 0.5, gold_c.lightened(0.4))
	spire.position = Vector3(0, y_pos + cellf * 0.25, 0)
	root.add_child(spire)
	var orb := _sphere(cellf * 0.1, gold_c.lightened(0.55))
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


## 带纹理的盒子（砖面/幕墙/瓷砖贴图）
static func _add_box_tex(parent: Node3D, sx: float, sy: float, sz: float, color: Color, tex: ImageTexture, pos: Vector3) -> void:
	_add_box_mat(parent, sx, sy, sz, _make_tex_mat(color, tex), pos)


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


## 双坡人字形屋顶：屋脊沿 X 方向，两个坡面 + 两端山墙三角形（SurfaceTool 构建，法线朝外）
static func _gable_roof(tw: float, td: float, rh: float, color: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx: float = tw * 0.5
	var hz: float = td * 0.5
	# 屋檐四角 / 屋脊两端
	var a := Vector3(-hx, 0, -hz); var b := Vector3(hx, 0, -hz)
	var c := Vector3(hx, 0, hz);  var d := Vector3(-hx, 0, hz)
	var e := Vector3(-hx, rh, 0); var f := Vector3(hx, rh, 0)
	# 前坡（朝 +Z）：d-c-f / d-f-e
	st.add_vertex(d); st.add_vertex(c); st.add_vertex(f)
	st.add_vertex(d); st.add_vertex(f); st.add_vertex(e)
	# 后坡（朝 -Z）：a-f-b / a-e-f
	st.add_vertex(a); st.add_vertex(f); st.add_vertex(b)
	st.add_vertex(a); st.add_vertex(e); st.add_vertex(f)
	# 山墙（朝 +X）：b-f-c；山墙（朝 -X）：a-d-e
	st.add_vertex(b); st.add_vertex(f); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(d); st.add_vertex(e)
	# 封底面（朝 -Y）：a-c-b / a-d-c（封闭下侧，俯视低角度不露内腔）
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
	st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := _make_mat(color)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # 双面渲染：任意视角均实心（修复低俯仰角屋顶"透明"）
	mi.material_override = mat
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
