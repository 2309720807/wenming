extends Control

## 军事与防御界面：右上角军事/防御切换，默认军事。
## 军事页：消耗金币+科技点制造军事设施（进入库存）。
## 防御页：军事基地网格建设，从库存部署设施，可扩大基地；军事规模达标后人机攻城。
## 设计依据：docs/design/game_design.md 3.12

const FONT_HEAVY: Font = preload("res://assets/fonts/SourceHanSansCN-Heavy.ttf")
const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")
const FONT_SERIF: Font = preload("res://assets/fonts/SourceHanSerifCN-Regular.otf")

var _current_page: String = "military"  # military / defense
var _selected_unit: String = ""          # 防御页选中的库存设施 id
var _info_label: Label
var _inventory_box: VBoxContainer
var _base_grid: MilitaryBaseGrid
var _military_panel: VBoxContainer
var _defense_panel: VBoxContainer


func _ready() -> void:
	WindowManager.setup_scale_root(self)
	_build_ui()
	MilitarySystem.inventory_changed.connect(_refresh_inventory)
	MilitarySystem.base_changed.connect(func(_c: Vector2i) -> void: _refresh_base_info())
	MilitarySystem.siege_triggered.connect(func(wave: int, power: int) -> void:
		_info_label.text = "⚔ 人机攻城来袭！第 %d 波（战力 %d）" % [wave, power])
	MilitarySystem.siege_resolved.connect(func(victory: bool, destroyed: int) -> void:
		if victory:
			_info_label.text = "🛡 成功击退攻城！获得奖励"
		else:
			_info_label.text = "💥 基地被攻破，损失 %d 个设施" % destroyed)
	_switch_page("military")


func _build_ui() -> void:
	# 科幻渐变背景（深蓝星空感）
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.01, 0.03, 0.09, 1), Color(0.05, 0.1, 0.22, 1), Color(0.01, 0.02, 0.07, 1)])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0.5, 0)
	gtex.fill_to = Vector2(0.5, 1)
	var bg := TextureRect.new()
	bg.texture = gtex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 顶部资源栏（全局资源可见，同主界面顶栏信息）
	var res_bar := ResourceBar.new()
	res_bar.name = "ResourceBar"
	res_bar.position = Vector2(0, 6)
	res_bar.size = Vector2(1280, 44)
	add_child(res_bar)

	# 顶栏
	var top := HBoxContainer.new()
	top.position = Vector2(16, 58)
	top.custom_minimum_size = Vector2(1248, 46)
	top.add_theme_constant_override("separation", 12)
	add_child(top)
	var title := Label.new()
	title.text = "⚔ 军事与防御"
	title.add_theme_font_override("font", FONT_HEAVY)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.4, 0.82, 1, 1))
	top.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var btn_military := Button.new()
	btn_military.text = "军事"
	btn_military.custom_minimum_size = Vector2(96, 38)
	btn_military.add_theme_font_override("font", FONT_BOLD)
	btn_military.add_theme_font_size_override("font_size", 15)
	btn_military.pressed.connect(func() -> void: _switch_page("military"))
	top.add_child(btn_military)
	var btn_defense := Button.new()
	btn_defense.text = "防御"
	btn_defense.custom_minimum_size = Vector2(96, 38)
	btn_defense.add_theme_font_override("font", FONT_BOLD)
	btn_defense.add_theme_font_size_override("font_size", 15)
	btn_defense.pressed.connect(func() -> void: _switch_page("defense"))
	top.add_child(btn_defense)
	var btn_back := Button.new()
	btn_back.text = "返回主界面"
	btn_back.custom_minimum_size = Vector2(130, 38)
	btn_back.add_theme_font_override("font", FONT_BOLD)
	btn_back.add_theme_font_size_override("font_size", 14)
	btn_back.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/ui/main_ui.tscn"))
	top.add_child(btn_back)

	# 内容区
	var content := HBoxContainer.new()
	content.position = Vector2(16, 112)
	content.custom_minimum_size = Vector2(1248, 540)
	content.add_theme_constant_override("separation", 14)
	add_child(content)

	# 左：军事页（制造列表）/ 防御页（库存列表）
	_military_panel = VBoxContainer.new()
	_military_panel.custom_minimum_size = Vector2(380, 560)
	_military_panel.add_theme_constant_override("separation", 8)
	content.add_child(_military_panel)
	_defense_panel = VBoxContainer.new()
	_defense_panel.custom_minimum_size = Vector2(380, 560)
	_defense_panel.add_theme_constant_override("separation", 8)
	content.add_child(_defense_panel)

	# 右：基地网格 / 信息
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	content.add_child(right)

	_base_grid = MilitaryBaseGrid.new()
	_base_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_base_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_base_grid.custom_minimum_size = Vector2(600, 420)
	_base_grid.unit_selected.connect(func(unit_id: String) -> void:
		_selected_unit = unit_id
		_base_grid.selected_unit = unit_id
		_refresh_defense_panel())
	_base_grid.remove_requested.connect(func(cell: Vector2i) -> void:
		MilitarySystem.remove_unit(cell))
	_base_grid.place_requested.connect(func(cell: Vector2i) -> void:
		# 部署选中设施到基地（从库存扣减）
		if _selected_unit.is_empty():
			return
		if MilitarySystem.place_unit(_selected_unit, cell):
			_info_label.text = "已部署设施到基地"
		else:
			_info_label.text = "部署失败：库存不足或位置不可用")
	right.add_child(_base_grid)

	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size = Vector2(0, 60)
	_info_label.add_theme_font_override("font", FONT_SERIF)
	_info_label.add_theme_font_size_override("font_size", 14)
	_info_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1, 0.95))
	right.add_child(_info_label)


func _switch_page(page: String) -> void:
	_current_page = page
	_military_panel.visible = (page == "military")
	_defense_panel.visible = (page == "defense")
	_base_grid.edit_mode = (page == "defense")
	if page == "military":
		_build_military_page()
	else:
		_refresh_defense_panel()


# === 军事页：制造 ===

func _build_military_page() -> void:
	for child: Node in _military_panel.get_children():
		child.queue_free()
	var head := Label.new()
	head.text = "制造军事设施（消耗金币 + 科技点）"
	head.add_theme_font_override("font", FONT_BOLD)
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", Color(0.5, 0.8, 1, 0.95))
	_military_panel.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_military_panel.add_child(scroll)
	_inventory_box = VBoxContainer.new()
	_inventory_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_inventory_box)
	_refresh_inventory()


func _refresh_inventory() -> void:
	if _inventory_box == null:
		return
	for child: Node in _inventory_box.get_children():
		child.queue_free()
	for unit_id: String in MilitarySystem.units_data:
		var unit: Dictionary = MilitarySystem.units_data[unit_id]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _make_card_style())
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("margin_left", 12)
		vbox.add_theme_constant_override("margin_right", 12)
		vbox.add_theme_constant_override("margin_top", 8)
		vbox.add_theme_constant_override("margin_bottom", 8)
		vbox.add_theme_constant_override("separation", 4)
		card.add_child(vbox)
		var name_label := Label.new()
		name_label.text = "%s · 库存 %d" % [unit.get("name", ""), int(MilitarySystem.inventory.get(unit_id, 0))]
		name_label.add_theme_font_override("font", FONT_BOLD)
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", Color(1, 0.85, 0.5, 1))
		vbox.add_child(name_label)
		var desc := Label.new()
		desc.text = "%s\n消耗：%d 金币 + %d 科技点 · 占地 %dx%d" % [
			unit.get("desc", ""), int(unit.get("cost_gold", 0)), int(unit.get("cost_tech", 0)),
			int(unit.get("width", 1)), int(unit.get("height", 1))]
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_override("font", FONT_SERIF)
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(0.72, 0.8, 0.92, 0.9))
		vbox.add_child(desc)
		var make_btn := Button.new()
		make_btn.text = "制造 ×1"
		make_btn.custom_minimum_size = Vector2(0, 34)
		make_btn.add_theme_font_override("font", FONT_BOLD)
		make_btn.add_theme_font_size_override("font_size", 13)
		make_btn.pressed.connect(func() -> void:
			var result: Dictionary = MilitarySystem.manufacture(unit_id)
			_info_label.text = result["message"])
		vbox.add_child(make_btn)
		_inventory_box.add_child(card)


# === 防御页：库存选择 ===

func _refresh_defense_panel() -> void:
	if _defense_panel == null:
		return
	for child: Node in _defense_panel.get_children():
		child.queue_free()
	var head := Label.new()
	head.text = "选择库存设施部署到基地（右键拆除）"
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_font_override("font", FONT_BOLD)
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(0.5, 0.8, 1, 0.95))
	_defense_panel.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_defense_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	for unit_id: String in MilitarySystem.units_data:
		var count: int = int(MilitarySystem.inventory.get(unit_id, 0))
		var unit: Dictionary = MilitarySystem.units_data[unit_id]
		var btn := Button.new()
		var selected: bool = (unit_id == _selected_unit)
		btn.text = "%s ×%d%s" % [unit.get("name", ""), count, "  ✅" if selected else ""]
		btn.custom_minimum_size = Vector2(0, 36)
		btn.add_theme_font_override("font", FONT_BOLD)
		btn.add_theme_font_size_override("font_size", 14)
		btn.disabled = (count <= 0)
		btn.pressed.connect(_on_inventory_btn_pressed.bind(unit_id))
		box.add_child(btn)
	# 扩大基地
	var expand_btn := Button.new()
	expand_btn.text = "扩大基地（+2x+2）"
	expand_btn.custom_minimum_size = Vector2(0, 36)
	expand_btn.add_theme_font_override("font", FONT_BOLD)
	expand_btn.add_theme_font_size_override("font_size", 13)
	expand_btn.pressed.connect(func() -> void:
		var result: Dictionary = MilitarySystem.expand_base()
		_info_label.text = result["message"])
	_defense_panel.add_child(expand_btn)
	_refresh_base_info()


func _on_inventory_btn_pressed(unit_id: String) -> void:
	## 库存设施按钮：选中/取消选中，并同步基地网格的选中设施
	_selected_unit = unit_id if _selected_unit != unit_id else ""
	_base_grid.selected_unit = _selected_unit
	_refresh_defense_panel()


func _refresh_base_info() -> void:
	if _base_grid == null:
		return
	_base_grid.queue_redraw()
	if _current_page == "defense":
		_info_label.text = "军事规模：%d（攻城阈值 %d）· 基地 %dx%d · 已部署 %d" % [
			MilitarySystem.military_score(), MilitarySystem.SIEGE_THRESHOLD,
			MilitarySystem.BASE_W, MilitarySystem.BASE_H, MilitarySystem.base_placed.size()]


func _make_card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.11, 0.22, 0.95)
	sb.border_color = Color(0.3, 0.55, 0.9, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	return sb


# ================= 军事基地网格（内部类） =================

class MilitaryBaseGrid:
	extends Control

	## 军事基地网格：绘制 base_grid/base_placed，点击部署选中设施，右键拆除。

	signal unit_selected(unit_id: String)  # 点击已部署设施时选中其类型
	signal remove_requested(cell: Vector2i)
	signal place_requested(cell: Vector2i)  # 点击空白格部署选中设施

	const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")

	var edit_mode: bool = false
	var selected_unit: String = ""  # 父类同步的当前选中设施 id
	var _hover_cell: Vector2i = Vector2i(-1, -1)


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP


	func _gui_input(event: InputEvent) -> void:
		if not edit_mode:
			return
		if event is InputEventMouseMotion:
			var c: Vector2i = _pos_to_cell(event.position)
			if c != _hover_cell:
				_hover_cell = c
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed:
			var c: Vector2i = _pos_to_cell(event.position)
			if event.button_index == MOUSE_BUTTON_LEFT:
				# 点击已部署设施则选中其类型；点击空白格部署选中设施
				var placed_key: String = MilitarySystem.get_placed_key(c)
				if placed_key != "":
					unit_selected.emit(MilitarySystem.base_placed[placed_key]["unit_id"])
					return
				if not selected_unit.is_empty():
					place_requested.emit(c)
				else:
					unit_selected.emit("")  # 无选中设施时取消选择
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				if MilitarySystem.get_placed_key(c) != "":
					remove_requested.emit(c)


	func _draw() -> void:
		var origin: Vector2 = _grid_origin()
		var cell: float = MilitarySystem.cell_size * 0.9
		var grid_px: Vector2 = Vector2(MilitarySystem.BASE_W, MilitarySystem.BASE_H) * cell
		draw_rect(Rect2(origin, grid_px), Color(0.03, 0.06, 0.12, 0.9))
		for x: int in range(MilitarySystem.BASE_W):
			for y: int in range(MilitarySystem.BASE_H):
				draw_rect(Rect2(origin + Vector2(x, y) * cell, Vector2(cell, cell)),
						Color(0.05, 0.1, 0.2, 0.5), false, 1.0)
		# 已部署设施（立体感：侧面+顶面）
		for key: String in MilitarySystem.base_placed:
			var p: Dictionary = MilitarySystem.base_placed[key]
			var unit: Dictionary = MilitarySystem.units_data.get(p["unit_id"], {})
			var anchor: Vector2i = MilitarySystem._key_to_cell(key)
			var rect := Rect2(origin + Vector2(anchor * int(cell)), Vector2(int(p["width"]) * cell, int(p["height"]) * cell))
			var c: Color = _unit_color(p["unit_id"])
			draw_rect(Rect2(rect.position + Vector2(2, 3), rect.size), Color(0, 0, 0, 0.3))
			draw_rect(rect, c.darkened(0.45))  # 侧面
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.8)), c.lightened(0.12))
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.8)), c.lightened(0.5), false, 2.0)
			draw_string(FONT_BOLD, rect.position + Vector2(6, rect.size.y * 0.55), unit.get("name", "?"),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.95))
		# 悬停高亮
		if _hover_cell.x >= 0 and _hover_cell.y >= 0:
			draw_rect(Rect2(origin + Vector2(_hover_cell * int(cell)), Vector2(cell, cell)),
					Color(0.4, 0.8, 1, 0.25))


	func _unit_color(unit_id: String) -> Color:
		match unit_id:
			"turret": return Color(0.75, 0.35, 0.3)
			"wall": return Color(0.5, 0.52, 0.58)
			"barracks": return Color(0.4, 0.5, 0.85)
			"aa": return Color(0.8, 0.55, 0.25)
			"armory": return Color(0.55, 0.4, 0.75)
			"bunker": return Color(0.35, 0.65, 0.55)
			_: return Color(0.5, 0.6, 0.8)


	func _grid_origin() -> Vector2:
		var cell: float = MilitarySystem.cell_size * 0.9
		var grid_px: Vector2 = Vector2(MilitarySystem.BASE_W, MilitarySystem.BASE_H) * cell
		return Vector2((size.x - grid_px.x) / 2.0, (size.y - grid_px.y) / 2.0)


	func _pos_to_cell(pos: Vector2) -> Vector2i:
		var origin: Vector2 = _grid_origin()
		var cell: float = MilitarySystem.cell_size * 0.9
		var rel: Vector2 = pos - origin
		if rel.x < 0 or rel.y < 0:
			return Vector2i(-1, -1)
		return Vector2i(int(rel.x / cell), int(rel.y / cell))
