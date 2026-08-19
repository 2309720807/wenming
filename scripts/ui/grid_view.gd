extends Control
class_name GridView

## 网格地图视图：绘制网格/障碍/建筑/预览，处理悬停与点击
## 设计依据：docs/design/game_design.md 3.7
## 网格尺寸以 BuildingSystem.cell_size 为准（数据驱动，data/buildings.json）

signal hover_changed(cell: Vector2i)
signal cell_clicked(cell: Vector2i)

const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")
const FONT_NORMAL: Font = preload("res://assets/fonts/SourceHanSansCN-Normal.ttf")
const ANIM_PLACE: float = 0.3
const ANIM_COMPLETE: float = 0.6

var hover_cell: Vector2i = Vector2i(-1, -1)
var preview_item: Dictionary = {}  # 当前选中待放置的建筑配置
var place_animations: Dictionary = {}   # "x,y" -> 已播放时长（放置缩放动画）
var completion_effects: Dictionary = {} # "x,y" -> 已播放时长（完工闪光）


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	_tick_animations(place_animations, ANIM_PLACE, delta)
	_tick_animations(completion_effects, ANIM_COMPLETE, delta)


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
	if event is InputEventMouseMotion:
		var cell: Vector2i = _pos_to_cell(event.position)
		if cell != hover_cell:
			hover_cell = cell
			hover_changed.emit(cell)
			queue_redraw()
	elif event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		cell_clicked.emit(_pos_to_cell(event.position))


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
	_draw_preview(origin)


func _draw_cell(origin: Vector2, cell: Vector2i) -> void:
	var rect := Rect2(origin + Vector2(cell * _cell()), Vector2(_cell(), _cell()))
	draw_rect(rect, Color(0.05, 0.1, 0.2, 0.5), false, 1.0)


func _draw_obstacles(origin: Vector2) -> void:
	# 障碍只有锚点格标记 obs:xxx，需按 w×h 绘制完整矩形（湖泊等大障碍）
	for x: int in range(BuildingSystem.GRID_W):
		for y: int in range(BuildingSystem.GRID_H):
			var mark: String = str(BuildingSystem.grid[x][y])
			if not mark.begins_with("obs:"):
				continue
			var obs: Dictionary = BuildingSystem.obstacles_data.get(mark.substr(4), {})
			var rect := Rect2(origin + Vector2(x, y) * _cell(),
					Vector2(int(obs.get("width", 1)) * _cell(), int(obs.get("height", 1)) * _cell()))
			var color: Color = Color(obs.get("color", "#888888"))
			var inner := rect.grow(-4)
			if obs.get("id", "") == "lake":
				draw_rect(inner, Color(color, 0.8))
				draw_arc(inner.get_center(), inner.size.x * 0.25, 0, TAU, 12, Color(1, 1, 1, 0.25), 2.0)
			else:
				draw_circle(inner.get_center(), inner.size.x * 0.32, Color(color, 0.9))
				draw_circle(inner.get_center(), inner.size.x * 0.14, Color(1, 1, 1, 0.35))


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
		var scaled := rect.grow(rect.size.x * (1.0 - scale_factor) * 0.5) \
				if scale_factor < 1.0 else rect

		var color: Color = Color(item.get("color", "#6a7fa8"))
		var op: String = p["op"]
		var active: bool = p["completed"] or op != ""
		var blink: float = 0.0
		if op == "demolish":
			# 拆除中建筑闪烁提示
			blink = 0.55 + 0.35 * sin(Time.get_ticks_msec() * 0.01)
		draw_rect(scaled, Color(color, 0.95 if active else 0.55))
		draw_rect(scaled, color.lightened(0.35), false, 2.0)

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


func _draw_preview(origin: Vector2) -> void:
	if preview_item.is_empty() or hover_cell.x < 0 or hover_cell.y < 0:
		return
	var w: int = int(preview_item.get("width", 1))
	var h: int = int(preview_item.get("height", 1))
	var rect := Rect2(origin + Vector2(hover_cell * _cell()), Vector2(w * _cell(), h * _cell()))
	var can_build: bool = can_build_at(hover_cell, w, h)
	var color: Color = Color(0.3, 0.95, 0.5, 0.4) if can_build else Color(0.95, 0.3, 0.3, 0.4)
	draw_rect(rect, color)
	draw_rect(rect, Color(color, 0.9), false, 2.0)


# === 工具 ===

func _cell() -> int: return BuildingSystem.cell_size


func _grid_origin() -> Vector2:
	# 网格居中填满中央区域（两侧留少量边距，底部给信息窗留空间）
	var grid_px: Vector2 = Vector2(BuildingSystem.GRID_W, BuildingSystem.GRID_H) * _cell()
	return Vector2((size.x - grid_px.x) / 2.0, 30.0)


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
