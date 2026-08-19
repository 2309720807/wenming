class_name BuildingBalance
extends RefCounted

## 建造数值平衡：升级/拆除费用计算、建筑加成汇总。
## 常量集中在模块内，避免散落魔法数字；加成与费用口径供 UI 与系统共用。
## 设计依据：docs/design/game_design.md 3.7

const MAX_LEVEL: int = 5
const UPGRADE_COST_RATIO: float = 0.75  # 升级费用 = 基础费用 × 比例 × 当前等级
const UPGRADE_TIME_RATIO: float = 0.6   # 升级时间 = 建造时间 × 比例 × 当前等级
const DEMOLISH_REFUND_RATIO: float = 0.6  # 拆除返还 = 总投入 × 比例
const DEMOLISH_TIME_RATIO: float = 0.6    # 拆除时间 = 建造时间 × 比例


static func get_upgrade_cost(item: Dictionary, level: int) -> float:
	# 升级费用随等级递增：基础费用 × 0.75 × 当前等级
	return float(item.get("cost", 0.0)) * UPGRADE_COST_RATIO * float(level)


static func get_demolish_refund(item: Dictionary, level: int) -> float:
	# 返还 =（建造费用 + 全部升级费用）× 60%
	var total: float = float(item.get("cost", 0.0))
	for lv: int in range(1, level):
		total += float(item.get("cost", 0.0)) * UPGRADE_COST_RATIO * float(lv)
	return total * DEMOLISH_REFUND_RATIO


static func collect_bonuses(placed: Dictionary, item_lookup: Callable) -> Dictionary:
	# 统计所有已完工建筑/装饰的加成（加成 = 基础 × 等级）
	var totals: Dictionary = {
		"gold_rate": 0.0,
		"pop_max": 0,
		"pop_growth_rate": 0.0,
		"tech_rate": 0.0,
		"culture_rate": 0.0,
		"happiness": 0,
	}
	for key: String in placed:
		var p: Dictionary = placed[key]
		var level: int = int(p.get("level", 1))
		var item: Dictionary = item_lookup.call(p.get("item_id", ""))
		var bonuses: Dictionary = item.get("bonuses", {})
		totals["gold_rate"] += float(bonuses.get("gold_rate", 0.0)) * level
		totals["pop_max"] += int(bonuses.get("pop_max", 0)) * level
		totals["pop_growth_rate"] += float(bonuses.get("pop_growth_rate", 0.0)) * level
		totals["tech_rate"] += float(bonuses.get("tech_rate", 0.0)) * level
		totals["culture_rate"] += float(bonuses.get("culture_rate", 0.0)) * level
		totals["happiness"] += int(bonuses.get("happiness", 0)) * level
	return totals
