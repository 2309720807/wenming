class_name MapSummary
extends PanelContainer

## 建筑产出总览面板：实时汇总所有已建建筑/装饰的累计加成
## 数据来源 BuildingSystem.placed（与 BuildingSystem._recalculate_bonuses 同口径）
## 仅作展示，不参与游戏逻辑；监听 bonus_updated 信号刷新

const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")
const FONT_SERIF: Font = preload("res://assets/fonts/SourceHanSerifCN-Regular.otf")

# 汇总项定义：key 对应 buildings.json 的 bonuses 字段；is_float 决定取整方式
const STAT_DEFS: Array[Dictionary] = [
	{"key": "gold_rate", "label": "金币/月", "color": Color(1.0, 0.85, 0.4), "is_float": true},
	{"key": "pop_max", "label": "人口上限", "color": Color(0.5, 1.0, 0.7), "is_float": false},
	{"key": "pop_growth_rate", "label": "人口/月", "color": Color(0.6, 1.0, 0.8), "is_float": true},
	{"key": "tech_rate", "label": "科技/月", "color": Color(0.6, 0.8, 1.0), "is_float": true},
	{"key": "culture_rate", "label": "文化/月", "color": Color(1.0, 0.7, 0.9), "is_float": true},
	{"key": "happiness", "label": "幸福度", "color": Color(1.0, 0.8, 0.5), "is_float": false},
]

var _value_labels: Dictionary = {}  # stat key -> Label


func _ready() -> void:
	_build_ui()
	BuildingSystem.bonus_updated.connect(refresh)
	refresh()


func _build_ui() -> void:
	# 面板样式（与 InfoPanel 的 StyleBox_info 保持一致）
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.03, 0.06, 0.14, 0.9)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.25, 0.5, 0.85, 0.4)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.3)
	panel_style.shadow_size = 8
	panel_style.shadow_offset = Vector2(0, 3)
	add_theme_stylebox_override("panel", panel_style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.add_theme_constant_override("margin_left", 14)
	vbox.add_theme_constant_override("margin_top", 10)
	vbox.add_theme_constant_override("margin_right", 14)
	vbox.add_theme_constant_override("margin_bottom", 10)
	add_child(vbox)

	var title: Label = Label.new()
	title.text = "建筑产出总览"
	title.add_theme_color_override("font_color", Color(0.42, 0.72, 1.0, 0.95))
	title.add_theme_font_override("font", FONT_BOLD)
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 22)
	vbox.add_child(hbox)

	for def: Dictionary in STAT_DEFS:
		_add_stat(hbox, def)


func _add_stat(parent: Control, def: Dictionary) -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var value: Label = Label.new()
	value.add_theme_color_override("font_color", def["color"])
	value.add_theme_font_override("font", FONT_BOLD)
	value.add_theme_font_size_override("font_size", 18)
	value.text = _format(0.0, def["is_float"])
	var name_label: Label = Label.new()
	name_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95, 0.8))
	name_label.add_theme_font_override("font", FONT_SERIF)
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.text = def["label"]
	col.add_child(value)
	col.add_child(name_label)
	parent.add_child(col)
	_value_labels[def["key"]] = value


func refresh() -> void:
	# 与 BuildingSystem._recalculate_bonuses 同口径：累加所有 placed 的 bonuses × 等级
	var totals: Dictionary = {}
	for def: Dictionary in STAT_DEFS:
		totals[def["key"]] = 0.0
	for key: String in BuildingSystem.placed:
		var p: Dictionary = BuildingSystem.placed[key]
		var level: int = int(p["level"])
		var item: Dictionary = BuildingSystem.get_item(p["item_id"])
		var bonuses: Dictionary = item.get("bonuses", {})
		for def: Dictionary in STAT_DEFS:
			var stat_key: String = def["key"]
			totals[stat_key] += float(bonuses.get(stat_key, 0.0)) * float(level)
	for def: Dictionary in STAT_DEFS:
		var stat_key: String = def["key"]
		var label: Label = _value_labels[stat_key]
		var new_text: String = _format(float(totals[stat_key]), def["is_float"])
		if label.text != new_text:
			label.text = new_text
			UiAnim.value_flash(label)  # 数值变化闪烁提示


func _format(value: float, is_float: bool) -> String:
	if is_float:
		return "+%.1f" % value
	return "+%d" % int(value)
