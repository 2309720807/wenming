extends VBoxContainer
class_name BuildingMenu

## 左侧建筑菜单栏：分类展示建筑与装饰卡片，上下滚动选择
## 设计依据：docs/design/game_design.md 3.7

signal item_selected(item: Dictionary)

const FONT_HEAVY: Font = preload("res://assets/fonts/SourceHanSansCN-Heavy.ttf")
const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")
const FONT_SERIF: Font = preload("res://assets/fonts/SourceHanSerifCN-Regular.otf")

var selected_id: String = ""
var _cards: Dictionary = {}  # item_id -> PanelContainer（用于选中态样式切换）


func _ready() -> void:
	_build_section("建筑", BuildingSystem.buildings_data)
	_build_section("装饰", BuildingSystem.decorations_data)


func _build_section(title: String, items: Dictionary) -> void:
	var section_title := Label.new()
	section_title.text = "— %s —" % title
	section_title.add_theme_font_override("font", FONT_HEAVY)
	section_title.add_theme_font_size_override("font_size", 15)
	section_title.add_theme_color_override("font_color", Color(0.5, 0.78, 1, 0.9))
	add_child(section_title)
	for id: String in items:
		_add_card(items[id])


func _add_card(item: Dictionary) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 66)
	card.add_theme_stylebox_override("panel", _make_card_style(false))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "%s · %d 金币" % [item["name"], int(item["cost"])]
	title.add_theme_font_override("font", FONT_BOLD)
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1, 0.88, 0.5, 1))
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "占地 %dx%d · %s" % [int(item["width"]), int(item["height"]), item["bonus_desc"]]
	desc.add_theme_font_override("font", FONT_SERIF)
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.72, 0.8, 0.92, 0.9))
	vbox.add_child(desc)

	var click := Button.new()
	click.text = ""
	click.set_anchors_preset(Control.PRESET_FULL_RECT)
	click.flat = true
	click.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	# 悬停高亮：半透明白色底（纯视觉）
	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = Color(0.45, 0.7, 1, 0.14)
	hover_sb.set_corner_radius_all(8)
	click.add_theme_stylebox_override("hover", hover_sb)
	click.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	click.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	click.pressed.connect(_on_card_pressed.bind(item, card))
	card.add_child(click)

	_cards[item["id"]] = card
	add_child(card)


func _make_card_style(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.18, 0.34, 0.95) if selected else Color(0.05, 0.09, 0.18, 0.9)
	sb.border_color = Color(1, 0.85, 0.35, 0.9) if selected else Color(0.25, 0.5, 0.85, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 2)
	return sb


func _on_card_pressed(item: Dictionary, card: PanelContainer) -> void:
	# 再次点击已选中的建筑 = 取消选择
	if selected_id == item["id"]:
		selected_id = ""
		for id: String in _cards:
			_cards[id].add_theme_stylebox_override("panel", _make_card_style(false))
		item_selected.emit({})
		return
	selected_id = item["id"]
	for id: String in _cards:
		var selected: bool = (id == selected_id)
		_cards[id].add_theme_stylebox_override("panel", _make_card_style(selected))
	item_selected.emit(item)