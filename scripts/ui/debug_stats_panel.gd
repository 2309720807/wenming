class_name DebugStatsPanel
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
