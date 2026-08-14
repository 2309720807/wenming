extends Control

## 登录界面：输入玩家昵称后进入游戏。
## 设计依据：docs/design/game_design.md（正式化阶段：主菜单/登录）。

@onready var name_input: LineEdit = %NameInput
@onready var start_button: Button = %StartButton
@onready var error_label: Label = %ErrorLabel

var player_name: String = ""


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	name_input.text_submitted.connect(_on_start_pressed)
	error_label.visible = false
	name_input.grab_focus()


func _on_start_pressed(_text: String = "") -> void:
	var name_value := name_input.text.strip_edges()
	if name_value.is_empty():
		error_label.text = "请输入玩家昵称"
		error_label.visible = true
		return
	player_name = name_value
	error_label.visible = false
	print("登录成功，玩家：", player_name)
	# TODO(正式化): 后续跳转到主菜单/基地场景，并写入存档。