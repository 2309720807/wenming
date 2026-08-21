extends Control
class_name GridView

## 3D 地图视图：程序化 3D 地面/建筑/障碍 + 轨道摄像机（滚轮缩放/左键旋转/中键右键平移）+ 射线拾取建造
## 设计依据：docs/design/game_design.md 3.7（3D 化，参考《模拟城市：我是市长》）
## 与 explore_map 保持既有信号/接口契约：hover_changed / cell_clicked / preview / demolish / zoom / 动画表

signal hover_changed(cell: Vector2i)
signal cell_clicked(cell: Vector2i)
signal preview_cancel_requested  # 右键单击取消预选建造
signal drag_place_requested(cell: Vector2i)  # Shift+左键拖动连续建造
signal demolition_requested(rect: Rect2i)   # 批量拆除框选完成
signal demolish_mode_changed(on: bool)      # 拆除模式开关

const ZOOM_MIN: float = 0.4
const ZOOM_MAX: float = 3.0
const DRAG_THRESHOLD: float = 6.0  # 左键超过该像素距离视为旋转视角而非单击

const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")

# === 摄像机参数 ===
const CAM_DIST_BASE: float = 230.0      # zoom=1.0 时的摄像机距离
const CAM_DIST_MIN: float = 45.0
const CAM_DIST_MAX: float = 2600.0
const CAM_YAW_INIT: float = -0.7
const CAM_PITCH_INIT: float = 0.55
const CAM_PITCH_MIN: float = 0.12
const CAM_PITCH_MAX: float = 1.35
const ROTATE_SPEED: float = 0.006
const PAN_SPEED: float = 1.4

var zoom: float = 1.0  # 缩放因子（与 BuildingSystem.map_zoom 同步，摄像机距离 = CAM_DIST_BASE / zoom）
var hover_cell: Vector2i = Vector2i(-1, -1)
var preview_item: Dictionary = {}  # 当前选中待放置的建筑配置
var demolish_mode: bool = false
# 动画表（兼容旧接口：explore_map / BuildingFeedback 写入，3D 中用于出生/完工表现）
var place_animations: Dictionary = {}    # "x,y" -> 已播放时长
var completion_effects: Dictionary = {}  # "x,y" -> 已播放时长

# === 3D 节点 ===
var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _ground_root: Node3D
var _object_root: Node3D
var _highlight: MeshInstance3D  # 悬停高亮格

# === 摄像机状态 ===
var _cam_dist: float = CAM_DIST_BASE
var _yaw: float = CAM_YAW_INIT
var _pitch: float = CAM_PITCH_INIT
var _cam_target: Vector3 = Vector3.ZERO  # 注视点（平移改变）

# === 输入状态 ===
var _mouse_left_down: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _click_armed: bool = false   # 左键按下待判定单击/旋转
var _rotating: bool = false      # 左键拖动旋转视角
var _panning_view: bool = false  # 中键/右键拖动平移
var _last_mouse_pos: Vector2 = Vector2.ZERO
var _last_drag_cell: Vector2i = Vector2i(-1, -1)
var _select_start: Vector2i = Vector2i(-1, -1)
var _select_end: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_3d_world()
	# 恢复缩放（跨场景/跨启动记忆，见 BuildingSystem.map_zoom）
	zoom = clampf(BuildingSystem.map_zoom, _min_zoom(), ZOOM_MAX)
	_cam_dist = CAM_DIST_BASE / maxf(zoom, 0.01)
	_cam_target = _map_center()
	_update_camera()
	# 数据层信号 → 3D 重建/更新
	BuildingSystem.grid_changed.connect(func(_c: Vector2i) -> void: _rebuild_all())
	BuildingSystem.building_placed.connect(func(cell: Vector2i, id: String) -> void: _spawn_building(cell, id))
	BuildingSystem.building_completed.connect(func(cell: Vector2i, id: String) -> void: _flash_building(cell, Color(1, 0.85, 0.35)))
	BuildingSystem.building_upgraded.connect(func(cell: Vector2i, id: String, _lv: int) -> void: _flash_building(cell, Color(0.55, 0.85, 1.0)))
	BuildingSystem.building_demolished.connect(func(cell: Vector2i, _id: String) -> void: _rebuild_all())
	BuildingSystem.obstacle_cleared.connect(func(_c: Vector2i) -> void: _rebuild_all())


# ================= 3D 世界构建 =================

func _build_3d_world() -> void:
	# 子视口容器铺满本控件
	var vpc := SubViewportContainer.new()
	vpc.set_anchors_preset(Control.PRESET_FULL_RECT)
	vpc.stretch = true
	add_child(vpc)
	var vp := SubViewport.new()
	vp.msaa_3d = Viewport.MSAA_4X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.size = Vector2i(maxi(64, int(size.x)), maxi(64, int(size.y)))
	vpc.add_child(vp)
	_viewport = vp
	_world = Node3D.new()
	_world.name = "World3D"
	vp.add_child(_world)
	# 光照（主光 + 补光 + 环境）
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	_world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 130, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.6, 0.75, 1.0)
	_world.add_child(fill)
	var env := WorldEnvironment.new()
	var sky := Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = Color(0.02, 0.05, 0.12)
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color(0.45, 0.6, 0.9)
	sky.ambient_light_energy = 0.6
	env.environment = sky
	_world.add_child(env)
	# 地面与物体根节点
	_ground_root = Node3D.new()
	_ground_root.name = "Ground"
	_world.add_child(_ground_root)
	_object_root = Node3D.new()
	_object_root.name = "Objects"
	_world.add_child(_object_root)
	# 摄像机
	_camera = Camera3D.new()
	_camera.fov = 42.0
	_camera.near = 1.0
	_camera.far = 6000.0
	_world.add_child(_camera)
	# 悬停高亮（格子半透明平面）
	_highlight = MeshInstance3D.new()
	_highlight.visible = false
	_highlight.mesh = _make_flat_quad(1.0, Color(0.5, 0.95, 0.6, 0.35))
	_highlight.material_override = _make_flat_mat(Color(0.5, 0.95, 0.6, 0.35))
	_object_root.add_child(_highlight)
	_rebuild_all()


func _map_center() -> Vector3:
	var cell: float = float(BuildingSystem.cell_size)
	return Vector3(float(BuildingSystem.GRID_W) * cell * 0.5, 0.0, float(BuildingSystem.GRID_H) * cell * 0.5)


func _cell_size_3d() -> float:
	return float(BuildingSystem.cell_size)


## 地面：SurfaceTool 合并所有格子瓦片为单个 Mesh（顶点色区分空地/占用/障碍）+ 格子线
func _build_ground() -> void:
	for child: Node in _ground_root.get_children():
		child.queue_free()
	var cell: float = _cell_size_3d()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cw: int = BuildingSystem.GRID_W
	var ch: int = BuildingSystem.GRID_H
	var vc: int = 0  # 顶点索引计数器（SurfaceTool 无 get_vertex_count）
	for x: int in range(cw):
		for y: int in range(ch):
			var mark: String = str(BuildingSystem.grid[x][y])
			var color: Color
			if mark.begins_with("obs:"):
				color = Color(0.22, 0.3, 0.2, 1.0)  # 障碍格（草绿暗底）
			elif mark == "occ":
				color = Color(0.16, 0.22, 0.34, 1.0)  # 占用
			else:
				color = Color(0.1, 0.16, 0.28, 1.0)  # 空地
			# 瓦片在 Y=0.02 微抬，避免 z-fighting
			var base: Vector3 = Vector3(x * cell, 0.02, y * cell)
			var s: Vector3 = Vector3(cell, 0.0, cell)
			st.set_color(color)
			st.add_vertex(base)
			st.add_vertex(base + Vector3(s.x, 0, 0))
			st.add_vertex(base + Vector3(s.x, 0, s.z))
			st.add_vertex(base + Vector3(0, 0, s.z))
			st.add_index(vc)
			st.add_index(vc + 1)
			st.add_index(vc + 2)
			st.add_index(vc)
			st.add_index(vc + 2)
			st.add_index(vc + 3)
			vc += 4
	var ground := MeshInstance3D.new()
	ground.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	ground.material_override = mat
	_ground_root.add_child(ground)
	# 格子线（ImmediateMesh 画网格边框）
	var lines := ImmediateMesh.new()
	var line_color := Color(0.35, 0.55, 0.85, 0.4)
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for x: int in range(cw + 1):
		var px: float = x * cell
		lines.surface_set_color(line_color)
		lines.surface_add_vertex(Vector3(px, 0.03, 0.0))
		lines.surface_add_vertex(Vector3(px, 0.03, ch * cell))
	for y: int in range(ch + 1):
		var pz: float = y * cell
		lines.surface_set_color(line_color)
		lines.surface_add_vertex(Vector3(0.0, 0.03, pz))
		lines.surface_add_vertex(Vector3(cw * cell, 0.03, pz))
	lines.surface_end()
	var line_mesh := MeshInstance3D.new()
	line_mesh.mesh = lines
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.vertex_color_use_as_albedo = true
	line_mesh.material_override = line_mat
	_ground_root.add_child(line_mesh)


## 重建全部物体（建筑 + 障碍 + 装饰），数据层信号触发
func _rebuild_all() -> void:
	for child: Node in _object_root.get_children():
		if child != _highlight:
			child.queue_free()
	_build_ground()
	_build_obstacles()
	for key: String in BuildingSystem.placed:
		var p: Dictionary = BuildingSystem.placed[key]
		_spawn_building(BuildingSystem.BuildingGrid.key_to_cell(key), p.get("item_id", ""))


# ================= 障碍物 3D =================

func _build_obstacles() -> void:
	var cell: float = _cell_size_3d()
	var cw: int = BuildingSystem.GRID_W
	var ch: int = BuildingSystem.GRID_H
	var anchors: Array[Vector2i] = []
	for x: int in range(cw):
		for y: int in range(ch):
			var mark: String = str(BuildingSystem.grid[x][y])
			if not mark.begins_with("obs:"):
				continue
			var anchor := Vector2i(x, y)
			var obs_id: String = mark.substr(4)
			# 大障碍只按锚点格生成一次（湖泊 2×2 的延伸格是 occ）
			if obs_id == "lake" and anchors.has(anchor):
				continue
			anchors.append(anchor)
			var center: Vector3 = Vector3((x + 0.5) * cell, 0.0, (y + 0.5) * cell)
			match obs_id:
				"tree": _spawn_tree(center, cell)
				"rock": _spawn_rock(center, cell)
				"lake": _spawn_lake(center, cell)


func _spawn_tree(center: Vector3, cell: float) -> void:
	var root := Node3D.new()
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = cell * 0.1
	tm.bottom_radius = cell * 0.16
	tm.height = cell * 0.5
	trunk.mesh = tm
	trunk.position = Vector3(0, cell * 0.25, 0)
	trunk.material_override = _make_std(Color(0.42, 0.3, 0.2))
	root.add_child(trunk)
	var crown := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = cell * 0.32
	cm.height = cell * 0.64
	crown.mesh = cm
	crown.position = Vector3(0, cell * 0.75, 0)
	crown.material_override = _make_std(Color(0.2, 0.5, 0.28))
	root.add_child(crown)
	root.position = center
	_object_root.add_child(root)


func _spawn_rock(center: Vector3, cell: float) -> void:
	var rock := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(cell * 0.72, cell * 0.55, cell * 0.66)
	rock.mesh = mesh
	rock.position = center + Vector3(0, cell * 0.27, 0)
	rock.material_override = _make_std(Color(0.5, 0.52, 0.58))
	_object_root.add_child(rock)


func _spawn_lake(center: Vector3, cell: float) -> void:
	var lake := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(cell * 2.0, cell * 2.0)
	lake.mesh = mesh
	lake.rotation_degrees = Vector3(-90, 0, 0)
	lake.position = center + Vector3(cell * 0.5, 0.08, cell * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.45, 0.8, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.1
	mat.roughness = 0.15
	lake.material_override = mat
	_object_root.add_child(lake)


# ================= 建筑 3D（程序化低多边形仿真） =================

func _spawn_building(cell: Vector2i, item_id: String) -> void:
	var item: Dictionary = BuildingSystem.get_item(item_id)
	if item.is_empty():
		return
	var key: String = "%d,%d" % [cell.x, cell.y]
	var p: Dictionary = BuildingSystem.placed.get(key, {})
	var node: Node3D = _make_building_node(item, p, cell)
	node.name = "B_" + key
	_object_root.add_child(node)
	# 出生动画：从地面升起
	if p.is_empty() or not p.get("completed", false):
		node.scale = Vector3(1, 0.1, 1)
		var tw: Tween = node.create_tween()
		tw.tween_property(node, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 施工中：半透明
	if p.get("op", "") != "":
		_set_node_transparency(node, 0.6)


## 按建筑类型生成低多边形仿真模型（数据驱动 colors/bonuses）
func _make_building_node(item: Dictionary, p: Dictionary, cell: Vector2i) -> Node3D:
	var cellf: float = _cell_size_3d()
	var w: int = int(item.get("width", 1))
	var h: int = int(item.get("height", 1))
	var base: Color = Color(item.get("color", "#6a7fa8"))
	var root := Node3D.new()
	root.position = Vector3((cell.x + w * 0.5) * cellf, 0.0, (cell.y + h * 0.5) * cellf)
	var total_w: float = w * cellf * 0.86
	var total_d: float = h * cellf * 0.86
	var body_h: float = cellf * (0.55 + 0.12 * float(int(item.get("cost", 50)) % 3))
	match item.get("id", ""):
		"finance":
			# 金融中心：高层 + 尖顶塔冠 + 金色
			body_h = cellf * 1.1
			_add_box(root, total_w, body_h, total_d, base, Vector3(0, body_h * 0.5, 0))
			var spire := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = total_w * 0.22
			cone.height = cellf * 0.5
			spire.mesh = cone
			spire.position = Vector3(0, body_h + cellf * 0.25, 0)
			spire.material_override = _make_std(base.lightened(0.35))
			root.add_child(spire)
			_add_box(root, total_w * 0.3, cellf * 0.12, total_d * 0.3, base.lightened(0.4),
					Vector3(-total_w * 0.28, body_h + cellf * 0.06, 0))
		"residence":
			# 住宅：主体 + 斜屋顶
			_add_box(root, total_w, body_h, total_d, base, Vector3(0, body_h * 0.5, 0))
			var roof := MeshInstance3D.new()
			var prism := PrismMesh.new()
			prism.size = Vector3(total_w * 1.02, cellf * 0.4, total_d * 1.02)
			roof.mesh = prism
			roof.position = Vector3(0, body_h + cellf * 0.2, 0)
			roof.rotation_degrees = Vector3(0, 0, 90)
			roof.material_override = _make_std(base.darkened(0.25))
			root.add_child(roof)
			# 烟囱
			_add_box(root, cellf * 0.14, cellf * 0.22, cellf * 0.14, Color(0.5, 0.4, 0.32),
					Vector3(total_w * 0.28, body_h + cellf * 0.4, 0))
		"office":
			# 办公楼：玻璃幕墙（半透明）+ 高光条
			_add_box(root, total_w, cellf * 0.9, total_d, base, Vector3(0, cellf * 0.45, 0))
			var glass := MeshInstance3D.new()
			var glass_box := BoxMesh.new()
			glass_box.size = Vector3(total_w * 0.94, cellf * 0.78, total_d * 0.94)
			glass.mesh = glass_box
			glass.position = Vector3(0, cellf * 0.45, 0)
			var gm := StandardMaterial3D.new()
			gm.albedo_color = Color(0.6, 0.85, 1.0, 0.55)
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.metallic = 0.5
			gm.roughness = 0.1
			glass.material_override = gm
			root.add_child(glass)
			_add_box(root, total_w * 1.04, cellf * 0.06, total_d * 1.04, Color(0.85, 0.95, 1.0),
					Vector3(0, cellf * 0.94, 0))
		"school":
			# 学校：主体 + 旗杆 + 旗帜
			_add_box(root, total_w, body_h, total_d, base, Vector3(0, body_h * 0.5, 0))
			var pole := MeshInstance3D.new()
			var pole_mesh := CylinderMesh.new()
			pole_mesh.top_radius = cellf * 0.02
			pole_mesh.bottom_radius = cellf * 0.03
			pole_mesh.height = cellf * 0.6
			pole.mesh = pole_mesh
			pole.position = Vector3(total_w * 0.38, body_h + cellf * 0.3, 0)
			pole.material_override = _make_std(Color(0.9, 0.9, 0.95))
			root.add_child(pole)
			_add_box(root, cellf * 0.3, cellf * 0.05, cellf * 0.18, Color(0.85, 0.4, 0.5),
					Vector3(total_w * 0.38 + cellf * 0.15, body_h + cellf * 0.55, 0))
		"hospital":
			# 医院：主体 + 红十字
			_add_box(root, total_w, body_h, total_d, base, Vector3(0, body_h * 0.5, 0))
			_add_box(root, cellf * 0.42, cellf * 0.12, cellf * 0.12, Color(0.95, 0.32, 0.34),
					Vector3(0, body_h + cellf * 0.12, 0))
			_add_box(root, cellf * 0.12, cellf * 0.42, cellf * 0.12, Color(0.95, 0.32, 0.34),
					Vector3(0, body_h + cellf * 0.12, 0))
		"garden":
			# 花园：矮基座 + 绿植球
			_add_box(root, total_w, cellf * 0.12, total_d, Color(0.35, 0.45, 0.3), Vector3(0, cellf * 0.06, 0))
			for i: int in range(4):
				var bush := MeshInstance3D.new()
				var sphere := SphereMesh.new()
				sphere.radius = cellf * 0.12
				sphere.height = cellf * 0.24
				bush.mesh = sphere
				bush.position = Vector3((i % 2) * cellf * 0.3 - cellf * 0.15, cellf * 0.24, (i / 2) * cellf * 0.3 - cellf * 0.15)
				bush.material_override = _make_std(Color(0.25, 0.6, 0.3))
				root.add_child(bush)
		"fountain":
			# 喷泉：基座 + 水柱
			_add_box(root, total_w, cellf * 0.2, total_d, Color(0.6, 0.65, 0.7), Vector3(0, cellf * 0.1, 0))
			var jet := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = cellf * 0.08
			cyl.bottom_radius = cellf * 0.08
			cyl.height = cellf * 0.4
			jet.mesh = cyl
			jet.position = Vector3(0, cellf * 0.35, 0)
			var wm := StandardMaterial3D.new()
			wm.albedo_color = Color(0.55, 0.85, 1.0, 0.8)
			wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			jet.material_override = wm
			root.add_child(jet)
		"statue":
			# 雕像：基座 + 人形柱
			_add_box(root, total_w, cellf * 0.15, total_d, Color(0.55, 0.55, 0.6), Vector3(0, cellf * 0.075, 0))
			_add_box(root, cellf * 0.2, cellf * 0.5, cellf * 0.2, Color(0.75, 0.72, 0.65), Vector3(0, cellf * 0.45, 0))
		_:
			# 通用建筑：简单主体
			_add_box(root, total_w, body_h, total_d, base, Vector3(0, body_h * 0.5, 0))
	return root


func _add_box(parent: Node3D, sx: float, sy: float, sz: float, color: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(maxf(sx, 0.02), maxf(sy, 0.02), maxf(sz, 0.02))
	mi.mesh = box
	mi.position = pos
	mi.material_override = _make_std(color)
	parent.add_child(mi)


func _make_std(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.75
	m.metallic = 0.05
	return m


func _make_flat_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _set_node_transparency(node: Node, alpha: float) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			var m: StandardMaterial3D = (child as MeshInstance3D).material_override
			if m != null:
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.albedo_color.a = alpha
			else:
				var nm := _make_std(Color(0.7, 0.7, 0.8, alpha))
				nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				(child as MeshInstance3D).material_override = nm
		_set_node_transparency(child, alpha)


func _flash_building(cell: Vector2i, color: Color) -> void:
	var key: String = "%d,%d" % [cell.x, cell.y]
	var node: Node = _object_root.get_node_or_null("B_" + key)
	if node == null:
		return
	# 完工/升级闪光：金色脉冲环
	var ring := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(_cell_size_3d(), 1.0, _cell_size_3d()) * 1.4
	ring.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.position = (node as Node3D).position + Vector3(0, 0.6, 0)
	_object_root.add_child(ring)
	var tw: Tween = ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * 2.0, 0.6)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.6)
	tw.tween_callback(ring.queue_free)


# ================= 摄像机 =================

func _update_camera() -> void:
	var offset := Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		cos(_yaw) * cos(_pitch)) * _cam_dist
	_camera.position = _cam_target + offset
	_camera.look_at(_cam_target, Vector3.UP)


func _min_zoom() -> float:
	# 动态最小缩放：保证无论如何都能缩放到看到整个地图
	var cell: float = _cell_size_3d()
	var fit: float = CAM_DIST_BASE / maxf(
		maxf(float(BuildingSystem.GRID_W), float(BuildingSystem.GRID_H)) * cell * 1.5, 1.0)
	return minf(ZOOM_MIN, fit)


func set_zoom(new_zoom: float) -> void:
	## 缩放（滚轮）：摄像机距离与 zoom 成反比，同步 BuildingSystem.map_zoom 跨场景/跨启动记忆
	zoom = clampf(new_zoom, _min_zoom(), ZOOM_MAX)
	BuildingSystem.set_map_zoom(zoom)
	_cam_dist = CAM_DIST_BASE / maxf(zoom, 0.01)
	_update_camera()


func _zoom_at(factor: float) -> void:
	## 以光标为锚点缩放：保持光标下的地图点位置不动
	var before: Vector3 = _screen_to_ground(_last_mouse_pos)
	set_zoom(zoom * factor)
	var after: Vector3 = _screen_to_ground(_last_mouse_pos)
	if before != Vector3.ZERO and after != Vector3.ZERO:
		_cam_target += before - after
	_update_camera()


func _screen_to_ground(screen_pos: Vector2) -> Vector3:
	# Godot 4 project_ray_origin/normal 接受视口像素坐标（GridView 局部 = 子视口像素，1:1）
	var ray_origin: Vector3 = _camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = _camera.project_ray_normal(screen_pos)
	if absf(ray_dir.y) < 0.0001:
		return Vector3.ZERO
	var t: float = -ray_origin.y / ray_dir.y
	if t < 0.0:
		return Vector3.ZERO
	return ray_origin + ray_dir * t


func _screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var hit: Vector3 = _screen_to_ground(screen_pos)
	var cell: float = _cell_size_3d()
	if hit == Vector3.ZERO:
		return Vector2i(-1, -1)
	var x: int = int(hit.x / cell)
	var y: int = int(hit.z / cell)
	if x < 0 or y < 0 or x >= BuildingSystem.GRID_W or y >= BuildingSystem.GRID_H:
		return Vector2i(-1, -1)
	return Vector2i(x, y)


# ================= 输入 =================

func _gui_input(event: InputEvent) -> void:
	# 拆除模式：左键拖动框选（屏幕矩形 → 格子包围盒），右键退出
	if demolish_mode:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_select_start = _screen_to_cell(event.position)
				_select_end = _select_start
				_update_hover_highlight()
			else:
				if _select_start.x >= 0 and _select_end.x >= 0:
					demolition_requested.emit(Rect2i(
						mini(_select_start.x, _select_end.x), mini(_select_start.y, _select_end.y),
						abs(_select_end.x - _select_start.x) + 1, abs(_select_end.y - _select_start.y) + 1))
				_select_start = Vector2i(-1, -1)
				_select_end = Vector2i(-1, -1)
				_update_hover_highlight()
			return
		elif event is InputEventMouseMotion:
			if _select_start.x >= 0:
				_select_end = _screen_to_cell(event.position)
				_update_hover_highlight()
			return
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			set_demolish_mode(false)
			return
	# 滚轮缩放（以光标为锚点）
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_zoom_at(1.12)
		return
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_zoom_at(1.0 / 1.12)
		return
	# 中键/右键按下：平移（记录位置）
	if event is InputEventMouseButton 			and (event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT):
		if event.pressed:
			_panning_view = true
			_last_mouse_pos = event.position
		else:
			_panning_view = false
		return
	if event is InputEventMouseMotion:
		# 左键按住超过阈值：切换为旋转视角（不再视为单击）
		if _mouse_left_down and _click_armed and not _rotating \
				and event.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_rotating = true
			_click_armed = false
		if _rotating:
			var delta: Vector2 = event.position - _last_mouse_pos
			_yaw -= delta.x * ROTATE_SPEED
			_pitch = clampf(_pitch - delta.y * ROTATE_SPEED, CAM_PITCH_MIN, CAM_PITCH_MAX)
			_update_camera()
		elif _panning_view:
			var delta: Vector2 = event.position - _last_mouse_pos
			_pan_camera(delta)
		else:
			# 悬停拾取
			var c: Vector2i = _screen_to_cell(event.position)
			if c != hover_cell:
				hover_cell = c
				hover_changed.emit(c)
				_update_hover_highlight()
			# Shift+左键拖动：连续建造
			if _mouse_left_down and not preview_item.is_empty() \
					and event.shift_pressed and c.x >= 0 and c != _last_drag_cell:
				_last_drag_cell = c
				drag_place_requested.emit(c)
		_last_mouse_pos = event.position
		return
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_left_down = event.pressed
		if event.pressed:
			_press_pos = event.position
			_last_mouse_pos = event.position
			_last_drag_cell = Vector2i(-1, -1)
			_click_armed = true
		else:
			_last_drag_cell = Vector2i(-1, -1)
			if _rotating:
				_rotating = false
				_click_armed = false
			elif _click_armed:
				_click_armed = false
				cell_clicked.emit(_screen_to_cell(event.position))
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		# 右键单击（未平移时）取消预选
		if event.pressed and not _panning_view and not preview_item.is_empty():
			preview_item = {}
			preview_cancel_requested.emit()


func _pan_camera(delta: Vector2) -> void:
	# 屏幕方向 → 世界方向（沿地面平面）
	var cam_right: Vector3 = _camera.global_transform.basis.x
	var cam_forward: Vector3 = _camera.global_transform.basis.z
	var flat_forward := Vector3(cam_forward.x, 0.0, cam_forward.z)
	if flat_forward.length() < 0.0001:
		flat_forward = Vector3.BACK
	flat_forward = flat_forward.normalized()
	var flat_right := Vector3(cam_right.x, 0.0, cam_right.z).normalized()
	var speed: float = _cam_dist * 0.0012
	_cam_target += (-flat_right * delta.x + flat_forward * delta.y) * speed
	_update_camera()


## 悬停高亮：单个格子或框选矩形
func _update_hover_highlight() -> void:
	var cellf: float = _cell_size_3d()
	if demolish_mode and _select_start.x >= 0 and _select_end.x >= 0:
		var r: Rect2i = _selection_rect()
		_highlight.position = Vector3((r.position.x + r.size.x * 0.5) * cellf, 0.05,
				(r.position.y + r.size.y * 0.5) * cellf)
		_highlight.scale = Vector3(r.size.x, 1.0, r.size.y)
		_highlight.visible = true
		(_highlight.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.4, 0.35, 0.3)
		return
	if hover_cell.x < 0 or hover_cell.y < 0:
		_highlight.visible = false
		return
	_highlight.position = Vector3((hover_cell.x + 0.5) * cellf, 0.05, (hover_cell.y + 0.5) * cellf)
	_highlight.scale = Vector3.ONE
	_highlight.visible = true
	(_highlight.material_override as StandardMaterial3D).albedo_color = Color(0.5, 0.95, 0.6, 0.32)


func _selection_rect() -> Rect2i:
	return Rect2i(mini(_select_start.x, _select_end.x), mini(_select_start.y, _select_end.y),
			abs(_select_end.x - _select_start.x) + 1, abs(_select_end.y - _select_start.y) + 1)


func _make_flat_quad(size: float, color: Color) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = size * 0.5
	st.set_color(color)
	st.add_vertex(Vector3(-half, 0, -half))
	st.add_vertex(Vector3(half, 0, -half))
	st.add_vertex(Vector3(half, 0, half))
	st.add_vertex(Vector3(-half, 0, half))
	st.add_index(0); st.add_index(1); st.add_index(2)
	st.add_index(0); st.add_index(2); st.add_index(3)
	return st.commit()


# === 工具（explore_map 兼容接口） ===

func set_demolish_mode(on: bool) -> void:
	demolish_mode = on
	_select_start = Vector2i(-1, -1)
	_select_end = Vector2i(-1, -1)
	demolish_mode_changed.emit(on)
	_update_hover_highlight()


func can_build_at(cell: Vector2i, w: int, h: int) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x + w > BuildingSystem.GRID_W 			or cell.y + h > BuildingSystem.GRID_H:
		return false
	for dx: int in range(w):
		for dy: int in range(h):
			if BuildingSystem.grid[cell.x + dx][cell.y + dy] != "":
				return false
	return true


func _notification(what: int) -> void:
	# 窗口/控件尺寸变化：同步子视口分辨率
	if what == NOTIFICATION_RESIZED and _viewport != null:
		_viewport.size = Vector2i(maxi(64, int(size.x)), maxi(64, int(size.y)))
