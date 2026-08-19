class_name DebugAssetsView
extends VBoxContainer

## 调试台-资产数据浏览：实时列出 data/*.json 加载的游戏资产。
## 从 BuildingSystem / GiftCodeManager 数据源读取，新增资产条目自动出现
## （禁止硬编码列表，见 AGENTS.md 3.2）

const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")
const FONT_SERIF: Font = preload("res://assets/fonts/SourceHanSerifCN-Regular.otf")

var _text: RichTextLabel


func _ready() -> void:
	var title := Label.new()
	title.text = "游戏资产数据"
	title.add_theme_font_override("font", FONT_BOLD)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.5, 0.8, 1, 0.9))
	add_child(title)

	var refresh_btn := Button.new()
	refresh_btn.text = "刷新资产列表"
	refresh_btn.custom_minimum_size = Vector2(0, 28)
	refresh_btn.pressed.connect(refresh)
	add_child(refresh_btn)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.custom_minimum_size = Vector2(0, 170)
	_text.add_theme_font_override("normal_font", FONT_SERIF)
	_text.add_theme_font_size_override("normal_font_size", 12)
	add_child(_text)

	refresh()


func refresh() -> void:
	var lines: Array[String] = []
	lines.append("[color=#88ccff]-- 建筑 --[/color]")
	for id: String in BuildingSystem.buildings_data:
		var b: Dictionary = BuildingSystem.buildings_data[id]
		lines.append("%s [%s] 费用%d 占地%dx%d %s" % [
			b.get("name", "?"), id, int(b.get("cost", 0)),
			int(b.get("width", 1)), int(b.get("height", 1)), _bonus_text(b),
		])
	lines.append("[color=#88ccff]-- 装饰 --[/color]")
	for id: String in BuildingSystem.decorations_data:
		var d: Dictionary = BuildingSystem.decorations_data[id]
		lines.append("%s [%s] 费用%d %s" % [d.get("name", "?"), id, int(d.get("cost", 0)), _bonus_text(d)])
	lines.append("[color=#88ccff]-- 障碍物 --[/color]")
	for id: String in BuildingSystem.obstacles_data:
		var o: Dictionary = BuildingSystem.obstacles_data[id]
		lines.append("%s [%s] 清除费%d" % [o.get("name", "?"), id, int(o.get("clear_cost", 0))])
	lines.append("[color=#88ccff]-- 礼包码 --[/color]")
	for code: String in GiftCodeManager._codes:
		var g: Dictionary = GiftCodeManager._codes[code]
		lines.append("%s → 金币+%d（%s）" % [code, int(g.get("gold", 0)), g.get("desc", "")])
	_text.text = "\n".join(lines)


func _bonus_text(item: Dictionary) -> String:
	var parts: Array[String] = []
	for key: String in item.get("bonuses", {}):
		parts.append("%s+%s" % [key, str(item["bonuses"][key])])
	return "加成: " + " ".join(parts) if not parts.is_empty() else "无加成"
