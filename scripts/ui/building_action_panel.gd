class_name BuildingActionPanel
extends RefCounted

## 建筑操作面板控制器：点击已完工建筑时显示等级/加成/升级费用/拆除返还。
## 由 explore_map 创建并注入节点引用，职责与地图交互逻辑分离。
## 设计依据：docs/design/game_design.md 3.7（升级与拆除）

var panel: PanelContainer
var title: Label
var desc: Label
var upgrade_btn: Button
var demolish_btn: Button
var close_btn: Button
var action_key: String = ""


func setup(panel_node: PanelContainer, title_node: Label, desc_node: Label,
		upgrade_node: Button, demolish_node: Button, close_node: Button) -> void:
	panel = panel_node
	title = title_node
	desc = desc_node
	upgrade_btn = upgrade_node
	demolish_btn = demolish_node
	close_btn = close_node


func open(key: String) -> void:
	var p: Dictionary = BuildingSystem.placed[key]
	var item: Dictionary = BuildingSystem.get_item(p["item_id"])
	action_key = key
	var level: int = int(p["level"])
	title.text = "%s  Lv.%d" % [item.get("name", "?"), level]
	desc.text = "%s\n\n升级费用：%d 金币\n拆除返还：%d 金币" % [
		item.get("bonus_desc", ""),
		int(BuildingSystem.get_upgrade_cost(p)),
		int(BuildingSystem.get_demolish_refund(p)),
	]
	if level >= BuildingBalance.MAX_LEVEL:
		upgrade_btn.text = "已达最高等级"
		upgrade_btn.disabled = true
	else:
		upgrade_btn.text = "升级至 Lv.%d（%d 金币）" % [
			level + 1, int(BuildingSystem.get_upgrade_cost(p)),
		]
		upgrade_btn.disabled = GameState.gold < BuildingSystem.get_upgrade_cost(p)
	demolish_btn.text = "拆除（返还 %d 金币）" % int(BuildingSystem.get_demolish_refund(p))
	panel.show()


func close() -> void:
	panel.hide()
	action_key = ""


func current_key() -> String:
	return action_key
