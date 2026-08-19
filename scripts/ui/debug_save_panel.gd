class_name DebugSavePanel
extends VBoxContainer

## 调试台-存档管理：输入角色名保存当前进度；列出本地存档可加载/删除。
## 规则依据：AGENTS.md 3.2（开发者调试工具）；数据由 SaveManager 管理（user://saves/）

const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")
const FONT_SERIF: Font = preload("res://assets/fonts/SourceHanSerifCN-Regular.otf")

var _name_input: LineEdit
var _result_label: Label
var _save_list: SaveList


func _ready() -> void:
	var title := Label.new()
	title.text = "存档管理（本地 user://saves/）"
	title.add_theme_font_override("font", FONT_BOLD)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.5, 0.8, 1, 0.9))
	add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "存档角色名（留空用当前玩家名）"
	_name_input.text = GameState.player_name
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name_input)
	var save_btn := Button.new()
	save_btn.text = "保存当前进度"
	save_btn.pressed.connect(_on_save_pressed)
	row.add_child(save_btn)
	add_child(row)

	_result_label = Label.new()
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.add_theme_font_override("font", FONT_SERIF)
	_result_label.add_theme_font_size_override("font_size", 12)
	add_child(_result_label)

	_save_list = SaveList.new()
	_save_list.save_loaded.connect(_on_loaded)
	_save_list.save_deleted.connect(func(_f: String) -> void: _result_label.text = "存档已删除")
	add_child(_save_list)


func _on_save_pressed() -> void:
	var role: String = _name_input.text.strip_edges()
	if role.is_empty():
		role = GameState.player_name
	var result: Dictionary = SaveManager.save_game(role)
	_show_result(result)
	_save_list.refresh()


func _on_loaded(file_name: String) -> void:
	_show_result(SaveManager.load_game(file_name))


func _show_result(result: Dictionary) -> void:
	_result_label.text = result.get("message", "")
	_result_label.modulate = Color(0.55, 1, 0.6, 1) if result.get("ok", false) else Color(1, 0.6, 0.5, 1)
