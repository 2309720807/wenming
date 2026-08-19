extends Control

## 登录界面：输入玩家昵称后进入游戏。
## 设计依据：docs/design/game_design.md（正式化阶段：主菜单/登录）。

@onready var name_input: LineEdit = %NameInput
@onready var start_button: Button = %StartButton
@onready var error_label: Label = %ErrorLabel
@onready var panel: PanelContainer = $CenterContainer/Panel

var player_name: String = ""


func _ready() -> void:
	WindowManager.setup_scale_root(self)
	start_button.pressed.connect(_on_start_pressed)
	name_input.text_submitted.connect(_on_start_pressed)
	error_label.visible = false
	name_input.grab_focus()
	# 界面美化：面板入场 + 按钮动效（UiAnim，纯视觉）
	UiAnim.panel_enter(panel)
	UiAnim.attach_button(start_button)


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
	player_name = name_value
	GameState.player_name = player_name  # 存入数据层，供主界面等模块使用
	error_label.visible = false
	print("登录成功，玩家：", player_name)
	get_tree().change_scene_to_file("res://scenes/ui/main_ui.tscn")