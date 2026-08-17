extends Node

## 建造系统（Autoload 单例）
## 管理网格地图状态、建筑放置/建造进度/障碍清除、加成重算
## 数据来源：data/buildings.json

# === 信号 ===
signal grid_changed(cell: Vector2i)
signal building_placed(cell: Vector2i, item_id: String)
signal building_completed(cell: Vector2i, item_id: String)
signal building_upgraded(cell: Vector2i, item_id: String, level: int)
signal building_demolished(cell: Vector2i, item_id: String)
signal construction_cancelled(cell: Vector2i, item_id: String)
signal obstacle_cleared(cell: Vector2i)
signal bonus_updated

# === 网格常量 ===
# 25x14 填满中央区域（1280-250 菜单 = 1030 宽，高 590），网格居中
const GRID_W: int = 25
const GRID_H: int = 14

# === 升级/拆除参数 ===
const MAX_LEVEL: int = 5
const UPGRADE_COST_RATIO: float = 0.75  # 升级费用 = 基础费用 × 比例 × 当前等级
const UPGRADE_TIME_RATIO: float = 0.6   # 升级时间 = 建造时间 × 比例 × 当前等级
const DEMOLISH_REFUND_RATIO: float = 0.6  # 拆除返还 = 总投入 × 比例
const DEMOLISH_TIME_RATIO: float = 0.6    # 拆除时间 = 建造时间 × 比例

# === 数据配置（由 JSON 加载）===
var buildings_data: Dictionary = {}
var decorations_data: Dictionary = {}
var obstacles_data: Dictionary = {}
var cell_size: int = 40

# === 网格状态 ===
# grid[x][y]："" 空 / "occ" 被占用 / "obs:岩石" 障碍
var grid: Array = []
# placed："x,y" -> {"item_id", "width", "height", "remaining", "total", "completed", "level", "op"}
# op："" 空闲 / "build" 建造中 / "upgrade" 升级中 / "demolish" 拆除中
# 等级加成：加成 = 基础加成 × level
var placed: Dictionary = {}

# === 基础数值快照（重算加成时以它们为基准）===
var base_gold_rate: float = 0.0
var base_pop_max: int = 0
var base_pop_growth_rate: float = 0.0
var base_tech_rate: float = 0.0
var base_culture_rate: float = 0.0
var base_happiness: int = 0


func _ready() -> void:
	_load_data()
	_init_grid()
	_generate_obstacles()
	_snapshot_base_stats()


# === 数据加载 ===

func _load_data() -> void:
	var file: FileAccess = FileAccess.open("res://data/buildings.json", FileAccess.READ)
	if file == null:
		push_error("无法读取 buildings.json")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("buildings.json 格式错误")
		return
	cell_size = parsed.get("cell_size", 40)
	for b: Dictionary in parsed.get("buildings", []):
		buildings_data[b["id"]] = b
	for d: Dictionary in parsed.get("decorations", []):
		decorations_data[d["id"]] = d
	for o: Dictionary in parsed.get("obstacles", []):
		obstacles_data[o["id"]] = o


func _init_grid() -> void:
	grid.clear()
	for x: int in range(GRID_W):
		var column: Array = []
		for y: int in range(GRID_H):
			column.append("")
		grid.append(column)


# === 随机障碍生成 ===

func _generate_obstacles() -> void:
	# 随机生成岩石/树木/湖泊，点缀地图并创造"清障"玩法
	var plan: Array = []
	for i: int in range(randi_range(5, 7)):
		plan.append("rock")
	for i: int in range(randi_range(4, 6)):
		plan.append("tree")
	for i: int in range(randi_range(1, 2)):
		plan.append("lake")
	for obs_id: String in plan:
		var obs: Dictionary = obstacles_data[obs_id]
		var cell: Vector2i = _find_free_cell(obs["width"], obs["height"])
		if cell.x < 0:
			continue
		# 锚点格标记为 obs:xxx，其余格标记 occ（占用但不参与清障定位）
		for dx: int in range(int(obs["width"])):
			for dy: int in range(int(obs["height"])):
				var mark: String = "obs:" + obs_id if dx == 0 and dy == 0 else "occ"
				grid[cell.x + dx][cell.y + dy] = mark
	grid_changed.emit(Vector2i.ZERO)


func _find_free_cell(w: int, h: int) -> Vector2i:
	for attempt: int in range(60):
		var x: int = randi_range(0, GRID_W - w)
		var y: int = randi_range(0, GRID_H - h)
		if _cells_free(Vector2i(x, y), w, h):
			return Vector2i(x, y)
	return Vector2i(-1, -1)


func _cells_free(cell: Vector2i, w: int, h: int) -> bool:
	for dx: int in range(w):
		for dy: int in range(h):
			if grid[cell.x + dx][cell.y + dy] != "":
				return false
	return true


func _occupy_cells(cell: Vector2i, w: int, h: int, mark: String) -> void:
	for dx: int in range(w):
		for dy: int in range(h):
			grid[cell.x + dx][cell.y + dy] = mark
	grid_changed.emit(cell)


# === 查询 ===

func get_item(item_id: String) -> Dictionary:
	if buildings_data.has(item_id):
		return buildings_data[item_id]
	if decorations_data.has(item_id):
		return decorations_data[item_id]
	return {}


func is_obstacle(cell: Vector2i) -> bool:
	return _find_obstacle_anchor(cell).x >= 0


func get_obstacle_at(cell: Vector2i) -> Dictionary:
	var anchor: Vector2i = _find_obstacle_anchor(cell)
	if anchor.x < 0:
		return {}
	var mark: String = str(grid[anchor.x][anchor.y])
	return obstacles_data.get(mark.substr(4), {})


func get_obstacle_anchor(cell: Vector2i) -> Vector2i:
	# UI 清障时定位锚点格，避免湖泊等 2x2 障碍清错区域
	return _find_obstacle_anchor(cell)


func _find_obstacle_anchor(cell: Vector2i) -> Vector2i:
	# 若该格本身是锚点（obs:xxx）直接返回；否则检查它是否属于某个障碍的延伸格
	if cell.x < 0 or cell.y < 0:
		return Vector2i(-1, -1)
	var mark: String = str(grid[cell.x][cell.y])
	if mark.begins_with("obs:"):
		return cell
	if mark != "occ":
		return Vector2i(-1, -1)
	# occ 格：在相邻范围内查找包含它的障碍锚点
	for x: int in range(maxi(0, cell.x - 2), min(cell.x + 3, GRID_W)):
		for y: int in range(maxi(0, cell.y - 2), min(cell.y + 3, GRID_H)):
			var m: String = str(grid[x][y])
			if m.begins_with("obs:"):
				var obs: Dictionary = obstacles_data.get(m.substr(4), {})
				var w: int = int(obs.get("width", 1))
				var h: int = int(obs.get("height", 1))
				if cell.x >= x and cell.x < x + w and cell.y >= y and cell.y < y + h:
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func get_placed_at(cell: Vector2i) -> Dictionary:
	# 找到包含该格子的已放置建筑（锚点）
	var key: String = get_placed_key(cell)
	if key == "":
		return {}
	return placed[key]


func get_placed_key(cell: Vector2i) -> String:
	# 返回包含该格子的建筑锚点 key（"x,y"），用于取消建造等操作
	for key: String in placed:
		var p: Dictionary = placed[key]
		var anchor: Vector2i = _key_to_cell(key)
		if cell.x >= anchor.x and cell.x < anchor.x + int(p["width"]) \
				and cell.y >= anchor.y and cell.y < anchor.y + int(p["height"]):
			return key
	return ""


func get_placed_list() -> Dictionary:
	return placed


# === 放置建筑 ===

func place_item(cell: Vector2i, item_id: String) -> bool:
	# 部落冲突式：选中建筑 → 点击网格放置，消费金币
	var item: Dictionary = get_item(item_id)
	if item.is_empty() or cell.x < 0 or cell.y < 0:
		return false
	if cell.x + int(item["width"]) > GRID_W or cell.y + int(item["height"]) > GRID_H:
		return false
	if not _cells_free(cell, item["width"], item["height"]):
		return false
	if GameState.gold < float(item["cost"]):
		return false

	GameState.add_gold(-float(item["cost"]))
	_occupy_cells(cell, item["width"], item["height"], "occ")
	var key: String = "%d,%d" % [cell.x, cell.y]
	placed[key] = {
		"item_id": item_id,
		"width": item["width"],
		"height": item["height"],
		"remaining": float(item["build_time"]),
		"total": float(item["build_time"]),
		"completed": false,
		"level": 1,
		"op": "build",
	}
	building_placed.emit(cell, item_id)
	return true


# === 升级/拆除 ===

func upgrade_building(cell: Vector2i) -> bool:
	# 升级建筑：消耗金币与时间，等级+1，加成 = 基础 × 等级
	var key: String = get_placed_key(cell)
	if key.is_empty():
		return false
	var p: Dictionary = placed[key]
	if p["op"] != "":
		return false
	if int(p["level"]) >= MAX_LEVEL:
		return false
	var cost: float = get_upgrade_cost(p)
	if GameState.gold < cost:
		return false
	GameState.add_gold(-cost)
	var item: Dictionary = get_item(p["item_id"])
	p["remaining"] = float(item["build_time"]) * UPGRADE_TIME_RATIO * float(p["level"])
	p["total"] = p["remaining"]
	p["op"] = "upgrade"
	grid_changed.emit(cell)
	return true


func start_demolish(cell: Vector2i) -> bool:
	# 拆除建筑：需时间，完成后返还建造+升级总费用的一部分
	var key: String = get_placed_key(cell)
	if key.is_empty():
		return false
	var p: Dictionary = placed[key]
	if p["op"] != "":
		return false
	var item: Dictionary = get_item(p["item_id"])
	p["remaining"] = float(item["build_time"]) * DEMOLISH_TIME_RATIO
	p["total"] = p["remaining"]
	p["op"] = "demolish"
	grid_changed.emit(cell)
	return true


func get_upgrade_cost(p: Dictionary) -> float:
	# 升级费用随等级递增：基础费用 × 0.75 × 当前等级
	var item: Dictionary = get_item(p["item_id"])
	return float(item["cost"]) * UPGRADE_COST_RATIO * float(p["level"])


func get_demolish_refund(p: Dictionary) -> float:
	# 返还 =（建造费用 + 全部升级费用）× 60%
	var item: Dictionary = get_item(p["item_id"])
	var total: float = float(item["cost"])
	for lv: int in range(1, int(p["level"])):
		total += float(item["cost"]) * UPGRADE_COST_RATIO * float(lv)
	return total * DEMOLISH_REFUND_RATIO


# === 清除障碍 ===

func clear_obstacle(cell: Vector2i) -> bool:
	# 花费金币清除障碍，解锁可建造区域（自动定位锚点，湖泊等大障碍点击任意格均可清除）
	var anchor: Vector2i = _find_obstacle_anchor(cell)
	var obs: Dictionary = get_obstacle_at(anchor)
	if obs.is_empty():
		return false
	if GameState.gold < float(obs["clear_cost"]):
		return false
	GameState.add_gold(-float(obs["clear_cost"]))
	for dx: int in range(int(obs["width"])):
		for dy: int in range(int(obs["height"])):
			grid[anchor.x + dx][anchor.y + dy] = ""
	obstacle_cleared.emit(anchor)
	grid_changed.emit(anchor)
	return true


# === 取消建造 ===

func cancel_construction(cell: Vector2i) -> bool:
	# 点击正在建造的建筑可取消建造：释放格子并退还金币（仅建造中可取消）
	var key: String = get_placed_key(cell)
	if key.is_empty():
		return false
	var p: Dictionary = placed[key]
	if p["op"] != "build":
		return false
	var item: Dictionary = get_item(p["item_id"])
	var anchor: Vector2i = _key_to_cell(key)
	placed.erase(key)
	for dx: int in range(int(p["width"])):
		for dy: int in range(int(p["height"])):
			grid[anchor.x + dx][anchor.y + dy] = ""
	GameState.add_gold(float(item["cost"]))
	construction_cancelled.emit(anchor, p["item_id"])
	grid_changed.emit(anchor)
	return true


# === 施工计时 ===

func _process(delta: float) -> void:
	# 推进建造/升级/拆除进度（暂停时不动），完成后按 op 处理
	if TimeManager.is_paused:
		return
	var finished: Array[String] = []
	for key: String in placed:
		var p: Dictionary = placed[key]
		if p["op"] != "":
			p["remaining"] = float(p["remaining"]) - delta
			if p["remaining"] <= 0.0:
				p["remaining"] = 0.0
				finished.append(key)
	for key: String in finished:
		var p: Dictionary = placed[key]
		var cell: Vector2i = _key_to_cell(key)
		var item_id: String = p["item_id"]
		match p["op"]:
			"build":
				p["completed"] = true
				p["op"] = ""
				_recalculate_bonuses()
				building_completed.emit(cell, item_id)
			"upgrade":
				p["level"] = int(p["level"]) + 1
				p["op"] = ""
				_recalculate_bonuses()
				building_upgraded.emit(cell, item_id, p["level"])
			"demolish":
				var refund: float = get_demolish_refund(p)
				var anchor: Vector2i = _key_to_cell(key)
				placed.erase(key)
				for dx: int in range(int(p["width"])):
					for dy: int in range(int(p["height"])):
						grid[anchor.x + dx][anchor.y + dy] = ""
				GameState.add_gold(refund)
				_recalculate_bonuses()
				grid_changed.emit(anchor)
				building_demolished.emit(anchor, item_id)


# === 加成重算 ===

func _snapshot_base_stats() -> void:
	# 记录无建筑时的基础数值，重算时 = 基础 + 建筑加成
	base_gold_rate = GameState.gold_rate
	base_pop_max = GameState.pop_max
	base_pop_growth_rate = GameState.pop_growth_rate
	base_tech_rate = GameState.tech_rate
	base_culture_rate = GameState.culture_rate
	base_happiness = GameState.happiness


func _recalculate_bonuses() -> void:
	# 统计所有已完工建筑/装饰的加成（加成 = 基础 × 等级），写回 GameState 并通知 UI
	var gold_bonus: float = 0.0
	var pop_max_bonus: int = 0
	var pop_growth_bonus: float = 0.0
	var tech_bonus: float = 0.0
	var culture_bonus: float = 0.0
	var happiness_bonus: int = 0

	for key: String in placed:
		var p: Dictionary = placed[key]
		var level: int = int(p["level"])
		var item: Dictionary = get_item(p["item_id"])
		var bonuses: Dictionary = item.get("bonuses", {})
		gold_bonus += float(bonuses.get("gold_rate", 0.0)) * level
		pop_max_bonus += int(bonuses.get("pop_max", 0)) * level
		pop_growth_bonus += float(bonuses.get("pop_growth_rate", 0.0)) * level
		tech_bonus += float(bonuses.get("tech_rate", 0.0)) * level
		culture_bonus += float(bonuses.get("culture_rate", 0.0)) * level
		happiness_bonus += int(bonuses.get("happiness", 0)) * level

	GameState.gold_rate = base_gold_rate + gold_bonus
	GameState.pop_max = base_pop_max + pop_max_bonus
	GameState.pop_growth_rate = base_pop_growth_rate + pop_growth_bonus
	GameState.tech_rate = base_tech_rate + tech_bonus
	GameState.culture_rate = base_culture_rate + culture_bonus
	# 幸福度只增不降：建筑带来的幸福度下限，防止月度波动抹掉建筑价值
	if GameState.happiness < base_happiness + happiness_bonus:
		GameState.set_happiness(base_happiness + happiness_bonus)
	bonus_updated.emit()


# === 工具 ===

func _key_to_cell(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))