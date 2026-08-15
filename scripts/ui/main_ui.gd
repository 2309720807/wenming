extends Control

## 养成主界面：六大模块入口 + 顶部信息栏 + 底部操作栏
## 设计依据：docs/design/game_design.md
## 实时制：所有系统资源随时间自然变化，无回合概念

# === 顶部信息栏引用 ===
@onready var time_label: Label = %TimeLabel
@onready var gold_label: Label = %GoldLabel
@onready var population_label: Label = %PopulationLabel
@onready var happiness_label: Label = %HappinessLabel
@onready var tech_label: Label = %TechLabel
@onready var culture_label: Label = %CultureLabel

# === 底部模块按钮引用 ===
@onready var btn_populace: Button = %BtnPopulace
@onready var btn_tech: Button = %BtnTech
@onready var btn_economy: Button = %BtnEconomy
@onready var btn_military: Button = %BtnMilitary
@onready var btn_culture: Button = %BtnCulture
@onready var btn_explore: Button = %BtnExplore

# === 时间控制按钮 ===
@onready var btn_pause: Button = %BtnPause
@onready var btn_speed1: Button = %BtnSpeed1
@onready var btn_speed2: Button = %BtnSpeed2
@onready var btn_speed3: Button = %BtnSpeed3

# === 中央区域 ===
@onready var center_container: CenterContainer = %CenterContainer
@onready var placeholder_label: Label = %PlaceholderLabel

# === 消息日志 ===
@onready var message_log: RichTextLabel = %MessageLog

# === 当前选中的模块 ===
var current_module: String = ""

# === 游戏时间系统 ===
var game_time: float = 0.0  # 游戏内时间（秒）
var time_speed: float = 1.0  # 时间倍率（1x, 2x, 3x）
var is_paused: bool = false

# 游戏内1秒 = 现实1秒（1x倍率下）
# 1分钟游戏时间 = 1秒现实时间
# 1年 = 12个月 = 60秒现实时间（1x倍率下）
const SECONDS_PER_MONTH: float = 5.0  # 现实5秒 = 游戏1个月

# === 模拟数据 ===
var game_data: Dictionary = {
	"year": 1,
	"month": 1,
	"gold": 100.0,
	"gold_rate": 5.0,  # 每月金币增长
	"population": 10,
	"pop_max": 50,
	"pop_growth_rate": 0.2,  # 每月人口增长率
	"happiness": 75,
	"food": 50.0,
	"food_rate": 2.0,  # 每月食物增长
	"wood": 30.0,
	"stone": 20.0,
	"metal": 10.0,
	"tech_progress": 0.0,
	"tech_rate": 0.02,  # 每月科技增长
	"culture_progress": 0.0,
	"culture_rate": 0.015,  # 每月文化增长
}


func _ready() -> void:
	_connect_signals()
	_update_all_labels()
	_add_message("欢迎来到文明模拟器！你的文明刚刚起步。")


func _connect_signals() -> void:
	btn_populace.pressed.connect(_on_module_pressed.bind("populace"))
	btn_tech.pressed.connect(_on_module_pressed.bind("tech"))
	btn_economy.pressed.connect(_on_module_pressed.bind("economy"))
	btn_military.pressed.connect(_on_module_pressed.bind("military"))
	btn_culture.pressed.connect(_on_module_pressed.bind("culture"))
	btn_explore.pressed.connect(_on_module_pressed.bind("explore"))
	btn_pause.pressed.connect(_on_pause_pressed)
	btn_speed1.pressed.connect(_on_speed_pressed.bind(1.0))
	btn_speed2.pressed.connect(_on_speed_pressed.bind(2.0))
	btn_speed3.pressed.connect(_on_speed_pressed.bind(3.0))


func _process(delta: float) -> void:
	if is_paused:
		return

	# 累加游戏时间
	game_time += delta * time_speed

	# 检查是否过了一个月
	var current_month: int = int(game_time / SECONDS_PER_MONTH) + 1
	var current_year: int = (current_month - 1) / 12 + 1
	current_month = ((current_month - 1) % 12) + 1

	if current_year != game_data.year or current_month != game_data.month:
		game_data.year = current_year
		game_data.month = current_month
		_process_monthly_update()
		_update_all_labels()


func _process_monthly_update() -> void:
	# 资源随时间自动增长
	game_data.gold += game_data.gold_rate
	game_data.food += game_data.food_rate
	game_data.wood += 1.0
	game_data.stone += 0.5
	game_data.metal += 0.2

	# 人口增长（受幸福度影响）
	var growth_modifier: float = game_data.happiness / 100.0
	game_data.population = mini(
		game_data.population + int(game_data.pop_growth_rate * growth_modifier),
		game_data.pop_max
	)

	# 科技和文化进度
	game_data.tech_progress = minf(game_data.tech_progress + game_data.tech_rate, 1.0)
	game_data.culture_progress = minf(game_data.culture_progress + game_data.culture_rate, 1.0)

	# 幸福度小幅波动
	game_data.happiness = clampi(
		game_data.happiness + randi_range(-1, 2), 0, 100
	)


func _update_all_labels() -> void:
	time_label.text = "第 %d 年 第 %d 月" % [game_data.year, game_data.month]
	gold_label.text = "金币 %d (+%.0f/月)" % [int(game_data.gold), game_data.gold_rate]
	population_label.text = "人口 %d/%d" % [game_data.population, game_data.pop_max]
	happiness_label.text = "幸福度 %d%%" % game_data.happiness
	tech_label.text = "科技 %.0f%%" % (game_data.tech_progress * 100)
	culture_label.text = "文化 %.0f%%" % (game_data.culture_progress * 100)


func _on_module_pressed(module_name: String) -> void:
	current_module = module_name
	_highlight_active_button(module_name)
	_show_module_placeholder(module_name)


func _highlight_active_button(module_name: String) -> void:
	var buttons: Array[Button] = [
		btn_populace, btn_tech, btn_economy,
		btn_military, btn_culture, btn_explore,
	]
	for btn: Button in buttons:
		btn.modulate = Color(1, 1, 1, 0.6)
	var active_map: Dictionary = {
		"populace": btn_populace,
		"tech": btn_tech,
		"economy": btn_economy,
		"military": btn_military,
		"culture": btn_culture,
		"explore": btn_explore,
	}
	if active_map.has(module_name):
		active_map[module_name].modulate = Color(1, 1, 1, 1.0)


func _show_module_placeholder(module_name: String) -> void:
	var names: Dictionary = {
		"populace": "人口与民生",
		"tech": "科技与研发",
		"economy": "经济与资源",
		"military": "军事与防御",
		"culture": "文化与外交",
		"explore": "地图与探索",
	}
	var name_str: String = names.get(module_name, module_name)
	placeholder_label.text = "[ %s ]\n\n模块建设中，敬请期待..." % name_str
	placeholder_label.visible = true


func _on_pause_pressed() -> void:
	is_paused = not is_paused
	btn_pause.text = "▶" if is_paused else "⏸"
	if is_paused:
		_add_message("游戏已暂停")
	else:
		_add_message("游戏继续")


func _on_speed_pressed(speed: float) -> void:
	time_speed = speed
	# 更新按钮高亮
	btn_speed1.modulate = Color(1, 1, 1, 0.6)
	btn_speed2.modulate = Color(1, 1, 1, 0.6)
	btn_speed3.modulate = Color(1, 1, 1, 0.6)
	match int(speed):
		1: btn_speed1.modulate = Color(1, 1, 1, 1.0)
		2: btn_speed2.modulate = Color(1, 1, 1, 1.0)
		3: btn_speed3.modulate = Color(1, 1, 1, 1.0)
	_add_message("时间速度：%dx" % int(speed))


func _add_message(text: String) -> void:
	message_log.append_text("[color=#88aacc]%s[/color]\n" % text)
