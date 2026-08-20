extends Control

## 养成主界面：六大模块入口 + 底部操作栏 + 设置
## 设计依据：docs/design/game_design.md
## 实时制：所有系统资源随时间自然变化，无回合概念
## 顶部信息栏为独立组件（top_bar.gd 挂在 TopBar 节点）；消息日志见 message_log.gd

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

# === 设置 ===
@onready var btn_settings: Button = %BtnSettings
@onready var settings_menu: SettingsMenu = %SettingsMenu

# === 开发者调试台（入口：礼包码 tiaoshitai，见 AGENTS.md 3.2）===
var debug_console: DebugConsole

# === 中央区域 ===
@onready var placeholder_label: Label = %PlaceholderLabel
@onready var explore_map: Control = %ExploreMap

# === 消息日志（独立组件：scripts/ui/message_log.gd）===
@onready var message_log: MessageLog = %MessageLog


func _ready() -> void:
	WindowManager.setup_scale_root(self)
	debug_console = DebugConsole.new()
	debug_console.name = "DebugConsole"
	add_child(debug_console)
	_connect_signals()
	var player_display: String = GameState.player_name
	if player_display.is_empty():
		player_display = "引导者"
	message_log.add_message("欢迎你，%s！你的文明刚刚起步。" % player_display)
	# 默认进入地图与探索界面（网格建设）
	_on_module_pressed("explore")
	# 界面美化：面板入场 + 按钮动效（UiAnim，纯视觉）
	UiAnim.panel_enter($TopBar)
	UiAnim.panel_enter($BottomBar, 0.06)
	UiAnim.panel_enter($MessagePanel, 0.12)
	for btn: Button in [
		btn_populace, btn_tech, btn_economy, btn_military, btn_culture, btn_explore,
		btn_pause, btn_speed1, btn_speed2, btn_speed3, btn_settings,
	]:
		UiAnim.attach_button(btn)


func _connect_signals() -> void:
	# 模块按钮
	btn_populace.pressed.connect(_on_module_pressed.bind("populace"))
	btn_tech.pressed.connect(_on_module_pressed.bind("tech"))
	btn_economy.pressed.connect(_on_module_pressed.bind("economy"))
	btn_military.pressed.connect(_on_module_pressed.bind("military"))
	btn_culture.pressed.connect(_on_module_pressed.bind("culture"))
	btn_explore.pressed.connect(_on_module_pressed.bind("explore"))

	# 时间控制按钮
	btn_pause.pressed.connect(_on_pause_pressed)
	btn_speed1.pressed.connect(_on_speed_pressed.bind(1.0))
	btn_speed2.pressed.connect(_on_speed_pressed.bind(2.0))
	btn_speed3.pressed.connect(_on_speed_pressed.bind(3.0))

	# 设置面板
	btn_settings.pressed.connect(_on_settings_pressed)
	settings_menu.redeem_succeeded.connect(message_log.add_message)
	settings_menu.debug_requested.connect(_on_debug_requested)
	settings_menu.role_switched.connect(_on_role_switched)

	# TimeManager 信号
	TimeManager.speed_changed.connect(_on_speed_changed)
	TimeManager.paused_changed.connect(_on_paused_changed)


func _on_speed_changed(new_speed: float) -> void:
	_update_speed_buttons(int(new_speed))


func _on_paused_changed(is_paused: bool) -> void:
	btn_pause.text = "▶" if is_paused else "⏸"
	if is_paused:
		message_log.add_message("游戏已暂停")
	else:
		message_log.add_message("游戏继续")


# === 模块导航 ===

func _on_module_pressed(module_name: String) -> void:
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
	}
	if module_name == "explore":
		# 地图与探索：显示网格建设界面
		explore_map.visible = true
		placeholder_label.visible = false
		return
	var name_str: String = names.get(module_name, module_name)
	placeholder_label.text = "[ %s ]\n\n模块建设中，敬请期待..." % name_str
	placeholder_label.visible = true
	explore_map.visible = false


# === 时间控制 ===

func _on_pause_pressed() -> void:
	TimeManager.toggle_pause()


func _on_speed_pressed(speed: float) -> void:
	TimeManager.set_speed(speed)


# === 设置 ===

func _on_settings_pressed() -> void:
	settings_menu.open()


func _on_debug_requested() -> void:
	settings_menu.close()
	debug_console.open()
	message_log.add_message("开发者调试台已开启")


func _on_role_switched(message: String) -> void:
	## 设置面板切换角色完成：数据层信号已刷新顶栏/地图，这里仅提示
	message_log.add_message(message)


func _update_speed_buttons(active_speed: int) -> void:
	btn_speed1.modulate = Color(1, 1, 1, 0.6)
	btn_speed2.modulate = Color(1, 1, 1, 0.6)
	btn_speed3.modulate = Color(1, 1, 1, 0.6)
	match active_speed:
		1: btn_speed1.modulate = Color(1, 1, 1, 1.0)
		2: btn_speed2.modulate = Color(1, 1, 1, 1.0)
		3: btn_speed3.modulate = Color(1, 1, 1, 1.0)
	message_log.add_message("时间速度：%dx" % active_speed)
