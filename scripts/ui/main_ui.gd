extends Control

## 养成主界面：六大模块入口 + 顶部信息栏 + 底部操作栏
## 设计依据：docs/design/game_design.md

# === 顶部信息栏引用 ===
@onready var turn_label: Label = %TurnLabel
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
@onready var btn_end_turn: Button = %BtnEndTurn

# === 中央区域 ===
@onready var center_container: CenterContainer = %CenterContainer
@onready var placeholder_label: Label = %PlaceholderLabel

# === 消息日志 ===
@onready var message_log: RichTextLabel = %MessageLog

# === 当前选中的模块 ===
var current_module: String = ""

# === 模拟数据 ===
var game_data: Dictionary = {
	"turn": 1,
	"gold": 100,
	"population": 10,
	"pop_max": 50,
	"happiness": 75,
	"tech_progress": 0.0,
	"culture_progress": 0.0,
}


func _ready() -> void:
	_connect_signals()
	_update_top_bar()
	_add_message("欢迎来到文明模拟器！你的文明刚刚起步。")


func _connect_signals() -> void:
	btn_populace.pressed.connect(_on_module_pressed.bind("populace"))
	btn_tech.pressed.connect(_on_module_pressed.bind("tech"))
	btn_economy.pressed.connect(_on_module_pressed.bind("economy"))
	btn_military.pressed.connect(_on_module_pressed.bind("military"))
	btn_culture.pressed.connect(_on_module_pressed.bind("culture"))
	btn_explore.pressed.connect(_on_module_pressed.bind("explore"))
	btn_end_turn.pressed.connect(_on_end_turn)


func _update_top_bar() -> void:
	turn_label.text = "回合 %d" % game_data.turn
	gold_label.text = "金币 %d" % game_data.gold
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


func _on_end_turn() -> void:
	game_data.turn += 1
	# 模拟资源增长
	game_data.gold += 10
	game_data.population = mini(game_data.population + 1, game_data.pop_max)
	game_data.happiness = clampi(game_data.happiness + randi_range(-2, 3), 0, 100)
	game_data.tech_progress = minf(game_data.tech_progress + 0.05, 1.0)
	game_data.culture_progress = minf(game_data.culture_progress + 0.03, 1.0)
	_update_top_bar()
	_add_message("回合 %d 结束。" % game_data.turn)


func _add_message(text: String) -> void:
	message_log.append_text("[color=#88aacc]%s[/color]\n" % text)
