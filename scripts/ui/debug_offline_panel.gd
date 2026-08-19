class_name DebugOfflinePanel
extends VBoxContainer

## 调试台-离线挂机模拟：输入离线秒数立即结算收益，用于验证 OfflineGains 结算逻辑。
## 规则依据：AGENTS.md 3.2（新系统必须提供调试分组）

const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")
const FONT_SERIF: Font = preload("res://assets/fonts/SourceHanSerifCN-Regular.otf")

var _seconds_input: LineEdit
var _result_label: Label


func _ready() -> void:
	var title := Label.new()
	title.text = "离线挂机模拟（OfflineGains）"
	title.add_theme_font_override("font", FONT_BOLD)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.5, 0.8, 1, 0.9))
	add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_seconds_input = LineEdit.new()
	_seconds_input.placeholder_text = "离线秒数，如 86400 = 1 天"
	_seconds_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_seconds_input)
	var apply_btn := Button.new()
	apply_btn.text = "模拟离线"
	apply_btn.pressed.connect(_on_apply)
	row.add_child(apply_btn)
	add_child(row)

	_result_label = Label.new()
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.add_theme_font_override("font", FONT_SERIF)
	_result_label.add_theme_font_size_override("font_size", 12)
	add_child(_result_label)


func _on_apply() -> void:
	var secs: float = float(_seconds_input.text.strip_edges())
	if secs <= 0.0:
		_result_label.text = "请输入大于 0 的秒数"
		return
	var report: Dictionary = OfflineGains.apply_offline(secs)
	_result_label.text = "离线 %.1f 小时（%.1f 月）：金币 +%d" % [
		secs / 3600.0, report.get("months", 0.0), int(report.get("gold", 0)),
	]
