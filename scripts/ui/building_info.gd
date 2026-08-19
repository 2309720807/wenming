class_name BuildingInfo
extends RefCounted

## 地图信息文案：悬停/点击时显示的建筑/障碍/施工状态描述。
## 与 explore_map 交互逻辑分离，避免单文件超行数。
## 设计依据：docs/design/game_design.md 3.7

const HINT_BASE: String = "选择左侧建筑后，点击网格放置；点击障碍可花费金币清除"


static func obstacle_desc(obs: Dictionary) -> String:
	return "清除需 %d 金币\n点击障碍即可清除" % int(obs["clear_cost"])


static func construction_desc(item: Dictionary, placed: Dictionary) -> String:
	var progress: float = (1.0 - float(placed["remaining"]) / float(placed["total"])) * 100.0
	match placed["op"]:
		"build":
			return "建造中（%.0f%%）…点击可取消建造" % progress
		"upgrade":
			return "升级中（%.0f%%）…" % progress
		"demolish":
			return "拆除中（%.0f%%）…" % progress
	return ""


static func completed_desc(item: Dictionary, placed: Dictionary) -> String:
	return "%s\nLv.%d · 点击可升级或拆除" % [item.get("bonus_desc", ""), int(placed["level"])]
