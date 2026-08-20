class_name DebugConsole
extends Control

## 开发者调试台：时间倍速、数值调节、游戏资产数据浏览、离线挂机模拟、存档管理。
## 入口：设置面板礼包码输入 tiaoshitai（GiftCodeManager 特判，见 AGENTS.md 3.2）
## 面板组件已合并为内部类（避免过度拆分，见 AGENTS.md 3.1）：
##   DebugStatsPanel（数值调试）、DebugAssetsView（资产浏览）、DebugOfflinePanel（离线模拟）、DebugSavePanel（存档管理）

const FONT_HEAVY: Font = preload("res://assets/fonts/SourceHanSansCN-Heavy.ttf")
const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")
const PANEL_SIZE: Vector2 = Vector2(620, 640)
const SPEEDS: Array[float] = [1.0, 2.0, 3.0, 5.0, 10.0]

var _overlay: ColorRect
var _speed_buttons: Dictionary = {}  # speed -> Button
var _pause_btn: Button


func _ready() -> void:
	_build_ui()
	hide()


func open() -> void:
	show()
	var stats: DebugStatsPanel = _find_child("DebugStatsPanel") as DebugStatsPanel
	if stats:
		stats.refresh()
	_update_speed_buttons()
	_update_pause_btn()


func close() -> void:
	hide()


func _build_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# 半透明遮罩：点击空白处关闭调试台
	_overlay = ColorRect.new()
	_overlay.color = Color(0, 0, 0, 0.55)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.gui_input.connect(func(_e: InputEvent) -> void: close())
	add_child(_overlay)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	panel.position = Vector2((get_viewport_rect().size.x - PANEL_SIZE.x) / 2.0, 40.0)
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.add_theme_constant_override("margin_left", 18)
	vbox.add_theme_constant_override("margin_right", 18)
	vbox.add_theme_constant_override("margin_top", 14)
	vbox.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(vbox)

	# 标题行 + 关闭按钮
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "开发者调试台"
	title.add_theme_font_override("font", FONT_HEAVY)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.4, 0.85, 1, 1))
	head.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = "关闭 ✕"
	close_btn.custom_minimum_size = Vector2(72, 32)
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	vbox.add_child(head)

	# 可滚动内容区
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	content.add_child(_build_speed_group())
	var stats := DebugStatsPanel.new()
	stats.name = "DebugStatsPanel"
	content.add_child(stats)
	var assets_view := DebugAssetsView.new()
	assets_view.name = "DebugAssetsView"
	content.add_child(assets_view)
	var offline_panel := DebugOfflinePanel.new()
	offline_panel.name = "DebugOfflinePanel"
	content.add_child(offline_panel)
	var save_panel := DebugSavePanel.new()
	save_panel.name = "DebugSavePanel"
	content.add_child(save_panel)



func _build_speed_group() -> VBoxContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "时间控制"
	title.add_theme_font_override("font", FONT_BOLD)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.5, 0.8, 1, 0.9))
	group.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for s: float in SPEEDS:
		var btn := Button.new()
		btn.text = "%dx" % int(s)
		btn.custom_minimum_size = Vector2(58, 32)
		btn.pressed.connect(_on_speed_pressed.bind(s))
		_speed_buttons[s] = btn
		row.add_child(btn)
	group.add_child(row)

	_pause_btn = Button.new()
	_pause_btn.text = "⏸ 暂停"
	_pause_btn.custom_minimum_size = Vector2(0, 30)
	_pause_btn.pressed.connect(_on_pause_pressed)
	group.add_child(_pause_btn)
	return group


func _make_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.15, 0.97)
	sb.border_color = Color(0.3, 0.65, 1, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 20
	return sb


func _on_speed_pressed(speed: float) -> void:
	TimeManager.set_speed(speed)
	_update_speed_buttons()


func _on_pause_pressed() -> void:
	TimeManager.toggle_pause()
	_update_pause_btn()


func _update_speed_buttons() -> void:
	var current: float = TimeManager.get_speed()
	for s: float in _speed_buttons:
		_speed_buttons[s].modulate = Color(1, 1, 1, 1.0) if s == current else Color(1, 1, 1, 0.55)


func _update_pause_btn() -> void:
	_pause_btn.text = "▶ 继续" if TimeManager.get_pause_state() else "⏸ 暂停"


func _find_child(class_name_str: String) -> Node:
	for child: Node in get_children():
		if child.name == class_name_str:
			return child
	return null


# ================= 内部类（原独立面板文件已合并） =================

# === 数值调试面板（原 debug_stats_panel.gd）===
class DebugStatsPanel:
	extends VBoxContainer

	## 调试台-数值调试：GameState 全部公开数值 +/- 调节，实时生效并刷新 UI。
	## 数据源驱动：STAT_ITEMS 定义 GameState 属性映射；新增公开数值在此追加（见 AGENTS.md 3.2）

	const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")

	# key 对应 GameState 属性；step 为单次 +/- 步进
	const STAT_ITEMS: Array[Dictionary] = [
		{"key": "gold", "label": "金币", "step": 100.0},
		{"key": "food", "label": "食物", "step": 50.0},
		{"key": "wood", "label": "木材", "step": 30.0},
		{"key": "stone", "label": "石料", "step": 20.0},
		{"key": "metal", "label": "金属", "step": 10.0},
		{"key": "population", "label": "人口", "step": 1.0},
		{"key": "pop_max", "label": "人口上限", "step": 5.0},
		{"key": "happiness", "label": "幸福度", "step": 5.0},
		{"key": "tech_points", "label": "科技点", "step": 10.0},
		{"key": "culture_points", "label": "文化点", "step": 10.0},
		{"key": "gold_rate", "label": "金币速率", "step": 0.5},
		{"key": "food_rate", "label": "食物速率", "step": 0.5},
		{"key": "wood_rate", "label": "木材速率", "step": 0.5},
		{"key": "stone_rate", "label": "石料速率", "step": 0.5},
		{"key": "metal_rate", "label": "金属速率", "step": 0.5},
		{"key": "pop_growth_rate", "label": "人口增长率", "step": 0.1},
		{"key": "tech_rate", "label": "科技速率", "step": 0.1},
		{"key": "culture_rate", "label": "文化速率", "step": 0.1},
	]

	var _rows: Dictionary = {}  # key -> Label


	func _ready() -> void:
		var title := Label.new()
		title.text = "数值调试（+/- 实时生效）"
		title.add_theme_font_override("font", FONT_BOLD)
		title.add_theme_font_size_override("font_size", 14)
		title.add_theme_color_override("font_color", Color(0.5, 0.8, 1, 0.9))
		add_child(title)
		for item: Dictionary in STAT_ITEMS:
			add_child(_make_stat_row(item))
		refresh()


	func refresh() -> void:
		for key: String in _rows:
			_rows[key].text = _format_value(key, float(GameState.get(key)))


	func _format_value(key: String, value: float) -> String:
		if key in ["population", "pop_max", "happiness"]:
			return "%d" % int(value)
		return "%.1f" % value


	func _make_stat_row(item: Dictionary) -> HBoxContainer:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_label := Label.new()
		name_label.text = item["label"]
		name_label.custom_minimum_size = Vector2(120, 0)
		row.add_child(name_label)
		var value_label := Label.new()
		value_label.custom_minimum_size = Vector2(90, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_color_override("font_color", Color(0.6, 0.95, 1, 1))
		row.add_child(value_label)
		_rows[item["key"]] = value_label
		for delta: float in [-1.0, 1.0]:
			var btn := Button.new()
			btn.text = "−" if delta < 0 else "+"
			btn.custom_minimum_size = Vector2(34, 26)
			btn.pressed.connect(_apply_delta.bind(item, delta))
			row.add_child(btn)
		return row


	func _apply_delta(item: Dictionary, delta: float) -> void:
		# 通过 GameState 的 add_*/set_* API 修改（触发信号刷新 UI）；速率类赋值后补发信号
		var key: String = item["key"]
		var amount: float = delta * item["step"]
		match key:
			"gold":
				GameState.add_gold(amount)
			"food":
				GameState.add_food(amount)
			"wood":
				GameState.add_wood(amount)
			"stone":
				GameState.add_stone(amount)
			"metal":
				GameState.add_metal(amount)
			"population":
				GameState.set_population(GameState.population + int(amount))
			"happiness":
				GameState.set_happiness(GameState.happiness + int(amount))
			"pop_max":
				GameState.pop_max = maxi(1, GameState.pop_max + int(amount))
				GameState.population_changed.emit(GameState.population, GameState.pop_max)
			"tech_points":
				GameState.add_tech(amount)
			"culture_points":
				GameState.add_culture(amount)
			"gold_rate":
				GameState.gold_rate = maxf(0.0, GameState.gold_rate + amount)
				GameState.gold_changed.emit(GameState.gold, GameState.gold_rate)
			"food_rate":
				GameState.food_rate = maxf(0.0, GameState.food_rate + amount)
				GameState.food_changed.emit(GameState.food, GameState.food_rate)
			"wood_rate":
				GameState.wood_rate = maxf(0.0, GameState.wood_rate + amount)
				GameState.wood_changed.emit(GameState.wood)
			"stone_rate":
				GameState.stone_rate = maxf(0.0, GameState.stone_rate + amount)
				GameState.stone_changed.emit(GameState.stone)
			"metal_rate":
				GameState.metal_rate = maxf(0.0, GameState.metal_rate + amount)
				GameState.metal_changed.emit(GameState.metal)
			"pop_growth_rate":
				GameState.pop_growth_rate = maxf(0.0, GameState.pop_growth_rate + amount)
				GameState.population_changed.emit(GameState.population, GameState.pop_max)
			"tech_rate":
				GameState.tech_rate = maxf(0.0, GameState.tech_rate + amount)
				GameState.tech_changed.emit(GameState.tech_points)
			"culture_rate":
				GameState.culture_rate = maxf(0.0, GameState.culture_rate + amount)
				GameState.culture_changed.emit(GameState.culture_points)
		refresh()


# === 资产数据浏览面板（原 debug_assets_view.gd）===
class DebugAssetsView:
	extends VBoxContainer

	## 调试台-资产数据浏览：实时列出 data/*.json 加载的游戏资产。
	## 从 BuildingSystem / GiftCodeManager 数据源读取，新增资产条目自动出现
	## （禁止硬编码列表，见 AGENTS.md 3.2）

	const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")
	const FONT_SERIF: Font = preload("res://assets/fonts/SourceHanSerifCN-Regular.otf")

	var _text: RichTextLabel


	func _ready() -> void:
		var title := Label.new()
		title.text = "游戏资产数据"
		title.add_theme_font_override("font", FONT_BOLD)
		title.add_theme_font_size_override("font_size", 14)
		title.add_theme_color_override("font_color", Color(0.5, 0.8, 1, 0.9))
		add_child(title)

		var refresh_btn := Button.new()
		refresh_btn.text = "刷新资产列表"
		refresh_btn.custom_minimum_size = Vector2(0, 28)
		refresh_btn.pressed.connect(refresh)
		add_child(refresh_btn)

		_text = RichTextLabel.new()
		_text.bbcode_enabled = true
		_text.custom_minimum_size = Vector2(0, 170)
		_text.add_theme_font_override("normal_font", FONT_SERIF)
		_text.add_theme_font_size_override("normal_font_size", 12)
		add_child(_text)

		refresh()


	func refresh() -> void:
		var lines: Array[String] = []
		lines.append("[color=#88ccff]-- 建筑 --[/color]")
		for id: String in BuildingSystem.buildings_data:
			var b: Dictionary = BuildingSystem.buildings_data[id]
			lines.append("%s [%s] 费用%d 占地%dx%d %s" % [
				b.get("name", "?"), id, int(b.get("cost", 0)),
				int(b.get("width", 1)), int(b.get("height", 1)), _bonus_text(b),
			])
		lines.append("[color=#88ccff]-- 装饰 --[/color]")
		for id: String in BuildingSystem.decorations_data:
			var d: Dictionary = BuildingSystem.decorations_data[id]
			lines.append("%s [%s] 费用%d %s" % [d.get("name", "?"), id, int(d.get("cost", 0)), _bonus_text(d)])
		lines.append("[color=#88ccff]-- 障碍物 --[/color]")
		for id: String in BuildingSystem.obstacles_data:
			var o: Dictionary = BuildingSystem.obstacles_data[id]
			lines.append("%s [%s] 清除费%d" % [o.get("name", "?"), id, int(o.get("clear_cost", 0))])
		lines.append("[color=#88ccff]-- 礼包码 --[/color]")
		for code: String in GiftCodeManager._codes:
			var g: Dictionary = GiftCodeManager._codes[code]
			lines.append("%s → 金币+%d（%s）" % [code, int(g.get("gold", 0)), g.get("desc", "")])
		_text.text = "\n".join(lines)


	func _bonus_text(item: Dictionary) -> String:
		var parts: Array[String] = []
		for key: String in item.get("bonuses", {}):
			parts.append("%s+%s" % [key, str(item["bonuses"][key])])
		return "加成: " + " ".join(parts) if not parts.is_empty() else "无加成"


# === 离线挂机模拟面板（原 debug_offline_panel.gd）===
class DebugOfflinePanel:
	extends VBoxContainer

	## 调试台-离线挂机模拟：输入离线秒数立即结算收益，用于验证 OfflineGains 结算逻辑。
	## 规则依据：AGENTS.md 3.2（新系统必须提供调试分组）

	const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")
	const FONT_SERIF: Font = preload("res://assets/fonts/SourceHanSerifCN-Regular.otf")

	var _seconds_input: LineEdit
	var _result_label: Label


	func _ready() -> void:
		var title := Label.new()
		title.text = "离线挂机模拟（OfflineGains）"
		title.add_theme_font_override("font", FONT_BOLD)
		title.add_theme_font_size_override("font_size", 14)
		title.add_theme_color_override("font_color", Color(0.5, 0.8, 1, 0.9))
		add_child(title)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_seconds_input = LineEdit.new()
		_seconds_input.placeholder_text = "离线秒数，如 86400 = 1 天"
		_seconds_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_seconds_input)
		var apply_btn := Button.new()
		apply_btn.text = "模拟离线"
		apply_btn.pressed.connect(_on_apply)
		row.add_child(apply_btn)
		add_child(row)

		_result_label = Label.new()
		_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_result_label.add_theme_font_override("font", FONT_SERIF)
		_result_label.add_theme_font_size_override("font_size", 12)
		add_child(_result_label)


	func _on_apply() -> void:
		var secs: float = float(_seconds_input.text.strip_edges())
		if secs <= 0.0:
			_result_label.text = "请输入大于 0 的秒数"
			return
		var report: Dictionary = OfflineGains.apply_offline(secs)
		_result_label.text = "离线 %.1f 小时（%.1f 月）：金币 +%d" % [
			secs / 3600.0, report.get("months", 0.0), int(report.get("gold", 0)),
		]


# === 存档管理面板（原 debug_save_panel.gd）===
class DebugSavePanel:
	extends VBoxContainer

	## 调试台-存档管理：输入角色名保存当前进度；列出本地存档可加载/删除。
	## 规则依据：AGENTS.md 3.2（开发者调试工具）；数据由 SaveManager 管理（user://saves/）

	const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")
	const FONT_SERIF: Font = preload("res://assets/fonts/SourceHanSerifCN-Regular.otf")

	var _name_input: LineEdit
	var _result_label: Label
	var _save_list: SaveList


	func _ready() -> void:
		var title := Label.new()
		title.text = "存档管理（本地 user://saves/）"
		title.add_theme_font_override("font", FONT_BOLD)
		title.add_theme_font_size_override("font_size", 14)
		title.add_theme_color_override("font_color", Color(0.5, 0.8, 1, 0.9))
		add_child(title)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_name_input = LineEdit.new()
		_name_input.placeholder_text = "存档角色名（留空用当前玩家名）"
		_name_input.text = GameState.player_name
		_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_name_input)
		var save_btn := Button.new()
		save_btn.text = "保存当前进度"
		save_btn.pressed.connect(_on_save_pressed)
		row.add_child(save_btn)
		add_child(row)

		_result_label = Label.new()
		_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_result_label.add_theme_font_override("font", FONT_SERIF)
		_result_label.add_theme_font_size_override("font_size", 12)
		add_child(_result_label)

		_save_list = SaveList.new()
		_save_list.save_loaded.connect(_on_loaded)
		_save_list.save_deleted.connect(func(_f: String) -> void: _result_label.text = "存档已删除")
		add_child(_save_list)


	func _on_save_pressed() -> void:
		var role: String = _name_input.text.strip_edges()
		if role.is_empty():
			role = GameState.player_name
		var result: Dictionary = SaveManager.save_game(role)
		_show_result(result)
		_save_list.refresh()


	func _on_loaded(file_name: String) -> void:
		_show_result(SaveManager.load_game(file_name))


	func _show_result(result: Dictionary) -> void:
		_result_label.text = result.get("message", "")
		_result_label.modulate = Color(0.55, 1, 0.6, 1) if result.get("ok", false) else Color(1, 0.6, 0.5, 1)






