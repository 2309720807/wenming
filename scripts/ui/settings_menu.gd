extends PanelContainer
class_name SettingsMenu

## 设置面板：游戏分辨率调整、礼包码兑换、退出游戏
## 设计依据：docs/design/game_design.md（设置系统）
## UI 层职责：引用节点、绑定信号、更新显示；逻辑由 WindowManager / GiftCodeManager 处理

signal redeem_succeeded(message: String)
signal debug_requested  # 开发者调试台开启请求（礼包码 tiaoshitai，见 AGENTS.md 3.2）

@onready var resolution_option: OptionButton = %ResolutionOption
@onready var gift_code_input: LineEdit = %GiftCodeInput
@onready var btn_redeem: Button = %BtnRedeem
@onready var gift_result_label: Label = %GiftResultLabel
@onready var btn_exit: Button = %BtnExit
@onready var btn_close: Button = %BtnClose
@onready var confirm_dialog: ConfirmationDialog = %ConfirmDialog


func _ready() -> void:
	_fill_resolutions()
	resolution_option.item_selected.connect(_on_resolution_selected)
	gift_code_input.text_submitted.connect(_on_redeem_pressed)
	gift_code_input.text_changed.connect(func(_t: String) -> void: gift_result_label.text = "")
	btn_redeem.pressed.connect(_on_redeem_pressed)
	btn_exit.pressed.connect(_on_exit_pressed)
	btn_close.pressed.connect(close)
	confirm_dialog.confirmed.connect(_on_confirm_exit)


func open() -> void:
	_fill_resolutions()
	gift_result_label.text = ""
	gift_code_input.clear()
	show()
	UiAnim.panel_enter(self)  # 面板入场动画（纯视觉）


func close() -> void:
	hide()


func _fill_resolutions() -> void:
	resolution_option.clear()
	var current: Vector2i = WindowManager.current_resolution()
	var resolutions: Array[Vector2i] = WindowManager.get_resolutions()
	for i: int in range(resolutions.size()):
		var res: Vector2i = resolutions[i]
		resolution_option.add_item("%d × %d" % [res.x, res.y])
		if res == current:
			resolution_option.select(i)


func _on_resolution_selected(index: int) -> void:
	var resolutions: Array[Vector2i] = WindowManager.get_resolutions()
	if index >= 0 and index < resolutions.size():
		WindowManager.set_resolution(resolutions[index])


func _on_redeem_pressed() -> void:
	var result: Dictionary = GiftCodeManager.redeem(gift_code_input.text)
	gift_code_input.clear()
	gift_result_label.text = result["message"]
	gift_result_label.modulate = Color(0.55, 1, 0.6, 1) if result["ok"] else Color(1, 0.6, 0.5, 1)
	if result.get("debug", false):
		# 开发者调试码：交由主界面打开调试台，不记入普通兑换消息
		debug_requested.emit()
	elif result["ok"]:
		redeem_succeeded.emit(result["message"])


func _on_exit_pressed() -> void:
	# 子 Window 不受场景根缩放影响，按当前缩放系数等比放大内容，保持与 UI 一致
	confirm_dialog.content_scale_size = Vector2i(1280, 720)
	confirm_dialog.content_scale_factor = WindowManager.current_scale_factor()
	confirm_dialog.popup_centered()


func _on_confirm_exit() -> void:
	get_tree().quit()
