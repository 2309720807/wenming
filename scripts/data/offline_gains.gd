class_name OfflineGains
extends RefCounted

## 离线挂机收益结算：按关闭时长模拟游戏进度并计算所得。
## 无挂机时间上限：资源按时间批量数学计算，建筑施工按完成事件分段推进，
## 循环次数仅与施工事件数相关，与离线时长无关。
## 规则依据：AGENTS.md 3.2（开发者调试）；离线按 1x 倍速折算（SECONDS_PER_MONTH 秒 = 1 月）


## 结算离线收益，返回 {"seconds", "months", "gold"}
static func apply_offline(seconds: float) -> Dictionary:
	var report: Dictionary = {
		"seconds": seconds,
		"months": seconds / TimeManager.SECONDS_PER_MONTH,
		"gold": 0.0,
	}
	if seconds <= 0.0:
		return report
	var gold_before: float = GameState.gold
	var remaining: float = seconds
	while remaining > 0.001:
		var next_event: float = _next_construction_event()
		if next_event < 0.0 or next_event >= remaining:
			_apply_linear(remaining)
			_advance_construction(remaining)
			remaining = 0.0
		else:
			_apply_linear(next_event)
			_advance_construction(next_event)
			remaining -= next_event
	# 离线结算推进了年月，重新对齐 TimeManager 时间，防止 _process 把时间覆盖回去（调试台模拟同样受益）
	TimeManager.sync_to_save(GameState.year, GameState.month)
	report["gold"] = GameState.gold - gold_before
	return report


## 最近施工完成还需多少秒；无施工返回 -1
static func _next_construction_event() -> float:
	var earliest: float = -1.0
	for key: String in BuildingSystem.placed:
		var p: Dictionary = BuildingSystem.placed[key]
		if p["op"] != "":
			var t: float = float(p["remaining"])
			if earliest < 0.0 or t < earliest:
				earliest = t
	return earliest


## 按时长（秒）批量结算线性收益：资源/人口/科技/文化/年月
static func _apply_linear(seconds: float) -> void:
	var months: float = seconds / TimeManager.SECONDS_PER_MONTH
	GameState.add_gold(GameState.gold_rate * months)
	GameState.add_food(GameState.food_rate * months)
	GameState.add_wood(GameState.wood_rate * months)
	GameState.add_stone(GameState.stone_rate * months)
	GameState.add_metal(GameState.metal_rate * months)
	var growth: float = GameState.pop_growth_rate * (GameState.happiness / 100.0) * months
	GameState.accumulate_population_growth(growth)
	GameState.add_tech(GameState.tech_rate * months)
	GameState.add_culture(GameState.culture_rate * months)
	var total_months: int = int(months)
	if total_months > 0:
		var idx: int = (GameState.year - 1) * 12 + (GameState.month - 1) + total_months
		GameState.set_month(idx / 12 + 1, idx % 12 + 1)


## 施工推进：推进 duration 秒，完成的事件立即结算（完工/升级/拆除 + 加成重算）
static func _advance_construction(duration: float) -> void:
	var finished: Array[String] = []
	for key: String in BuildingSystem.placed:
		var p: Dictionary = BuildingSystem.placed[key]
		if p["op"] != "":
			p["remaining"] = float(p["remaining"]) - duration
			if float(p["remaining"]) <= 0.0:
				p["remaining"] = 0.0
				finished.append(key)
	for key: String in finished:
		_finish_job(key)


static func _finish_job(key: String) -> void:
	# 与 BuildingSystem._process_finished 同口径（跨类调用私有加成重算，属数据层协作）
	var p: Dictionary = BuildingSystem.placed[key]
	var cell: Vector2i = BuildingSystem.BuildingGrid.key_to_cell(key)
	var item_id: String = p["item_id"]
	match p["op"]:
		"build":
			p["completed"] = true
			p["op"] = ""
			BuildingSystem._recalculate_bonuses()
			BuildingSystem.building_completed.emit(cell, item_id)
		"upgrade":
			p["level"] = int(p["level"]) + 1
			p["op"] = ""
			BuildingSystem._recalculate_bonuses()
			BuildingSystem.building_upgraded.emit(cell, item_id, p["level"])
		"demolish":
			var refund: float = BuildingSystem.get_demolish_refund(p)
			var anchor: Vector2i = BuildingSystem.BuildingGrid.key_to_cell(key)
			BuildingSystem.placed.erase(key)
			BuildingSystem.BuildingGrid.release_cells(BuildingSystem.grid, anchor, int(p["width"]), int(p["height"]))
			GameState.add_gold(refund)
			BuildingSystem._recalculate_bonuses()
			BuildingSystem.grid_changed.emit(anchor)
			BuildingSystem.building_demolished.emit(anchor, item_id)
