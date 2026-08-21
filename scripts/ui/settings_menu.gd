extends PanelContainer
class_name SettingsMenu

## 设置面板：游戏分辨率调整、礼包码兑换、退出游戏
## 设计依据：docs/design/game_design.md（设置系统）
## UI 层职责：引用节点、绑定信号、更新显示；逻辑由 WindowManager / GiftCodeManager 处理

signal redeem_succeeded(message: String)
signal debug_requested  # 开发者调试台开启请求（礼包码 tiaoshitai，见 AGENTS.md 3.2）
signal role_switched(message: String)  # 切换角色完成（主界面消息日志提示）

@onready var resolution_option: OptionButton = %ResolutionOption
@onready var gift_code_input: LineEdit = %GiftCodeInput
@onready var btn_redeem: Button = %BtnRedeem
@onready var gift_result_label: Label = %GiftResultLabel
@onready var btn_exit: Button = %BtnExit
@onready var btn_close: Button = %BtnClose
@onready var confirm_dialog: ConfirmationDialog = %ConfirmDialog
@onready var quality_option: OptionButton = %QualityOption
@onready var btn_save: Button = %BtnSave
@onready var btn_switch_role: Button = %BtnSwitchRole
@onready var save_result_label: Label = %SaveResultLabel
@onready var role_list_box: VBoxContainer = %RoleListBox

var _save_list: SaveList


func _ready() -> void:
	_fill_resolutions()
	resolution_option.item_selected.connect(_on_resolution_selected)
	gift_code_input.text_submitted.connect(_on_redeem_pressed)
	gift_code_input.text_changed.connect(func(_t: String) -> void: gift_result_label.text = "")
	btn_redeem.pressed.connect(_on_redeem_pressed)
	btn_exit.pressed.connect(_on_exit_pressed)
	btn_close.pressed.connect(close)
	confirm_dialog.confirmed.connect(_on_confirm_exit)
	btn_save.pressed.connect(_on_save_pressed)
	btn_switch_role.pressed.connect(_on_switch_role_pressed)
	# 画质档位（超采样，自动记忆，见 WindowManager.set_quality_level）
	quality_option.item_selected.connect(_on_quality_selected)
	# 切换角色列表（复用 SaveList 组件：进入/删除/刷新）
	_save_list = SaveList.new()
	_save_list.name = "SaveList"
	_save_list.save_loaded.connect(_on_role_loaded)
	_save_list.save_deleted.connect(func(_f: String) -> void: save_result_label.text = "存档已删除")
	role_list_box.add_child(_save_list)


func open() -> void:
	_fill_resolutions()
	gift_result_label.text = ""
	gift_code_input.clear()
	# 画质档位：同步当前值（QUALITY_LEVELS 与下拉顺序一致）
	for i: int in range(WindowManager.QUALITY_LEVELS.size()):
		if WindowManager.QUALITY_LEVELS[i] == WindowManager.quality_level:
			quality_option.select(i)
			break
	show()
	UiAnim.panel_enter(self)  # 面板入场动画（纯视觉）


func _on_quality_selected(index: int) -> void:
	## 画质档位（超采样面积倍数）：实时生效并记忆（user://settings.cfg）
	if index >= 0 and index < WindowManager.QUALITY_LEVELS.size():
		WindowManager.set_quality_level(WindowManager.QUALITY_LEVELS[index])


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


func _on_redeem_pressed(_text: String = "") -> void:
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


# === 存档管理（保存进度 / 切换角色）===

func _on_save_pressed() -> void:
	## 保存当前进度到当前角色（角色名 = 登录昵称，各角色独立存档）
	var role: String = GameState.player_name.strip_edges()
	if role.is_empty():
		save_result_label.text = "当前没有角色，无法保存"
		save_result_label.modulate = Color(1, 0.6, 0.5, 1)
		return
	var result: Dictionary = SaveManager.save_game(role)
	save_result_label.text = result["message"]
	save_result_label.modulate = Color(0.55, 1, 0.6, 1) if result["ok"] else Color(1, 0.6, 0.5, 1)


func _on_switch_role_pressed() -> void:
	## 展开/收起角色列表；展开时刷新存档条目
	role_list_box.visible = not role_list_box.visible
	if role_list_box.visible:
		save_result_label.text = ""
		_save_list.refresh()


func _on_role_loaded(file_name: String) -> void:
	## 切换角色：加载目标角色存档，数据层信号自动刷新主界面，随后关闭设置面板
	var result: Dictionary = SaveManager.load_game(file_name)
	save_result_label.text = result["message"]
	save_result_label.modulate = Color(0.55, 1, 0.6, 1) if result["ok"] else Color(1, 0.6, 0.5, 1)
	if result["ok"]:
		role_switched.emit(result["message"])
		close()
