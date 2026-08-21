class_name ResourceBar
extends PanelContainer

## 全局资源栏组件：显示玩家名/时间/金币/人口/幸福度/科技/文化，数据层信号驱动刷新。
## 各游戏界面（主界面顶栏之外的新界面：军事/副本等）顶部复用，让玩家随时了解资源存量。
## 设计依据：docs/design/game_design.md 4-A（顶部信息栏）

const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")

var _name_label: Label
var _time_label: Label
var _gold_label: Label
var _pop_label: Label
var _hap_label: Label
var _tech_label: Label
var _culture_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(0, 44)
	add_theme_stylebox_override("panel", _make_style())
	_build()
	# 数据层信号 → 显示刷新（同 top_bar 逻辑）；建筑加成变化也触发整体刷新
	GameState.year_changed.connect(_update_all)
	GameState.month_changed.connect(_update_all)
	GameState.gold_changed.connect(_update_all)
	GameState.population_changed.connect(_update_all)
	GameState.happiness_changed.connect(_update_all)
	GameState.tech_changed.connect(_update_all)
	GameState.culture_changed.connect(_update_all)
	BuildingSystem.bonus_updated.connect(_update_all)
	_update_all()


func _build() -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	hbox.add_theme_constant_override("margin_left", 18)
	hbox.add_theme_constant_override("margin_right", 18)
	hbox.add_theme_constant_override("margin_top", 5)
	hbox.add_theme_constant_override("margin_bottom", 5)
	add_child(hbox)

	_name_label = _make_stat(hbox, "引导者", Color(0.4, 0.82, 1, 1), 15)
	_add_sep(hbox)
	_time_label = _make_stat(hbox, GameState.get_time_display(), Color(0.8, 0.9, 1, 1))
	_add_sep(hbox)
	_gold_label = _make_stat(hbox, GameState.get_gold_display(), Color(1, 0.85, 0.4, 1))
	_add_sep(hbox)
	_pop_label = _make_stat(hbox, GameState.get_population_display(), Color(0.5, 1, 0.7, 1))
	_add_sep(hbox)
	_hap_label = _make_stat(hbox, GameState.get_happiness_display(), Color(1, 0.75, 0.85, 1))
	_add_sep(hbox)
	_tech_label = _make_stat(hbox, GameState.get_tech_display(), Color(0.6, 0.8, 1, 1))
	_add_sep(hbox)
	_culture_label = _make_stat(hbox, GameState.get_culture_display(), Color(1, 0.7, 0.9, 1))


func _make_stat(parent: HBoxContainer, initial: String, color: Color, font_size: int = 14) -> Label:
	var label := Label.new()
	label.text = initial
	label.add_theme_font_override("font", FONT_BOLD)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _add_sep(parent: HBoxContainer) -> void:
	var sep := VSeparator.new()
	sep.modulate = Color(0.4, 0.7, 1, 0.4)
	parent.add_child(sep)


func _update_all() -> void:
	var player_display: String = GameState.player_name
	if player_display.is_empty():
		player_display = "引导者"
	_name_label.text = player_display
	_time_label.text = GameState.get_time_display()
	_gold_label.text = GameState.get_gold_display()
	_pop_label.text = GameState.get_population_display()
	_hap_label.text = GameState.get_happiness_display()
	_tech_label.text = GameState.get_tech_display()
	_culture_label.text = GameState.get_culture_display()


func _make_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.08, 0.18, 0.9)
	sb.border_width_bottom = 2
	sb.border_color = Color(0.35, 0.7, 1, 0.5)
	sb.shadow_color = Color(0.2, 0.5, 1.0, 0.3)
	sb.shadow_size = 10
	return sb
