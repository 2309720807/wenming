extends Node

## 临时验证脚本：验证建造系统核心逻辑（放置/扣除/加成/清障/取消/建造完成）

var _failures: int = 0


func _ready() -> void:
	call_deferred("_run_checks")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: " + msg)
	else:
		_failures += 1
		print("FAIL: " + msg)


func _run_checks() -> void:
	print("=== 建造系统验证开始 ===")
	# 1. 数据加载
	_check(BuildingSystem.buildings_data.size() == 5, "加载 5 种建筑")
	_check(BuildingSystem.decorations_data.size() == 3, "加载 3 种装饰")
	_check(BuildingSystem.obstacles_data.size() == 3, "加载 3 种障碍")

	# 2. 网格初始化 + 障碍生成（锚点格数量 10-15）
	var obs_count: int = 0
	for x: int in range(BuildingSystem.GRID_W):
		for y: int in range(BuildingSystem.GRID_H):
			if str(BuildingSystem.grid[x][y]).begins_with("obs:"):
				obs_count += 1
	_check(obs_count >= 10 and obs_count <= 15, "障碍数量 %d 在 10-15" % obs_count)

	# 3. 放置住宅（60 金币）
	var base_gold: float = GameState.gold
	var house_cell: Vector2i = _find_empty(2, 2)
	var result: bool = BuildingSystem.place_item(house_cell, "residence")
	_check(result == true, "放置住宅成功")
	_check(is_equal_approx(GameState.gold, base_gold - 60.0), "扣除 60 金币")

	# 4. 重叠放置失败
	var overlap: bool = BuildingSystem.place_item(house_cell, "office")
	_check(overlap == false, "重叠位置放置失败")
	_check(is_equal_approx(GameState.gold, base_gold - 60.0), "重叠放置未扣金币")

	# 5. 边界外放置失败
	var out: bool = BuildingSystem.place_item(Vector2i(BuildingSystem.GRID_W - 1, BuildingSystem.GRID_H - 1), "finance")
	_check(out == false, "边界外放置失败")

	# 6. 取消建造：返还金币、格子释放、placed 移除
	var key: String = "%d,%d" % [house_cell.x, house_cell.y]
	var gold_before_cancel: float = GameState.gold
	var cancelled: bool = BuildingSystem.cancel_construction(house_cell)
	_check(cancelled == true, "取消建造成功")
	_check(is_equal_approx(GameState.gold, gold_before_cancel + 60.0), "取消后返还 60 金币")
	_check(not BuildingSystem.placed.has(key), "取消后从 placed 移除")
	_check(BuildingSystem.grid[house_cell.x][house_cell.y] == "", "取消后格子释放")
	# 已完工建筑不可取消
	var cancel_completed: bool = BuildingSystem.cancel_construction(Vector2i(-1, -1))
	_check(cancel_completed == false, "无效格子取消失败")

	# 7. 建造完成 → 加成生效
	var house_cell2: Vector2i = _find_empty(2, 2)
	BuildingSystem.place_item(house_cell2, "residence")
	var key2: String = "%d,%d" % [house_cell2.x, house_cell2.y]
	BuildingSystem.placed[key2]["remaining"] = 0.01
	BuildingSystem._process(0.02)
	_check(BuildingSystem.placed[key2]["completed"] == true, "建造完成")
	_check(is_equal_approx(GameState.gold_rate, BuildingSystem.base_gold_rate), "住宅无金币加成（%s）" % GameState.gold_rate)

	# 8. 办公楼金币加成（动态寻找空位放置）
	GameState.add_gold(200.0)
	var office_cell: Vector2i = _find_empty(2, 2)
	BuildingSystem.place_item(office_cell, "office")
	var office_key: String = "%d,%d" % [office_cell.x, office_cell.y]
	BuildingSystem.placed[office_key]["remaining"] = 0.01
	BuildingSystem._process(0.02)
	_check(is_equal_approx(GameState.gold_rate, BuildingSystem.base_gold_rate + 2.0), "办公楼 +2 金币/月（%s）" % GameState.gold_rate)

	# 9. 医院幸福度加成
	var hospital_cell: Vector2i = _find_empty(2, 2)
	BuildingSystem.place_item(hospital_cell, "hospital")
	var hospital_key: String = "%d,%d" % [hospital_cell.x, hospital_cell.y]
	BuildingSystem.placed[hospital_key]["remaining"] = 0.01
	BuildingSystem._process(0.02)
	_check(GameState.happiness >= BuildingSystem.base_happiness + 2, "医院幸福度 +2（%d）" % GameState.happiness)

	# 10. 清障：锚点格
	var obs_cell: Vector2i = _find_obstacle_anchor()
	var obs_anchor: Vector2i = BuildingSystem.get_obstacle_anchor(obs_cell)
	GameState.add_gold(100.0)
	var gold_before: float = GameState.gold
	var cost: float = float(BuildingSystem.get_obstacle_at(obs_anchor).get("clear_cost", 0))
	var cleared: bool = BuildingSystem.clear_obstacle(obs_anchor)
	_check(cleared == true, "清除障碍成功")
	_check(is_equal_approx(GameState.gold, gold_before - cost), "清障扣除 %s 金币" % cost)
	_check(BuildingSystem.grid[obs_anchor.x][obs_anchor.y] == "", "障碍锚点格已清空")

	# 11. 清障：湖泊延伸格（occ 格）也能定位锚点并清除
	var lake_anchor: Vector2i = _find_obstacle_anchor_of("lake")
	if lake_anchor.x >= 0:
		var lake_occ: Vector2i = Vector2i(lake_anchor.x + 1, lake_anchor.y)
		_check(BuildingSystem.is_obstacle(lake_occ) == true, "湖泊延伸格识别为障碍")
		var lake_cost: float = float(BuildingSystem.get_obstacle_at(lake_occ).get("clear_cost", 0))
		var lake_gold: float = GameState.gold
		_check(BuildingSystem.clear_obstacle(lake_occ) == true, "从延伸格清除湖泊成功")
		_check(is_equal_approx(GameState.gold, lake_gold - lake_cost), "湖泊清除扣除 %s 金币" % lake_cost)
	else:
		_check(true, "无湖泊可测（跳过）")

	# 12. 金币不足无法放置
	GameState.gold = 10.0
	var poor: bool = BuildingSystem.place_item(Vector2i(2, 2), "finance")
	_check(poor == false, "金币不足放置失败")

	# 13. 建筑数量统计（住宅 + 办公楼 + 医院）
	_check(BuildingSystem.placed.size() == 3, "已放置 3 个建筑")

	# 14. 装饰放置
	GameState.add_gold(100.0)
	var garden_cell: Vector2i = _find_empty(1, 1)
	var garden_ok: bool = BuildingSystem.place_item(garden_cell, "garden")
	_check(garden_ok == true, "放置花园成功")
	_check(BuildingSystem.placed.size() == 4, "共 4 个建筑/装饰")

	# 15. 升级：费用与状态（住宅 Lv1 → Lv2，费用 60×0.75×1 = 45）
	var upgrade_gold: float = GameState.gold
	var upgrade_ok: bool = BuildingSystem.upgrade_building(house_cell2)
	_check(upgrade_ok == true, "升级住宅成功")
	_check(is_equal_approx(GameState.gold, upgrade_gold - 45.0), "升级扣除 45 金币")
	_check(BuildingSystem.placed[key2]["op"] == "upgrade", "住宅进入升级状态")
	_check(BuildingSystem.upgrade_building(house_cell2) == false, "升级中不可再次升级")

	# 16. 升级完成：等级+1，加成翻倍
	BuildingSystem.placed[key2]["remaining"] = 0.01
	BuildingSystem._process(0.02)
	_check(BuildingSystem.placed[key2]["level"] == 2, "升级后等级 2")
	_check(BuildingSystem.placed[key2]["op"] == "", "升级完成回到空闲")
	_check(GameState.pop_max == BuildingSystem.base_pop_max + 20, "住宅 Lv2 人口上限+20（%d）" % GameState.pop_max)

	# 17. 拆除：返还计算与状态
	var demolish_gold: float = GameState.gold
	var demolish_ok: bool = BuildingSystem.start_demolish(house_cell2)
	_check(demolish_ok == true, "开始拆除住宅")
	_check(BuildingSystem.placed[key2]["op"] == "demolish", "住宅进入拆除状态")
	var refund: float = BuildingSystem.get_demolish_refund(BuildingSystem.placed[key2])
	_check(is_equal_approx(refund, 63.0), "拆除返还计算 =（60+45）×60%% = 63（%s）" % refund)

	# 18. 拆除完成：移除、返还、格子释放
	BuildingSystem.placed[key2]["remaining"] = 0.01
	BuildingSystem._process(0.02)
	_check(not BuildingSystem.placed.has(key2), "拆除完成后移除 placed")
	_check(is_equal_approx(GameState.gold, demolish_gold + 63.0), "拆除完成返还 63 金币")
	_check(BuildingSystem.grid[house_cell2.x][house_cell2.y] == "", "拆除后格子释放")

	# 19. 最高等级限制
	var office_level: int = int(BuildingSystem.placed[office_key]["level"])
	BuildingSystem.placed[office_key]["level"] = BuildingSystem.MAX_LEVEL
	_check(BuildingSystem.upgrade_building(office_cell) == false, "满级不可升级")
	BuildingSystem.placed[office_key]["level"] = office_level

	# 20. 科技/文化点数化：累加不封顶、显示为点数
	GameState.add_tech(200.0)
	GameState.add_culture(150.0)
	_check(is_equal_approx(GameState.tech_points, 200.0), "科技点数累加（%s）" % GameState.tech_points)
	_check(is_equal_approx(GameState.culture_points, 150.0), "文化点数累加（%s）" % GameState.culture_points)
	_check(GameState.get_tech_display().find("%") == -1, "科技显示为点数非百分比")

	# 21. 建筑加成 × 等级：学校科技速率（Lv1 基础，验证加成随等级翻倍）
	GameState.add_gold(200.0)
	var school_cell: Vector2i = _find_empty(2, 2)
	BuildingSystem.place_item(school_cell, "school")
	var school_key: String = "%d,%d" % [school_cell.x, school_cell.y]
	BuildingSystem.placed[school_key]["remaining"] = 0.01
	BuildingSystem._process(0.02)
	_check(is_equal_approx(GameState.tech_rate, BuildingSystem.base_tech_rate + 0.2), "学校 Lv1 科技 +0.2/月（%s）" % GameState.tech_rate)
	BuildingSystem.upgrade_building(school_cell)
	BuildingSystem.placed[school_key]["remaining"] = 0.01
	BuildingSystem._process(0.02)
	_check(is_equal_approx(GameState.tech_rate, BuildingSystem.base_tech_rate + 0.4), "学校 Lv2 科技 +0.4/月（%s）" % GameState.tech_rate)

	print("=== 验证结束：%d 个失败 ===" % _failures)
	get_tree().quit(_failures)


func _find_empty(w: int, h: int) -> Vector2i:
	for attempt: int in range(500):
		var cell: Vector2i = Vector2i(
			randi_range(0, BuildingSystem.GRID_W - w),
			randi_range(0, BuildingSystem.GRID_H - h)
		)
		if BuildingSystem._cells_free(cell, w, h):
			return cell
	return Vector2i(2, 2)


func _find_obstacle_anchor() -> Vector2i:
	for x: int in range(BuildingSystem.GRID_W):
		for y: int in range(BuildingSystem.GRID_H):
			if str(BuildingSystem.grid[x][y]).begins_with("obs:"):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _find_obstacle_anchor_of(obs_id: String) -> Vector2i:
	for x: int in range(BuildingSystem.GRID_W):
		for y: int in range(BuildingSystem.GRID_H):
			if str(BuildingSystem.grid[x][y]) == "obs:" + obs_id:
				return Vector2i(x, y)
	return Vector2i(-1, -1)