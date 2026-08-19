class_name SaveList
extends VBoxContainer

## 存档列表组件：显示本地存档（角色名/时间/金币摘要），提供进入（加载）与删除按钮。
## 数据来自 SaveManager.list_saves()；删除前弹确认框。
## 用于登录首页（加载后进入游戏）与调试台（加载后替换当前状态）

signal save_loaded(file_name: String)
signal save_deleted(file_name: String)

const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")
const FONT_SERIF: Font = preload("res://assets/fonts/SourceHanSerifCN-Regular.otf")

var _rows_box: VBoxContainer


func _ready() -> void:
	var title := Label.new()
	title.text = "已有存档"
	title.add_theme_font_override("font", FONT_BOLD)
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.5, 0.8, 1, 0.9))
	add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 120)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows_box)
	refresh()


func refresh() -> void:
	for child: Node in _rows_box.get_children():
		child.queue_free()
	var saves: Array[Dictionary] = SaveManager.list_saves()
	if saves.is_empty():
		var empty := Label.new()
		empty.text = "暂无存档（可在游戏内输入礼包码 tiaoshitai 打开调试台保存）"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_override("font", FONT_SERIF)
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(0.55, 0.65, 0.8, 0.8))
		_rows_box.add_child(empty)
		return
	for s: Dictionary in saves:
		_rows_box.add_child(_make_row(s))


func _make_row(s: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = s.get("player_name", "未知角色")
	name_label.add_theme_font_override("font", FONT_BOLD)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 1))
	info.add_child(name_label)
	var detail := Label.new()
	detail.text = "第%d年%d月 · 金币 %d" % [s.get("year", 1), s.get("month", 1), s.get("gold", 0)]
	detail.add_theme_font_override("font", FONT_SERIF)
	detail.add_theme_font_size_override("font_size", 11)
	detail.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85, 0.85))
	info.add_child(detail)
	row.add_child(info)
	var load_btn := Button.new()
	load_btn.text = "进入"
	load_btn.custom_minimum_size = Vector2(56, 40)
	load_btn.pressed.connect(save_loaded.emit.bind(s["file_name"]))
	row.add_child(load_btn)
	var del_btn := Button.new()
	del_btn.text = "删除"
	del_btn.custom_minimum_size = Vector2(56, 40)
	del_btn.pressed.connect(_confirm_delete.bind(s))
	row.add_child(del_btn)
	return row


func _confirm_delete(s: Dictionary) -> void:
	# 删除前确认，防止误删；对话框用完即释放
	var dialog := ConfirmationDialog.new()
	dialog.title = "删除存档"
	dialog.dialog_text = "确定删除角色「%s」的存档吗？此操作不可恢复。" % s.get("player_name", "未知角色")
	dialog.ok_button_text = "删除"
	dialog.cancel_button_text = "取消"
	dialog.confirmed.connect(func() -> void:
		SaveManager.delete_save(s["file_name"])
		save_deleted.emit(s["file_name"])
		refresh())
	dialog.close_requested.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
