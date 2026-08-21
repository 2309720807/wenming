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
var _viewport_container: SubViewportContainer  # 手动管理尺寸/缩放（见 _update_viewport_size）
var _world: Node3D
var _camera: Camera3D
var _ground_root: Node3D
var _object_root: Node3D
var _highlight: MeshInstance3D  # 悬停高亮格
var _sun: DirectionalLight3D    # 日光（东升西落）
var _moon: DirectionalLight3D   # 月光（夜晚补光）
var _sky: WorldEnvironment      # 天空环境（昼夜色渐变）
var _sun_disc: MeshInstance3D   # 太阳圆盘（可见光球，跟随日光方向）
var _moon_disc: MeshInstance3D  # 月亮圆盘（冷色光球，跟随月光方向）

# === 昼夜系统 ===
const DAY_LENGTH: float = 90.0          # 现实 90 秒 = 游戏一昼夜（随 GameState 游戏时间流逝）
const SUN_MAX_ELEV: float = 0.62        # 太阳最高仰角（sin 弧度 ≈ 35.5°）
const MOON_MAX_ELEV: float = 0.55       # 月亮最高仰角
const DISC_DIST: float = 2400.0       # 太阳/月亮圆盘沿相机前方距离（视差定位，保证视锥内）
const SUN_DISC_R: float = 68.0        # 太阳圆盘半径
const MOON_DISC_R: float = 52.0       # 月亮圆盘半径
const SUN_WARM: Color = Color(1.0, 0.92, 0.78)    # 黄昏暖橙
const SUN_NOON: Color = Color(1.0, 0.98, 0.92)    # 正午暖白
const MOON_COLOR: Color = Color(0.62, 0.72, 1.0)  # 月亮冷蓝白
const NIGHT_SKY: Color = Color(0.008, 0.015, 0.045)  # 深夜天空
const DUSK_SKY: Color = Color(0.75, 0.45, 0.28)     # 黄昏橙红天空（明亮）
const DAY_SKY: Color = Color(0.34, 0.5, 0.75)       # 白昼亮蓝天（修复：原深蓝近黑致天空灰暗）

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

# === 粒子 / 人流 / 动画状态 ===
var _particles: Array[Dictionary] = []  # {node, vel, life, max_life, kind}
var _people: Array[Dictionary] = []     # {node, target, speed}
var _people_targets: Array[Vector3] = []
var _flash_t: float = 0.0               # 金币不足红闪计时
const PEOPLE_MAX: int = 20


func _process(delta: float) -> void:
	_update_viewport_size()  # 每帧同步子视口分辨率（父级 scale 变化不触发 TRANSFORM_CHANGED，轮询最可靠）
	_update_day_night(delta)
	_flash_t += delta
	_tick_particles(delta)
	_tick_people(delta)
	_update_construction_bars()
	if not preview_item.is_empty():
		_update_hover_highlight()  # 金币不足红闪需要持续刷新


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_3d_world()
	# 恢复缩放与视角（跨场景/跨启动记忆，见 BuildingSystem.set_map_view / map_zoom）
	zoom = clampf(BuildingSystem.map_zoom, _min_zoom(), ZOOM_MAX)
	_cam_dist = CAM_DIST_BASE / maxf(zoom, 0.01)
	_yaw = BuildingSystem.map_yaw
	_pitch = clampf(BuildingSystem.map_pitch, CAM_PITCH_MIN, CAM_PITCH_MAX)
	if BuildingSystem.map_target_x >= 0.0:
		_cam_target = Vector3(BuildingSystem.map_target_x, 0.0, BuildingSystem.map_target_z)
	else:
		_cam_target = _map_center()
	_update_camera()
	# 数据层信号 → 3D 重建/更新
	BuildingSystem.grid_changed.connect(func(_c: Vector2i) -> void: _rebuild_all())
	BuildingSystem.building_placed.connect(func(cell: Vector2i, id: String) -> void:
		_spawn_building(cell, id)
		_spawn_effect_particles(cell, "place"))
	BuildingSystem.building_completed.connect(func(cell: Vector2i, id: String) -> void:
		# 重建建筑：恢复实态（不再半透明）、移除施工进度条，随后闪光+粒子
		_rebuild_all()
		_flash_building(cell, Color(1, 0.85, 0.35))
		_spawn_effect_particles(cell, "complete"))
	BuildingSystem.building_upgraded.connect(func(cell: Vector2i, id: String, _lv: int) -> void:
		_rebuild_all()
		_flash_building(cell, Color(0.55, 0.85, 1.0))
		_spawn_effect_particles(cell, "upgrade"))
	BuildingSystem.building_demolished.connect(func(cell: Vector2i, _id: String) -> void:
		_rebuild_all()
		_spawn_effect_particles(cell, "demolish"))
	BuildingSystem.obstacle_cleared.connect(func(_c: Vector2i) -> void: _rebuild_all())


# ================= 3D 世界构建 =================

func _build_3d_world() -> void:
	# 子视口容器：锚点左上角，尺寸/缩放由 _update_viewport_size 手动管理
	var vpc := SubViewportContainer.new()
	vpc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	vpc.position = Vector2.ZERO
	vpc.stretch = false  # stretch=true 时容器强制子视口 = 容器尺寸，无法手动提高渲染分辨率
	add_child(vpc)
	_viewport_container = vpc
	var vp := SubViewport.new()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# 高清渲染：子视口渲染分辨率 = 布局尺寸 × 窗口缩放系数（_physical_size），
	# 显示时容器按 1/factor 反向缩放，最终屏幕像素 = 子视口渲染像素（任意分辨率不模糊）
	vp.size = _physical_size()
	vpc.add_child(vp)
	_viewport = vp
	set_notify_transform(true)  # 监听根缩放变化（窗口/界面缩放时更新子视口分辨率）
	_world = Node3D.new()
	_world.name = "World3D"
	vp.add_child(_world)
	# 昼夜光照：太阳（暖光,随游戏时间东升西落）+ 月亮（冷光补光）+ 环境
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52, -38, 0)
	_sun.light_energy = 1.1
	_sun.light_color = Color(1.0, 0.98, 0.92)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 9000.0   # 阴影覆盖全图（地图 2760+ 格域）
	_sun.directional_shadow_split_1 = 0.25
	_sun.directional_shadow_split_2 = 0.6
	_sun.shadow_bias = 0.02
	_world.add_child(_sun)
	_moon = DirectionalLight3D.new()
	_moon.light_energy = 0.0
	_moon.light_color = Color(0.6, 0.72, 1.0)
	_moon.shadow_enabled = true
	_moon.directional_shadow_max_distance = 9000.0
	_moon.shadow_bias = 0.02
	_world.add_child(_moon)
	# 太阳圆盘（发光暖球）+ 月亮圆盘（冷球）：跟随光方向远处显示
	_sun_disc = _make_celestial_disc(SUN_DISC_R, Color(1.0, 0.85, 0.45))
	_sun_disc.name = "SunDisc"
	_world.add_child(_sun_disc)
	_moon_disc = _make_celestial_disc(MOON_DISC_R, Color(0.85, 0.9, 1.0))
	_moon_disc.name = "MoonDisc"
	_world.add_child(_moon_disc)
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
	_sky = env
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
	# 地面使用标准光照材质：接收太阳/月亮投影（UNSHADED 不产生阴影接收）
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.metallic = 0.0
	mat.shadow_offset = 0.01
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
	for pt: Dictionary in _particles:
		(pt["node"] as Node).queue_free()
	_particles.clear()
	for pp: Dictionary in _people:
		(pp["node"] as Node).queue_free()
	_people.clear()
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
	var node: Node3D = BuildingMeshes.build(item, int(p.get("level", 1)), _cell_size_3d())
	node.name = "B_" + key
	node.position = Vector3((cell.x + float(item.get("width", 1)) * 0.5) * _cell_size_3d(),
			0.0, (cell.y + float(item.get("height", 1)) * 0.5) * _cell_size_3d())
	_object_root.add_child(node)
	# 等级徽章（Label3D 广告牌，悬浮建筑上方，随缩放自适应字号）
	var badge := Label3D.new()
	badge.name = "Badge"
	badge.text = "Lv.%d" % int(p.get("level", 1))
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.font_size = maxi(6, int(_cell_size_3d() * 0.28))
	badge.outline_size = maxi(2, int(_cell_size_3d() * 0.03))
	badge.outline_modulate = Color(0, 0, 0, 0.85)
	badge.modulate = Color(1, 0.92, 0.5, 1.0)
	badge.no_depth_test = true
	badge.position = Vector3(0, _cell_size_3d() * 1.45, 0)
	badge.pixel_size = 0.004
	node.add_child(badge)
	# 出生动画：从地面升起
	if p.is_empty() or not p.get("completed", false):
		node.scale = Vector3(1, 0.1, 1)
		var tw: Tween = node.create_tween()
		tw.tween_property(node, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 施工中：半透明
	if p.get("op", "") != "":
		_set_node_transparency(node, 0.6)


## 建筑模型生成已抽取至独立模块 BuildingMeshes（真实建筑模板程序化重构）


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
	m.cull_mode = BaseMaterial3D.CULL_DISABLED  # 双面渲染，任意视角可见
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
	# 升级后刷新等级徽章
	var badge: Label3D = node.get_node_or_null("Badge") as Label3D
	if badge != null:
		badge.text = "Lv.%d" % int(BuildingSystem.placed.get(key, {}).get("level", 1))
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
	# 视角记忆（跨场景/跨启动，写入 settings.cfg）
	BuildingSystem.set_map_view(_yaw, _pitch, _cam_target)


## 创建天体圆盘（自发光球体，远距离显示为圆盘）
func _make_celestial_disc(radius: float, glow: Color) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	disc.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # 自身发光不受光照
	mat.albedo_color = glow
	mat.emission_enabled = true
	mat.emission = glow
	mat.emission_energy_multiplier = 3.0
	mat.disable_receive_shadows = true
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.visible = false
	return disc


## 每帧定位天体：相对相机放置（保证在相机视锥内可见；太阳月亮始终挂在天上）
func _update_celestial_disc(light: DirectionalLight3D, disc: MeshInstance3D, up: bool, dist: float) -> void:
	if disc == null:
		return
	disc.visible = up
	if not up:
		return
	# DirectionalLight3D 朝 -Z 照射；+basis.z 即"光源所在"的天空方向
	var sky_dir: Vector3 = light.global_transform.basis.z.normalized()
	# 相机视线前方 dist + 天向偏移：俯视地面时太阳也在视锥内（修复：原相对场景中心，
	# 正午太阳在头顶上方，被俯视相机排除在视野外）
	var cam_fwd: Vector3 = -_camera.global_transform.basis.z.normalized()
	disc.position = _camera.global_position + cam_fwd * dist + sky_dir * (dist * 0.35)


## 昼夜光影：太阳/月亮按游戏时间东升西落（方位 360° + 仰角正弦曲线）
## 时间轴 t∈[0,1)：t=0 日出 → t=0.25 正午 → t=0.5 日落 → t=0.75 午夜 → 回归
func _update_day_night(_delta: float) -> void:
	if _sun == null or _moon == null:
		return
	# TimeManager.game_time 为现实秒（1 月 = 5 秒）；直接取模 DAY_LENGTH 得到真实 90 秒一昼夜
	var t: float = fposmod(TimeManager.game_time, DAY_LENGTH) / DAY_LENGTH
	# --- 太阳 ---
	var sun_phase: float = t * 2.0  # 0~1 为白昼，1~2 为夜晚
	var sun_up: bool = sun_phase <= 1.0
	if sun_up:
		# 日出=0（东）→ 正午=0.5（南天顶）→ 日落=1（西）
		var az: float = sun_phase * PI           # 方位角 0..π（东→西）
		var elev: float = sin(sun_phase * PI) * SUN_MAX_ELEV
		_sun.rotation_degrees = Vector3(rad_to_deg(elev) - 90.0, lip_deg(az, -90.0, 90.0), 0.0)
		# 能量与仰角同步：日出/日落=0（平滑进入夜晚，原 0.35 残光在切换瞬间跳变）
		var sun_curve: float = sin(sun_phase * PI)
		_sun.light_energy = 1.1 * sun_curve
		_sun.light_color = SUN_NOON.lerp(SUN_WARM, 1.0 - sun_curve)
	else:
		_sun.light_energy = 0.0
	# --- 月亮 ---
	var moon_phase: float = fposmod(sun_phase, 1.0)
	var moon_up: bool = not sun_up
	if moon_up:
		var maz: float = moon_phase * PI
		var melev: float = sin(moon_phase * PI) * MOON_MAX_ELEV
		_moon.rotation_degrees = Vector3(rad_to_deg(melev) - 90.0, lip_deg(maz, -90.0, 90.0), 0.0)
		# 月光随月轨渐入（0→0.4→0），与天空 nightness 同步无暗隙
		_moon.light_energy = 0.4 * sin(moon_phase * PI)
	else:
		_moon.light_energy = 0.0
	# --- 太阳/月亮圆盘定位（沿光反方向远处，随仰角升降） ---
	_update_celestial_disc(_sun, _sun_disc, sun_up, DISC_DIST)
	_update_celestial_disc(_moon, _moon_disc, moon_up, DISC_DIST)
	# --- 天空/环境渐变（平滑连续，无瞬间跳变） ---
	# 夜晚深沉度 = sin(月相位弧)：月出(0)→深更(0.5)=1→月落(1)→0，与月轨同步
	var nightness: float = sin(moon_phase * PI)  # 月出月落时=0（黄昏），深夜=1
	var sky_col: Color
	var ambient: float
	if sun_up:
		var dayness: float = sin(sun_phase * PI)
		sky_col = DAY_SKY.lerp(DUSK_SKY, 1.0 - dayness)
		ambient = 0.5 + 0.45 * dayness  # 白昼环境光提亮（修复灰暗）
	else:
		# 黄昏(DUSK) → 深夜(NIGHT) → 黎明(DUSK)：nightness 0→1→0 平滑过渡
		sky_col = DUSK_SKY.lerp(NIGHT_SKY, nightness)
		ambient = 0.45 - 0.3 * nightness  # 黄昏 0.45 → 深夜 0.15
	_sky.environment.background_color = sky_col
	_sky.environment.ambient_light_color = sky_col.lightened(0.25)
	_sky.environment.ambient_light_energy = ambient


## 角度计算辅助：相位→方位角（东为 -90°，西为 +90°，即绕 Y 方向）
func lip_deg(phase: float, lo: float, hi: float) -> float:
	return lo + (hi - lo) * phase


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
	BuildingSystem.set_map_view(_yaw, _pitch, _cam_target, true)  # 缩放后强制保存视角


func _screen_to_ground(screen_pos: Vector2) -> Vector3:
	# 输入为 GridView 布局坐标；子视口渲染分辨率 = 布局 × 缩放 × 超采样（_physical_size），
	# 射线投影需换算为子视口像素坐标（含画质档位超采样倍数）
	var factor: float = 1.0
	if WindowManager.has_method("current_scale_factor"):
		factor = WindowManager.current_scale_factor()
	var ss: float = 1.0
	if WindowManager.has_method("supersample_factor"):
		ss = WindowManager.supersample_factor()
	var vp_px := screen_pos * factor * ss
	var ray_origin: Vector3 = _camera.project_ray_origin(vp_px)
	var ray_dir: Vector3 = _camera.project_ray_normal(vp_px)
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
			BuildingSystem.set_map_view(_yaw, _pitch, _cam_target, true)  # 平移结束强制保存视角
		return
	if event is InputEventMouseMotion:
		# 未选中建筑时：左键按住超过阈值切换为旋转视角（不再视为单击）
		if _mouse_left_down and _click_armed and not _rotating \
				and preview_item.is_empty() \
				and event.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_rotating = true
			_click_armed = false
		# 选中建筑时：左键按住拖动 = 批量连续建造（划过可建格自动放置）
		if _mouse_left_down and not preview_item.is_empty() and not _rotating:
			var pc: Vector2i = _screen_to_cell(event.position)
			if pc.x >= 0 and pc != _last_drag_cell:
				_last_drag_cell = pc
				_click_armed = false  # 拖动建造开始后，松开不再视为单击
				drag_place_requested.emit(pc)
		if _rotating:
			var delta: Vector2 = event.position - _last_mouse_pos
			_yaw -= delta.x * ROTATE_SPEED
			# 鼠标下拖 → 俯角增大（更俯视），修正：原方向相反
			_pitch = clampf(_pitch + delta.y * ROTATE_SPEED, CAM_PITCH_MIN, CAM_PITCH_MAX)
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
				BuildingSystem.set_map_view(_yaw, _pitch, _cam_target, true)  # 旋转结束强制保存视角
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
	# 鼠标下拖 → 画面内容下移（与拖动方向一致），修正：原竖直方向相反
	_cam_target += (-flat_right * delta.x - flat_forward * delta.y) * speed
	_update_camera()


## 悬停高亮：单个格子或框选矩形
func _update_hover_highlight() -> void:
	var cellf: float = _cell_size_3d()
	if demolish_mode and _select_start.x >= 0 and _select_end.x >= 0:
		var r: Rect2i = _selection_rect()
		_highlight.position = Vector3((r.position.x + r.size.x * 0.5) * cellf, 0.05,
				(r.position.y + r.size.y * 0.5) * cellf)
		# 缩放 × 格子尺寸：框选矩形按真实格数占地显示
		_highlight.scale = Vector3(r.size.x * cellf, 1.0, r.size.y * cellf)
		_highlight.visible = true
		(_highlight.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.4, 0.35, 0.3)
		return
	# 建造预选框：选中建筑时按建筑真实占地尺寸显示绿（可建）/红（不可建）/红闪（金币不足）
	if not preview_item.is_empty() and hover_cell.x >= 0 and hover_cell.y >= 0:
		var pw: int = int(preview_item.get("width", 1))
		var ph: int = int(preview_item.get("height", 1))
		var can: bool = can_build_at(hover_cell, pw, ph)
		var afford: bool = GameState.gold >= float(preview_item.get("cost", 0))
		var color: Color
		if can and afford:
			color = Color(0.3, 0.95, 0.5, 0.38)
		elif not afford:
			var blink: float = 0.55 + 0.35 * sin(_flash_t * 10.0)  # 金币不足红色闪烁
			color = Color(0.95, 0.25, 0.25, blink)
		else:
			color = Color(0.95, 0.3, 0.3, 0.4)
		_highlight.position = Vector3((hover_cell.x + pw * 0.5) * cellf, 0.05,
				(hover_cell.y + ph * 0.5) * cellf)
		# 缩放 × 格子尺寸：预选框 = 建筑真实占用大小（w×h 格）
		_highlight.scale = Vector3(pw * cellf, 1.0, ph * cellf)
		_highlight.visible = true
		(_highlight.material_override as StandardMaterial3D).albedo_color = color
		return
	if hover_cell.x < 0 or hover_cell.y < 0:
		_highlight.visible = false
		return
	_highlight.position = Vector3((hover_cell.x + 0.5) * cellf, 0.05, (hover_cell.y + 0.5) * cellf)
	_highlight.scale = Vector3(cellf, 1.0, cellf)
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
	# 绕序反转：法线朝上（+Y），从上方俯视可见（修复：原绕序法线朝下被背面剔除，预选框看不见）
	st.add_index(0); st.add_index(2); st.add_index(1)
	st.add_index(0); st.add_index(3); st.add_index(2)
	return st.commit()


# ================= 粒子特效（建造/完工/升级/拆除） =================

func _emit_particle(pos: Vector3, vel: Vector3, color: Color, size: float, life: float, kind: String = "spark") -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = pos
	_object_root.add_child(mi)
	_particles.append({"node": mi, "vel": vel, "life": life, "max_life": life, "kind": kind})


func _tick_particles(delta: float) -> void:
	var done: Array[int] = []
	for i: int in range(_particles.size()):
		var pt: Dictionary = _particles[i]
		pt["life"] = float(pt["life"]) - delta
		if pt.get("kind", "") == "debris":
			pt["vel"] = Vector3(pt["vel"]) + Vector3(0, -30.0, 0) * delta  # 拆除碎片下落
		var node: MeshInstance3D = pt["node"]
		node.position = node.position + Vector3(pt["vel"]) * delta
		var alpha: float = clampf(float(pt["life"]) / float(pt["max_life"]), 0.0, 1.0)
		(node.material_override as StandardMaterial3D).albedo_color.a = alpha
		if float(pt["life"]) <= 0.0:
			done.append(i)
	for i: int in range(done.size()):
		var idx: int = int(done[done.size() - 1 - i])
		(_particles[idx]["node"] as Node).queue_free()
		_particles.remove_at(idx)


func _spawn_effect_particles(cell: Vector2i, kind: String) -> void:
	var cellf: float = _cell_size_3d()
	var center: Vector3 = Vector3((cell.x + 0.5) * cellf, cellf * 0.4, (cell.y + 0.5) * cellf)
	match kind:
		"place":
			# 放置：青色火花四溅 + 光柱
			for i: int in range(12):
				var ang: float = randf() * TAU
				_emit_particle(center, Vector3(cos(ang), randf_range(0.6, 1.6), sin(ang)) * 45.0,
						Color(0.5, 0.9, 1.0), cellf * 0.04, 0.6)
			_emit_particle(center + Vector3(0, cellf * 0.3, 0), Vector3(0, 120, 0),
					Color(0.7, 0.95, 1.0), cellf * 0.35, 0.45, "beam")
		"complete":
			# 完工：金色爆发
			for i: int in range(18):
				var ang: float = randf() * TAU
				var phi: float = randf() * TAU
				_emit_particle(center + Vector3(0, cellf * 0.4, 0),
						Vector3(cos(ang) * cos(phi), sin(phi), sin(ang) * cos(phi)) * 70.0,
						Color(1.0, 0.85, 0.35), cellf * 0.05, 0.9)
		"upgrade":
			# 升级：蓝色上升光点
			for i: int in range(10):
				_emit_particle(center + Vector3(randf_range(-cellf * 0.3, cellf * 0.3), 0.2,
						randf_range(-cellf * 0.3, cellf * 0.3)),
						Vector3(0, randf_range(45, 100), 0), Color(0.6, 0.9, 1.0), cellf * 0.04, 0.8)
		"demolish":
			# 拆除：棕色碎片下落
			for i: int in range(14):
				_emit_particle(center + Vector3(0, cellf * 0.5, 0),
						Vector3(randf_range(-70, 70), randf_range(20, 70), randf_range(-70, 70)),
						Color(0.7, 0.55, 0.4), cellf * 0.06, 1.0, "debris")


# ================= 人流粒子（完工建筑间游走） =================

func _tick_people(delta: float) -> void:
	_people_targets.clear()
	for key: String in BuildingSystem.placed:
		var p: Dictionary = BuildingSystem.placed[key]
		if not p.get("completed", false):
			continue
		var anchor: Vector2i = BuildingSystem.BuildingGrid.key_to_cell(key)
		_people_targets.append(Vector3((anchor.x + 0.5) * _cell_size_3d(), 0.3,
				(anchor.y + 0.5) * _cell_size_3d()))
	if _people_targets.is_empty():
		if not _people.is_empty():
			for pp: Dictionary in _people:
				(pp["node"] as Node).queue_free()
			_people.clear()
		return
	var target_count: int = mini(PEOPLE_MAX, _people_targets.size() * 2)
	if _people.size() < target_count:
		for i: int in range(target_count - _people.size()):
			_people.append(_spawn_person())
	elif _people.size() > target_count:
		for i: int in range(_people.size() - target_count):
			var pp: Dictionary = _people.pop_back()
			(pp["node"] as Node).queue_free()
	for pp: Dictionary in _people:
		var node: Node3D = pp["node"]
		var target: Vector3 = pp["target"]
		var dir: Vector3 = target - node.position
		if dir.length() < 3.0:
			pp["target"] = _people_targets[randi() % _people_targets.size()]
		else:
			node.position = node.position + dir.normalized() * float(pp["speed"]) * delta


func _spawn_person() -> Dictionary:
	var node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.6
	sphere.height = 3.2
	node.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.92, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	node.position = _people_targets[randi() % _people_targets.size()]
	_object_root.add_child(node)
	return {"node": node, "target": _people_targets[randi() % _people_targets.size()],
			"speed": randf_range(14.0, 26.0)}


# ================= 施工进度条 =================

func _update_construction_bars() -> void:
	var cellf: float = _cell_size_3d()
	for key: String in BuildingSystem.placed:
		var p: Dictionary = BuildingSystem.placed[key]
		if p.get("op", "") == "":
			continue
		var cellk: Vector2i = BuildingSystem.BuildingGrid.key_to_cell(key)
		var bar: MeshInstance3D = _object_root.get_node_or_null("Bar_" + key) as MeshInstance3D
		if bar == null:
			var box := BoxMesh.new()
			box.size = Vector3(float(p.get("width", 1)) * cellf * 0.8, cellf * 0.06, cellf * 0.08)
			bar = MeshInstance3D.new()
			bar.name = "Bar_" + key
			bar.mesh = box
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bar.material_override = mat
			bar.position = Vector3((cellk.x + float(p.get("width", 1)) * 0.5) * cellf,
					cellf * 1.25, (cellk.y + float(p.get("height", 1)) * 0.5) * cellf)
			_object_root.add_child(bar)
		# 进度 = 已施工比例；颜色：建造绿/升级黄/拆除红
		var progress: float = 1.0 - float(p.get("remaining", 0.0)) / maxf(float(p.get("total", 1.0)), 0.001)
		bar.scale = Vector3(maxf(progress, 0.01), 1.0, 1.0)
		var c: Color = {"build": Color(0.3, 0.9, 0.55), "upgrade": Color(0.95, 0.8, 0.3),
				"demolish": Color(0.95, 0.35, 0.3)}.get(p.get("op", ""), Color.WHITE)
		(bar.material_override as StandardMaterial3D).albedo_color = c


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


## 子视口目标分辨率：布局尺寸 × 窗口等比缩放 × 画质档位超采样（线性倍率）
## 画质档位见 WindowManager.QUALITY_LEVELS（面积 1/2/4/8/16 倍 → 线性 √档位）
func _physical_size() -> Vector2i:
	var factor: float = 1.0
	if WindowManager.has_method("current_scale_factor"):
		factor = WindowManager.current_scale_factor()
	var ss: float = 1.0
	if WindowManager.has_method("supersample_factor"):
		ss = WindowManager.supersample_factor()
	return Vector2i(maxi(64, int(size.x * factor * ss)), maxi(64, int(size.y * factor * ss)))


func _update_viewport_size() -> void:
	if _viewport == null or _viewport_container == null:
		return
	var target: Vector2i = _physical_size()
	# 容器布局尺寸 = 子视口渲染分辨率（1 渲染像素 = 1 布局像素）
	if target != _viewport.size:
		_viewport.size = target
		_viewport_container.size = Vector2(target)
	# 反向缩放补偿：容器显示尺寸 = 布局尺寸（GridView 区域），渲染像素 = 屏幕像素 × 超采样
	var factor: float = 1.0
	if WindowManager.has_method("current_scale_factor"):
		factor = WindowManager.current_scale_factor()
	var ss: float = 1.0
	if WindowManager.has_method("supersample_factor"):
		ss = WindowManager.supersample_factor()
	var inv: Vector2 = Vector2(1.0 / (factor * ss), 1.0 / (factor * ss))
	if _viewport_container.scale != inv:
		_viewport_container.scale = inv


func _notification(what: int) -> void:
	# 控件尺寸/全局缩放变化 → 同步子视口分辨率（防 3D 画面拉伸模糊）
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_TRANSFORM_CHANGED:
		_update_viewport_size()
