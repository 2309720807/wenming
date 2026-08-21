extends Control
class_name GridView

## 网格地图视图：绘制网格/障碍/建筑/预览，处理悬停与点击
## 设计依据：docs/design/game_design.md 3.7
## 网格尺寸以 BuildingSystem.cell_size 为准（数据驱动，data/buildings.json）

signal hover_changed(cell: Vector2i)
signal cell_clicked(cell: Vector2i)
signal preview_cancel_requested  # 右键取消预选建造
signal drag_place_requested(cell: Vector2i)  # 左键拖动连续建造
signal demolition_requested(rect: Rect2i)   # 批量拆除框选完成
signal demolish_mode_changed(on: bool)      # 拆除模式开关

const ZOOM_MIN: float = 0.4
const ZOOM_MAX: float = 3.0
const PAN_DRAG_THRESHOLD: float = 6.0  # 左键按住超过该像素距离视为平移而非单击

var zoom: float = 1.0
var _last_drag_cell: Vector2i = Vector2i(-1, -1)
var _mouse_left_down: bool = false  # 本地记录左键状态（拖动连续建造，兼容事件无 button_mask 的情况）

# === 地图平移（未建设时左键拖动查看）===
var _pan: Vector2 = Vector2.ZERO  # 视口平移偏移（叠加在网格原点上）
var _view_dragging: bool = false  # 正在进行地图平移拖动
var _click_armed: bool = false    # 左键按下待判定单击/拖动（未建设时）
var _press_pos: Vector2 = Vector2.ZERO  # 按下位置（用于区分单击与平移拖动）
var _last_mouse_pos: Vector2 = Vector2.ZERO  # 上次鼠标位置（平移用位置差计算，兼容无 relative 的合成事件）

# === 批量拆除框选 ===
var demolish_mode: bool = false
var _select_start: Vector2i = Vector2i(-1, -1)
var _select_end: Vector2i = Vector2i(-1, -1)

const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")
const FONT_NORMAL: Font = preload("res://assets/fonts/SourceHanSansCN-Normal.ttf")
const ANIM_PLACE: float = 0.3
const ANIM_COMPLETE: float = 0.6

var hover_cell: Vector2i = Vector2i(-1, -1)
var preview_item: Dictionary = {}  # 当前选中待放置的建筑配置
var place_animations: Dictionary = {}   # "x,y" -> 已播放时长（放置缩放动画）
var completion_effects: Dictionary = {} # "x,y" -> 已播放时长（完工闪光）

# === 粒子系统（建造/完工/升级/拆除特效 + 人流粒子）===
var effect_particles: Array[Dictionary] = []  # {pos, vel, life, max_life, color, size, kind}
var _people: Array[Dictionary] = []           # 人流粒子 {pos, target, speed}
var _people_spots: Array[Vector2] = []        # 人群兴趣点（已完工建筑中心）
const PEOPLE_MAX: int = 24


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 地图只在地图显示区域内渲染，超出部分裁剪，避免扩大后溢出覆盖两侧菜单/信息面板
	clip_contents = true
	# 恢复地图缩放比例（跨场景/跨启动记忆，见 BuildingSystem.map_zoom）
	zoom = BuildingSystem.map_zoom
	_clamp_pan()
	# 大地图时恢复的缩放可能低于"整图可见"所需，延迟一帧校正（_ready 时布局未完成）
	_ensure_min_zoom.call_deferred()
	# 建造/完工/升级/拆除特效粒子（数据层信号驱动）
	BuildingSystem.building_placed.connect(func(cell: Vector2i, _id: String) -> void:
		_spawn_build_particles(cell, "place"))
	BuildingSystem.building_completed.connect(func(cell: Vector2i, _id: String) -> void:
		_spawn_build_particles(cell, "complete"))
	BuildingSystem.building_upgraded.connect(func(cell: Vector2i, _id: String, _lv: int) -> void:
		_spawn_build_particles(cell, "upgrade"))
	BuildingSystem.building_demolished.connect(func(cell: Vector2i, _id: String) -> void:
		_spawn_build_particles(cell, "demolish"))


func _process(delta: float) -> void:
	_tick_animations(place_animations, ANIM_PLACE, delta)
	_tick_animations(completion_effects, ANIM_COMPLETE, delta)
	_tick_particles(delta)
	_tick_people(delta)


func _tick_animations(dict: Dictionary, max_time: float, delta: float) -> void:
	var changed: bool = false
	var done: Array[String] = []
	for key: String in dict:
		dict[key] = float(dict[key]) + delta
		if float(dict[key]) >= max_time:
			done.append(key)
		changed = true
	for key: String in done:
		dict.erase(key)
	if changed:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# 拆除模式：左键拖动框选区域，右键退出
	if demolish_mode:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_select_start = _pos_to_cell(event.position)
				_select_end = _select_start
			else:
				if _select_start.x >= 0 and _select_end.x >= 0:
					demolition_requested.emit(_selection_rect())
				_select_start = Vector2i(-1, -1)
				_select_end = Vector2i(-1, -1)
			queue_redraw()
			return
		elif event is InputEventMouseMotion:
			if _select_start.x >= 0:
				_select_end = _pos_to_cell(event.position)
				queue_redraw()
			return
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			set_demolish_mode(false)
			return
	if event is InputEventMouseMotion:
		# 平移拖动：地图随鼠标移动（未建设时的左键拖动查看）
		if _view_dragging:
			# 用位置差而非 event.relative：合成/模拟鼠标事件可能不带 relative
			_pan += event.position - _last_mouse_pos
			_last_mouse_pos = event.position
			_clamp_pan()
			queue_redraw()
			return
		var cell: Vector2i = _pos_to_cell(event.position)
		if cell != hover_cell:
			hover_cell = cell
			hover_changed.emit(cell)
			queue_redraw()
		_last_mouse_pos = event.position
		# 左键按住拖动：连续建造（仅选中建筑时；修复：motion 分支需合并处理，elif 会被 hover 分支吞掉）
		if _mouse_left_down and not preview_item.is_empty():
			var drag_cell: Vector2i = _pos_to_cell(event.position)
			if drag_cell.x >= 0 and drag_cell != _last_drag_cell:
				_last_drag_cell = drag_cell
				drag_place_requested.emit(drag_cell)
		# 未建设时按住左键超过阈值：切换为平移地图
		elif _mouse_left_down and _click_armed and not _view_dragging \
				and event.position.distance_to(_press_pos) > PAN_DRAG_THRESHOLD:
			_view_dragging = true
			_click_armed = false
			_last_mouse_pos = event.position  # 平移起点，避免首帧跳变
			hover_cell = Vector2i(-1, -1)
			hover_changed.emit(hover_cell)  # 平移中隐藏悬停信息
		return
	elif event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_left_down = event.pressed
		if event.pressed:
			_press_pos = event.position
			_last_mouse_pos = event.position
			_last_drag_cell = Vector2i(-1, -1)
			if preview_item.is_empty():
				# 未建设：按下不立即触发点击，抬起时按是否拖动判定单击/平移
				_click_armed = true
			else:
				cell_clicked.emit(_pos_to_cell(event.position))
		else:
			_last_drag_cell = Vector2i(-1, -1)
			if _view_dragging:
				# 平移结束：立即恢复悬停信息
				_view_dragging = false
				var end_cell: Vector2i = _pos_to_cell(event.position)
				if end_cell != hover_cell:
					hover_cell = end_cell
					hover_changed.emit(end_cell)
			elif _click_armed:
				# 未发生拖动：视为单击
				_click_armed = false
				cell_clicked.emit(_pos_to_cell(event.position))
			_click_armed = false
	elif event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# 右键取消当前预选建造
		if not preview_item.is_empty():
			preview_item = {}
			preview_cancel_requested.emit()
			queue_redraw()
	elif event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		# 滚轮放大（以光标为锚点，缩放范围 0.4x ~ 3.0x）
		_zoom_at(event.position, 1.12)
	elif event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		# 滚轮缩小
		_zoom_at(event.position, 1.0 / 1.12)


# === 绘制 ===

func _draw() -> void:
	var origin: Vector2 = _grid_origin()
	var grid_px: Vector2 = Vector2(BuildingSystem.GRID_W, BuildingSystem.GRID_H) * _cell()
	draw_rect(Rect2(origin, grid_px), Color(0.03, 0.07, 0.14, 0.85))
	for x: int in range(BuildingSystem.GRID_W):
		for y: int in range(BuildingSystem.GRID_H):
			_draw_cell(origin, Vector2i(x, y))
	_draw_obstacles(origin)
	_draw_buildings(origin)
	_draw_people()
	_draw_particles()
	_draw_selection(origin)
	_draw_preview(origin)


func _draw_cell(origin: Vector2, cell: Vector2i) -> void:
	var rect := Rect2(origin + Vector2(cell * _cell()), Vector2(_cell(), _cell()))
	draw_rect(rect, Color(0.05, 0.1, 0.2, 0.5), false, 1.0)


func _draw_obstacles(origin: Vector2) -> void:
	# 障碍形状多样化：树/岩石/湖泊按格子坐标确定性随机绘制（同一格子形状稳定，重载存档不变）
	for x: int in range(BuildingSystem.GRID_W):
		for y: int in range(BuildingSystem.GRID_H):
			var mark: String = str(BuildingSystem.grid[x][y])
			if not mark.begins_with("obs:"):
				continue
			var obs_id: String = mark.substr(4)
			var obs: Dictionary = BuildingSystem.obstacles_data.get(obs_id, {})
			var cell_pos: Vector2 = origin + Vector2(x, y) * _cell()
			var cell_size: float = float(_cell())
			match obs_id:
				"tree":
					_draw_tree(cell_pos, cell_size, x, y)
				"rock":
					_draw_rock(cell_pos, cell_size, x, y)
				"lake":
					_draw_lake(cell_pos, cell_size * 2.0, x, y)
				_:
					draw_rect(Rect2(cell_pos, Vector2(cell_size, cell_size)), Color(obs.get("color", "#888888"), 0.8))


## 确定性哈希噪声：同一 (x,y) 恒返回同一 0..1 值，保证存档重载后障碍形状不变
func _hash_noise(x: int, y: int, salt: int = 0) -> float:
	var h: int = hash(Vector2i(x * 131 + salt, y * 977))
	return float((h % 100000) / 100000.0)


## 树木：树干 + 多层圆形树冠（大小/色差随机）
func _draw_tree(cell_pos: Vector2, cell_size: float, x: int, y: int) -> void:
	var trunk_w: float = cell_size * 0.13
	var trunk_h: float = cell_size * 0.26
	var crown_r: float = cell_size * (0.3 + _hash_noise(x, y, 1) * 0.12)
	# 树冠圆心相对格子上边的偏移（绘制时再叠加 cell_pos，原代码重复加 cell_pos.y 导致树冠错位到 2 倍行距）
	var crown_cy: float = trunk_h + crown_r * 0.55
	draw_rect(Rect2(cell_pos + Vector2(cell_size * 0.5 - trunk_w / 2, cell_size * 0.58),
			Vector2(trunk_w, trunk_h)), Color(0.42, 0.3, 0.2, 0.95))
	var shade: float = 0.75 + _hash_noise(x, y, 2) * 0.25
	var leaf: Color = Color(0.2, 0.55 * shade, 0.3, 0.95)
	draw_circle(cell_pos + Vector2(cell_size * (0.34 + _hash_noise(x, y, 3) * 0.3), crown_cy - crown_r * 0.28),
			crown_r * 0.6, leaf.lightened(0.12))
	draw_circle(cell_pos + Vector2(cell_size * (0.56 + _hash_noise(x, y, 4) * 0.25), crown_cy + crown_r * 0.08),
			crown_r * 0.5, leaf.lightened(0.2))
	draw_circle(cell_pos + Vector2(cell_size * 0.45, crown_cy - crown_r * 0.3), crown_r * 0.2, Color(1, 1, 1, 0.18))


## 岩石：5-7 顶点不规则多边形 + 高光面
func _draw_rock(cell_pos: Vector2, cell_size: float, x: int, y: int) -> void:
	var base: Color = Color(0.55, 0.58, 0.65, 0.95)
	var center: Vector2 = cell_pos + Vector2(cell_size * 0.5, cell_size * 0.56)
	var radius: float = cell_size * 0.32
	var n: int = 5 + int(_hash_noise(x, y, 5) * 3.0)
	var points: PackedVector2Array = []
	for i: int in range(n):
		var ang: float = TAU * float(i) / float(n)
		var r: float = radius * (0.72 + _hash_noise(x, y, 6 + i) * 0.5)
		points.append(center + Vector2(cos(ang), sin(ang)) * r)
	draw_colored_polygon(points, base)
	var closed: PackedVector2Array = points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, base.lightened(0.35), 2.0)
	draw_circle(center + Vector2(-radius * 0.2, -radius * 0.28), radius * 0.26, Color(1, 1, 1, 0.15))


## 湖泊：不规则多边形水面 + 岸边 + 涟漪（2x2 大障碍）
func _draw_lake(cell_pos: Vector2, size: float, x: int, y: int) -> void:
	var center: Vector2 = cell_pos + Vector2(size * 0.5, size * 0.5)
	var water: Color = Color(0.18, 0.44, 0.75, 0.85)
	var n: int = 10
	var points: PackedVector2Array = []
	for i: int in range(n):
		var ang: float = TAU * float(i) / float(n)
		var rx: float = size * 0.44 * (0.78 + _hash_noise(x, y, 20 + i) * 0.38)
		var ry: float = size * 0.38 * (0.78 + _hash_noise(x, y, 40 + i) * 0.38)
		points.append(center + Vector2(cos(ang) * rx, sin(ang) * ry))
	draw_colored_polygon(points, water)
	var closed: PackedVector2Array = points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, Color(0.6, 0.8, 1, 0.55), 2.0)
	for k: int in range(3):
		var rk: float = size * (0.16 + k * 0.1 + _hash_noise(x, y, 60 + k) * 0.04)
		draw_arc(center, rk, 0.3 + k * 0.5, TAU * 0.85 + k * 0.3, 16, Color(1, 1, 1, 0.26), 1.5)
	draw_circle(center + Vector2(-size * 0.12, -size * 0.12), size * 0.09, Color(1, 1, 1, 0.22))


func _draw_buildings(origin: Vector2) -> void:
	for key: String in BuildingSystem.placed:
		var p: Dictionary = BuildingSystem.placed[key]
		var item: Dictionary = BuildingSystem.get_item(p["item_id"])
		var anchor: Vector2i = _key_to_cell(key)
		var w: int = int(item.get("width", 1))
		var h: int = int(item.get("height", 1))
		var rect := Rect2(origin + Vector2(anchor * _cell()), Vector2(w * _cell(), h * _cell()))

		var scale_factor: float = 1.0
		if place_animations.has(key):
			scale_factor = 0.6 + 0.4 * (float(place_animations[key]) / ANIM_PLACE)
		# 建筑间隙：绘制内缩 5px，建筑间自然留缝
		var scaled := rect.grow(rect.size.x * (1.0 - scale_factor) * 0.5 - 5.0)

		var color: Color = Color(item.get("color", "#6a7fa8"))
		var op: String = p["op"]
		var active: bool = p["completed"] or op != ""
		var blink: float = 0.0
		if op == "demolish":
			# 拆除中建筑闪烁提示
			blink = 0.55 + 0.35 * sin(Time.get_ticks_msec() * 0.01)
		# 立体建筑：侧面 + 顶面 + 窗格 + 投影（带间隙）
		_draw_building_body(scaled, item, p, anchor, Color(color, 0.95 if active else 0.55))

		if op != "":
			# 施工进度条：建造绿 / 升级黄 / 拆除红
			var progress: float = 1.0 - float(p["remaining"]) / float(p["total"])
			var bar_color: Color = {
				"build": Color(0.3, 0.9, 0.55, 0.95),
				"upgrade": Color(0.95, 0.8, 0.3, 0.95),
				"demolish": Color(0.95, 0.35, 0.3, 0.95),
			}.get(op, Color.WHITE)
			draw_rect(Rect2(scaled.position, Vector2(scaled.size.x, 5)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(scaled.position, Vector2(scaled.size.x * progress, 5)), bar_color)
		else:
			# 完工闪光
			if completion_effects.has(key):
				var t: float = float(completion_effects[key]) / ANIM_COMPLETE
				draw_rect(scaled.grow(6 * (1.0 - t)), Color(1, 0.9, 0.4, (1.0 - t) * 0.8), false, 3.0)

		# 建筑名
		draw_string(FONT_BOLD, scaled.position + Vector2(8, 20), item.get("name", "?"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.95))
		# 占地信息
		draw_string(FONT_NORMAL, scaled.position + Vector2(8, 34),
				"占地 %dx%d" % [w, h], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55))
		# 等级徽章（右上角）
		var level: int = int(p["level"])
		var badge_pos: Vector2 = scaled.position + Vector2(scaled.size.x - 30, 6)
		draw_circle(badge_pos + Vector2(9, 9), 11, Color(0.05, 0.1, 0.2, 0.85))
		draw_circle(badge_pos + Vector2(9, 9), 11, Color(0.4, 0.75, 1.0, 0.9), false, 2.0)
		draw_string(FONT_BOLD, badge_pos + Vector2(3, 15), "Lv.%d" % level,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.95))


## 立体建筑绘制：底部投影 + 侧面（深色）+ 顶面 + 窗格 + 建筑类型专属轮廓
func _draw_building_body(rect: Rect2, item: Dictionary, p: Dictionary, anchor: Vector2i, tint: Color) -> void:
	var side_depth: float = rect.size.y * 0.16
	var top_h: float = rect.size.y - side_depth
	var top_rect := Rect2(rect.position, Vector2(rect.size.x, top_h))
	# 底部投影
	draw_rect(Rect2(rect.position + Vector2(3, 4), rect.size), Color(0, 0, 0, 0.28))
	# 侧面（正面下方拉出立体感）
	draw_rect(Rect2(rect.position + Vector2(0, top_h), Vector2(rect.size.x, side_depth)), tint.darkened(0.5))
	# 顶面
	draw_rect(top_rect, tint.lightened(0.12))
	draw_rect(top_rect, tint.lightened(0.5), false, 2.0)
	# 施工中建筑顶面半透明（区分未完工）
	if not p.get("completed", false) and p.get("op", "") != "":
		draw_rect(top_rect, Color(0, 0, 0, 0.25))
	# 窗户（按坐标确定性明暗，夜间感灯光）
	var w: int = int(item.get("width", 1))
	var h: int = int(item.get("height", 1))
	var rows: int = maxi(1, h - 1)
	var win_w: float = rect.size.x / float(w) * 0.32
	var win_h: float = top_h / float(rows) * 0.3
	for wx: int in range(w):
		for wy: int in range(rows):
			var lit: float = _hash_noise(anchor.x * 10 + wx, anchor.y * 10 + wy, 80)
			if lit <= 0.3:
				continue
			var cx: float = rect.position.x + (wx + 0.5) * rect.size.x / float(w)
			var cy: float = rect.position.y + (wy + 0.5) * top_h / float(rows)
			draw_rect(Rect2(cx - win_w / 2, cy - win_h / 2, win_w, win_h),
					Color(1, 0.92, 0.6, 0.45 + lit * 0.5))
	# 建筑类型专属轮廓（伪 3D 细节）
	match item.get("id", ""):
		"finance":
			# 金融中心：尖顶塔冠
			var tower_w: float = rect.size.x * 0.3
			var tower_h: float = top_h * 0.35
			var tx: float = rect.position.x + rect.size.x * 0.5 - tower_w / 2
			var pts: PackedVector2Array = [
				Vector2(tx, rect.position.y + top_h * 0.4),
				Vector2(tx + tower_w / 2, rect.position.y + top_h * 0.4 - tower_h),
				Vector2(tx + tower_w, rect.position.y + top_h * 0.4),
			]
			draw_colored_polygon(pts, tint.lightened(0.3))
			draw_polyline(pts + PackedVector2Array([pts[0]]), tint.lightened(0.55), 2.0)
		"hospital":
			# 医院：红十字标识
			var cx2: float = rect.position.x + rect.size.x / 2
			var cy2: float = rect.position.y + top_h * 0.3
			var s: float = top_h * 0.09
			draw_rect(Rect2(cx2 - s * 3.2, cy2 - s, s * 6.4, s * 2), Color(0.95, 0.3, 0.32, 0.95))
			draw_rect(Rect2(cx2 - s, cy2 - s * 3.2, s * 2, s * 6.4), Color(0.95, 0.3, 0.32, 0.95))
		"school":
			# 学校：旗杆 + 旗帜
			draw_line(rect.position + Vector2(rect.size.x * 0.8, top_h), rect.position + Vector2(rect.size.x * 0.8, top_h * 0.25),
					Color(0.9, 0.9, 0.95, 0.9), 2.0)
			draw_colored_polygon(PackedVector2Array([
				rect.position + Vector2(rect.size.x * 0.8, top_h * 0.25),
				rect.position + Vector2(rect.size.x * 0.8 + top_h * 0.22, top_h * 0.34),
				rect.position + Vector2(rect.size.x * 0.8, top_h * 0.43),
			]), Color(0.85, 0.4, 0.5, 0.95))
		"office":
			# 办公楼：顶部高光条（玻璃幕墙感）
			draw_rect(Rect2(rect.position + Vector2(rect.size.x * 0.15, 3), Vector2(rect.size.x * 0.7, 3)),
					Color(0.9, 0.98, 1, 0.35))
		"residence":
			# 住宅：烟囱 + 屋檐线
			draw_rect(Rect2(rect.position + Vector2(rect.size.x * 0.12, top_h * 0.3), Vector2(rect.size.x * 0.14, top_h * 0.16)),
					tint.darkened(0.3))
			draw_line(rect.position + Vector2(0, top_h * 0.22), rect.position + Vector2(rect.size.x, top_h * 0.22),
					tint.lightened(0.55), 2.0)


func _draw_preview(origin: Vector2) -> void:
	if preview_item.is_empty() or hover_cell.x < 0 or hover_cell.y < 0:
		return
	var w: int = int(preview_item.get("width", 1))
	var h: int = int(preview_item.get("height", 1))
	var rect := Rect2(origin + Vector2(hover_cell * _cell()), Vector2(w * _cell(), h * _cell()))
	var can_afford: bool = GameState.gold >= float(preview_item.get("cost", 0))
	var can_build: bool = can_build_at(hover_cell, w, h) and can_afford
	var color: Color
	if can_build:
		color = Color(0.3, 0.95, 0.5, 0.4)
	elif not can_afford:
		# 金币不足：红色闪烁警告预选状态
		var blink: float = 0.55 + 0.35 * sin(Time.get_ticks_msec() * 0.012)
		color = Color(0.95, 0.25, 0.25, blink)
	else:
		color = Color(0.95, 0.3, 0.3, 0.4)
	draw_rect(rect, color)
	draw_rect(rect, Color(color, 0.9), false, 2.0)


# === 粒子系统 ===

func _tick_particles(delta: float) -> void:
	var done: Array[int] = []
	for i: int in range(effect_particles.size()):
		var pt: Dictionary = effect_particles[i]
		pt["life"] = float(pt["life"]) - delta
		pt["pos"] = Vector2(pt["pos"]) + Vector2(pt["vel"]) * delta
		# 拆除碎片受重力下落
		if pt.get("kind", "") == "debris":
			pt["vel"] = Vector2(pt["vel"]) + Vector2(0, 260) * delta
		if float(pt["life"]) <= 0.0:
			done.append(i)
	for i: int in done.size():
		var idx: int = int(done[done.size() - 1 - i])
		effect_particles.remove_at(idx)
	if not done.is_empty():
		queue_redraw()


func _spawn_build_particles(cell: Vector2i, kind: String) -> void:
	# 在建筑中心生成特效粒子（place 光柱 / complete 金色爆发 / upgrade 上升 / demolish 碎片）
	var center: Vector2 = _grid_origin() + Vector2(cell * _cell()) + Vector2(_cell(), _cell()) * 0.5
	match kind:
		"place":
			for i: int in range(14):
				var ang: float = randf() * TAU
				effect_particles.append({
					"pos": center, "vel": Vector2(cos(ang), sin(ang)) * randf_range(40, 120),
					"life": 0.6, "max_life": 0.6, "color": Color(0.5, 0.9, 1, 0.9),
					"size": 3.0, "kind": "spark",
				})
			# 光柱
			effect_particles.append({
				"pos": center, "vel": Vector2(0, -60),
				"life": 0.5, "max_life": 0.5, "color": Color(0.7, 0.95, 1, 0.8),
				"size": _cell() * 0.9, "kind": "beam",
			})
		"complete":
			for i: int in range(20):
				var ang: float = randf() * TAU
				effect_particles.append({
					"pos": center, "vel": Vector2(cos(ang), sin(ang)) * randf_range(60, 160),
					"life": 0.9, "max_life": 0.9, "color": Color(1, 0.85, 0.35, 1.0),
					"size": 4.0, "kind": "spark",
				})
		"upgrade":
			for i: int in range(12):
				effect_particles.append({
					"pos": center + Vector2(randf_range(-20, 20), 0),
					"vel": Vector2(0, -randf_range(50, 110)),
					"life": 0.8, "max_life": 0.8, "color": Color(0.6, 0.9, 1, 0.9),
					"size": 3.0, "kind": "spark",
				})
		"demolish":
			for i: int in range(16):
				effect_particles.append({
					"pos": center + Vector2(randf_range(-_cell() * 0.4, _cell() * 0.4), -_cell() * 0.3),
					"vel": Vector2(randf_range(-90, 90), randf_range(-60, 20)),
					"life": 1.0, "max_life": 1.0, "color": Color(0.7, 0.55, 0.4, 1.0),
					"size": 4.0, "kind": "debris",
				})
	queue_redraw()


func _draw_selection(origin: Vector2) -> void:
	# 批量拆除框选区域（红色半透明矩形）
	if demolish_mode and _select_start.x >= 0 and _select_end.x >= 0:
		var r: Rect2i = _selection_rect()
		var rect := Rect2(origin + Vector2(r.position * int(_cell())),
				Vector2(r.size * int(_cell())))
		draw_rect(rect, Color(1, 0.35, 0.3, 0.25))
		draw_rect(rect, Color(1, 0.35, 0.3, 0.85), false, 2.0)
		var blink: float = 0.5 + 0.4 * sin(Time.get_ticks_msec() * 0.008)
		draw_rect(rect, Color(1, 0.9, 0.5, blink * 0.6), false, 1.0)


func _draw_particles() -> void:
	for pt: Dictionary in effect_particles:
		var alpha: float = float(pt["life"]) / float(pt["max_life"])
		var pos: Vector2 = Vector2(pt["pos"])
		var color: Color = Color(pt["color"])
		color.a *= alpha
		match pt.get("kind", ""):
			"beam":
				# 放置光柱：竖直渐隐矩形
				draw_rect(Rect2(pos - Vector2(float(pt["size"]) * 0.5, float(pt["size"]) * 1.2),
						Vector2(float(pt["size"]), float(pt["size"]) * 2.4)), Color(color, color.a * 0.4))
			"debris":
				draw_rect(Rect2(pos - Vector2(2, 2), Vector2(5, 5)), Color(color, color.a))
			_:
				draw_circle(pos, float(pt["size"]) * (0.5 + alpha * 0.5), Color(color, color.a))


# === 人流粒子（越繁荣人流量越大）===

func _tick_people(delta: float) -> void:
	# 收集已完工建筑中心作为兴趣点
	_people_spots.clear()
	for key: String in BuildingSystem.placed:
		var p: Dictionary = BuildingSystem.placed[key]
		if not p.get("completed", false):
			continue
		var anchor: Vector2i = BuildingSystem.BuildingGrid.key_to_cell(key)
		_people_spots.append(_grid_origin() + Vector2(anchor * _cell()) + Vector2(_cell(), _cell()) * 0.5)
	if _people_spots.is_empty():
		if not _people.is_empty():
			_people.clear()
			queue_redraw()
		return
	# 人口越多人群越多（上限 PEOPLE_MAX）
	var target_count: int = mini(PEOPLE_MAX, _people_spots.size() * 2)
	if _people.size() < target_count:
		var spawn_n: int = target_count - _people.size()
		for i: int in range(spawn_n):
			_people.append(_spawn_person())
	elif _people.size() > target_count:
		_people.resize(target_count)
	# 移动
	for p in _people:
		var pos: Vector2 = Vector2(p["pos"])
		var target: Vector2 = Vector2(p["target"])
		var dir: Vector2 = target - pos
		var dist: float = dir.length()
		if dist < 3.0:
			p["target"] = _people_spots[randi() % _people_spots.size()]
		else:
			p["pos"] = pos + dir.normalized() * float(p["speed"]) * delta
	if _people.size() > 0:
		queue_redraw()


func _spawn_person() -> Dictionary:
	return {
		"pos": _people_spots[randi() % _people_spots.size()] + Vector2(randf_range(-6, 6), randf_range(-6, 6)),
		"target": _people_spots[randi() % _people_spots.size()],
		"speed": randf_range(18, 34),
	}


func _draw_people() -> void:
	for p in _people:
		var pos: Vector2 = Vector2(p["pos"])
		draw_circle(pos, 2.2, Color(1, 0.92, 0.8, 0.75))
		draw_circle(pos + Vector2(0, -3), 1.6, Color(0.9, 0.75, 0.6, 0.7))


# === 工具 ===

func _cell() -> float: return float(BuildingSystem.cell_size) * zoom


func set_demolish_mode(on: bool) -> void:
	## 批量拆除模式开关：开启后左键拖动框选，右键退出
	demolish_mode = on
	_select_start = Vector2i(-1, -1)
	_select_end = Vector2i(-1, -1)
	demolish_mode_changed.emit(on)
	queue_redraw()


func _selection_rect() -> Rect2i:
	return Rect2i(mini(_select_start.x, _select_end.x), mini(_select_start.y, _select_end.y),
			abs(_select_end.x - _select_start.x) + 1, abs(_select_end.y - _select_start.y) + 1)


func set_zoom(new_zoom: float) -> void:
	## 滚轮缩放地图（最小缩放动态适配地图尺寸，保证整图可见；最大 3.0x），
	## 网格以中央区域中心为锚点缩放；同步 BuildingSystem.map_zoom 实现跨场景/跨启动记忆
	zoom = clampf(new_zoom, _min_zoom(), ZOOM_MAX)
	BuildingSystem.set_map_zoom(zoom)
	_clamp_pan()
	queue_redraw()


func _zoom_at(cursor: Vector2, factor: float) -> void:
	## 以光标为锚点缩放：光标下的地图点缩放前后位置保持不变
	var new_zoom: float = clampf(zoom * factor, _min_zoom(), ZOOM_MAX)
	if is_equal_approx(new_zoom, zoom):
		return
	var rel: Vector2 = (cursor - _grid_origin()) / zoom  # 光标相对网格原点（zoom=1 像素单位）
	zoom = new_zoom
	BuildingSystem.set_map_zoom(zoom)
	_pan = cursor - _base_origin() - rel * zoom
	_clamp_pan()
	queue_redraw()


func _base_origin() -> Vector2:
	# 无平移时的网格居中位置（缩放以中央区域中心为锚）
	var grid_px: Vector2 = Vector2(BuildingSystem.GRID_W, BuildingSystem.GRID_H) * _cell()
	return Vector2((size.x - grid_px.x) / 2.0, 30.0)


func _grid_origin() -> Vector2:
	# 网格居中 + 平移偏移（左键拖动查看）
	return _base_origin() + _pan


func _min_zoom() -> float:
	# 动态最小缩放：保证无论地图多大，最小都能缩放到看到整个地图（宽高分别适配视口）
	var fit_x: float = size.x / (float(BuildingSystem.GRID_W) * float(BuildingSystem.cell_size))
	var fit_y: float = size.y / (float(BuildingSystem.GRID_H) * float(BuildingSystem.cell_size))
	return minf(ZOOM_MIN, minf(fit_x, fit_y))


func _ensure_min_zoom() -> void:
	# 恢复/窗口变化后校正最小缩放：大地图时恢复值可能低于整图可见所需
	var mz: float = _min_zoom()
	if zoom < mz:
		zoom = mz
		BuildingSystem.set_map_zoom(zoom)
		_clamp_pan()
		queue_redraw()


func _clamp_pan() -> void:
	# 地图视窗不能移动到地图外面：地图比视口大时，视口四边始终被地图覆盖（看不到地图外的空白）；
	# 地图比视口小时锁定居中（不产生可拖动的空白区域）
	var grid_px: Vector2 = Vector2(BuildingSystem.GRID_W, BuildingSystem.GRID_H) * _cell()
	var base: Vector2 = _base_origin()
	if grid_px.x >= size.x:
		_pan.x = clampf(_pan.x, size.x - base.x - grid_px.x, -base.x)
	else:
		_pan.x = 0.0
	if grid_px.y >= size.y:
		_pan.y = clampf(_pan.y, size.y - base.y - grid_px.y, -base.y)
	else:
		_pan.y = 0.0


func _notification(what: int) -> void:
	# 窗口尺寸变化后：重新校正最小缩放（整图可见）并约束平移范围
	if what == NOTIFICATION_RESIZED:
		_ensure_min_zoom()
		_clamp_pan()
		queue_redraw()


func _pos_to_cell(pos: Vector2) -> Vector2i:
	var origin: Vector2 = _grid_origin()
	var rel: Vector2 = pos - origin
	if rel.x < 0 or rel.y < 0:
		return Vector2i(-1, -1)
	var x: int = int(rel.x / _cell())
	var y: int = int(rel.y / _cell())
	if x >= BuildingSystem.GRID_W or y >= BuildingSystem.GRID_H:
		return Vector2i(-1, -1)
	return Vector2i(x, y)


func can_build_at(cell: Vector2i, w: int, h: int) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x + w > BuildingSystem.GRID_W \
			or cell.y + h > BuildingSystem.GRID_H:
		return false
	for dx: int in range(w):
		for dy: int in range(h):
			if BuildingSystem.grid[cell.x + dx][cell.y + dy] != "":
				return false
	return true


func _key_to_cell(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
