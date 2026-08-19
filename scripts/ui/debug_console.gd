class_name DebugConsole
extends Control

## 开发者调试台：时间倍速、数值调节、游戏资产数据浏览。
## 入口：设置面板礼包码输入 tiaoshitai（GiftCodeManager 特判，见 AGENTS.md 3.2）
## 组件：debug_stats_panel.gd（数值调试）、debug_assets_view.gd（资产浏览）

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
	content.add_child(DebugAssetsView.new())
	content.add_child(DebugOfflinePanel.new())
	content.add_child(DebugSavePanel.new())


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
