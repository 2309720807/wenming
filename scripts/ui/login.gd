extends Control

## 登录界面：输入玩家昵称后进入游戏。
## 设计依据：docs/design/game_design.md（正式化阶段：主菜单/登录）。

@onready var name_input: LineEdit = %NameInput
@onready var start_button: Button = %StartButton
@onready var error_label: Label = %ErrorLabel
@onready var panel: PanelContainer = $CenterContainer/Panel
@onready var panel_vbox: VBoxContainer = $CenterContainer/Panel/VBox

var player_name: String = ""
var _pending_name: String = ""  # 同名覆盖确认中的角色名


func _ready() -> void:
	WindowManager.setup_scale_root(self)
	start_button.pressed.connect(_on_start_pressed)
	name_input.text_submitted.connect(_on_start_pressed)
	error_label.visible = false
	name_input.grab_focus()
	# 界面美化：面板入场 + 按钮动效（UiAnim，纯视觉）
	UiAnim.panel_enter(panel)
	UiAnim.attach_button(start_button)
	# 离线挂机收益提示（SaveManager 启动时已结算）
	var offline: Dictionary = SaveManager.last_offline_gains
	if offline.get("seconds", 0.0) > 0.0:
		var hours: float = float(offline["seconds"]) / 3600.0
		var offline_label := Label.new()
		offline_label.text = "⏳ 离线挂机 %.1f 小时：金币 +%d" % [hours, int(offline.get("gold", 0))]
		offline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		offline_label.add_theme_font_override("font", preload("res://assets/fonts/SourceHanSansCN-Bold.ttf"))
		offline_label.add_theme_font_size_override("font_size", 13)
		offline_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
		panel_vbox.add_child(offline_label)
	# 开发者本地存档列表（见 SaveManager / AGENTS.md 3.2）
	var divider := HSeparator.new()
	divider.add_theme_color_override("separator", Color(0.35, 0.7, 1, 0.25))
	panel_vbox.add_child(divider)
	var save_list := SaveList.new()
	save_list.name = "SaveList"
	save_list.save_loaded.connect(_on_save_loaded)
	save_list.save_deleted.connect(func(_f: String) -> void: print("存档已删除"))
	panel_vbox.add_child(save_list)


func _on_save_loaded(file_name: String) -> void:
	# 加载本地存档：恢复 GameState 与建造状态后直接进入主界面
	var result: Dictionary = SaveManager.load_game(file_name)
	print(result["message"])
	get_tree().change_scene_to_file("res://scenes/ui/main_ui.tscn")


func _show_error(message: String) -> void:
	## 错误提示淡入显示，避免突兀闪烁。
	error_label.text = message
	error_label.visible = true
	error_label.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(error_label, "modulate:a", 1.0, 0.2)


func _on_start_pressed(_text: String = "") -> void:
	var name_value := name_input.text.strip_edges()
	if name_value.is_empty():
		_show_error("请输入玩家昵称")
		return
	# 同名角色防护：已有同名存档时先确认，避免误覆盖原角色进度
	for s: Dictionary in SaveManager.list_saves():
		if s.get("player_name", "") == name_value:
			_pending_name = name_value
			_show_overwrite_confirm(name_value)
			return
	_start_new_game(name_value)


func _show_overwrite_confirm(role: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "角色已存在"
	dialog.dialog_text = "角色「%s」已有存档，继续将覆盖其存档。确定新建/覆盖吗？" % role
	dialog.ok_button_text = "覆盖"
	dialog.cancel_button_text = "取消"
	dialog.confirmed.connect(func() -> void: _start_new_game(_pending_name))
	dialog.close_requested.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _start_new_game(name_value: String) -> void:
	player_name = name_value
	# 新建游戏 = 全新开局：重置数据/建造/时间状态，避免继承自动存档（修复：不同存档进入后内容相同）
	GameState.reset_state()
	BuildingSystem.reset_state()
	MilitarySystem.reset_state()  # 军事基地/库存独立（修复：各角色串号）
	TimeManager.reset_time()
	GameState.player_name = player_name  # 存入数据层，供主界面等模块使用
	error_label.visible = false
	print("登录成功，玩家：", player_name)
	get_tree().change_scene_to_file("res://scenes/ui/main_ui.tscn")