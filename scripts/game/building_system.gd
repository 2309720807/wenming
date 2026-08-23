extends Node

## 建造系统（Autoload 单例）：网格状态、建筑操作、施工计时、加成重算。
## 设计依据：docs/design/game_design.md 3.7
## 同系统小模块已合并为内部类（避免过度拆分，见 AGENTS.md 3.1）：
##   BuildingData（数据加载）、BuildingGrid（网格工具）、BuildingBalance（数值平衡）、BuildingActions（建筑操作）
## 其他脚本访问内部类需带 BuildingSystem 前缀，如 BuildingSystem.BuildingGrid.key_to_cell(...)

# === 信号 ===
signal grid_changed(cell: Vector2i)
signal building_placed(cell: Vector2i, item_id: String)
signal building_completed(cell: Vector2i, item_id: String)
signal building_upgraded(cell: Vector2i, item_id: String, level: int)
signal building_demolished(cell: Vector2i, item_id: String)
signal construction_cancelled(cell: Vector2i, item_id: String)
signal obstacle_cleared(cell: Vector2i)
signal bonus_updated

# === 网格尺寸（由 buildings.json 加载，缺失时回退默认值）===
var GRID_W: int = BuildingData.DEFAULT_GRID_W
var GRID_H: int = BuildingData.DEFAULT_GRID_H
var cell_size: int = BuildingData.DEFAULT_CELL_SIZE

var buildings_data: Dictionary = {}
var decorations_data: Dictionary = {}
var obstacles_data: Dictionary = {}

# === 网格状态 ===
# grid[x][y]："" 空 / "occ" 占用 / "obs:障碍id"；placed："x,y" -> 建筑字典（op：""空闲/"build"/"upgrade"/"demolish"）
var grid: Array = []
var placed: Dictionary = {}

# === 基础数值快照（重算加成时以它们为基准）===
var base_gold_rate: float = 0.0
var base_pop_max: int = 0
var base_pop_growth_rate: float = 0.0
var base_tech_rate: float = 0.0
var base_culture_rate: float = 0.0
var base_happiness: int = 0

var _actions: BuildingActions

# 地图滚轮缩放比例（跨场景保持 + settings.cfg 跨启动记忆，见 set_map_zoom）
var map_zoom: float = 1.0
const MAP_ZOOM_MIN: float = 0.05  # 存储下限放宽：实际显示下限由 GridView 按地图尺寸动态计算（保证整图可见）
const MAP_ZOOM_MAX: float = 3.0
const SETTINGS_PATH: String = "user://settings.cfg"

# === 3D 摄像机视角记忆（跨场景/跨启动，见 set_map_view）===
var map_yaw: float = -0.7
var map_pitch: float = 0.55
var map_target_x: float = -1.0  # -1 表示未保存过（用地图中心）
var map_target_z: float = -1.0
var _last_view_save: float = 0.0


func _ready() -> void:
	_load_settings()
	_load_data()
	grid = BuildingGrid.init_grid(GRID_W, GRID_H)
	BuildingGrid.generate_obstacles(grid, obstacles_data, GRID_W, GRID_H)
	_snapshot_base_stats()
	_actions = BuildingActions.new(self)
	grid_changed.emit(Vector2i.ZERO)


## 设置地图缩放比例并记忆（跨场景切换保持，跨启动恢复）
func set_map_zoom(value: float) -> void:
	map_zoom = clampf(value, MAP_ZOOM_MIN, MAP_ZOOM_MAX)
	_save_settings()


## 设置 3D 摄像机视角并记忆（跨场景切换保持 + settings.cfg 跨启动恢复；节流 1 秒写盘）
## force=true 用于交互结束强制保存最终视角（避免节流只留下中间状态）
func set_map_view(yaw: float, pitch: float, target: Vector3, force: bool = false) -> void:
	map_yaw = yaw
	map_pitch = pitch
	map_target_x = target.x
	map_target_z = target.z
	var now: float = Time.get_ticks_msec() / 1000.0
	if force or now - _last_view_save > 1.0:
		_last_view_save = now
		_save_settings()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		map_zoom = clampf(float(cfg.get_value("display", "map_zoom", 1.0)), MAP_ZOOM_MIN, MAP_ZOOM_MAX)
		map_yaw = float(cfg.get_value("display", "map_yaw", -0.7))
		map_pitch = float(cfg.get_value("display", "map_pitch", 0.55))
		map_target_x = float(cfg.get_value("display", "map_target_x", -1.0))
		map_target_z = float(cfg.get_value("display", "map_target_z", -1.0))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "map_zoom", map_zoom)
	cfg.set_value("display", "map_yaw", map_yaw)
	cfg.set_value("display", "map_pitch", map_pitch)
	cfg.set_value("display", "map_target_x", map_target_x)
	cfg.set_value("display", "map_target_z", map_target_z)
	cfg.save(SETTINGS_PATH)


func _load_data() -> void:
	var data: Dictionary = BuildingData.load_all()
	buildings_data = data["buildings"]
	decorations_data = data["decorations"]
	obstacles_data = data["obstacles"]
	GRID_W = data["grid_w"]
	GRID_H = data["grid_h"]
	cell_size = data["cell_size"]


func get_item(item_id: String) -> Dictionary:
	return BuildingData.get_item(buildings_data, decorations_data, item_id)


func is_obstacle(cell: Vector2i) -> bool:
	return BuildingGrid.is_obstacle(grid, obstacles_data, cell, GRID_W, GRID_H)


func get_obstacle_at(cell: Vector2i) -> Dictionary:
	return BuildingGrid.get_obstacle_at(grid, obstacles_data, cell, GRID_W, GRID_H)


func get_obstacle_anchor(cell: Vector2i) -> Vector2i:
	return BuildingGrid.find_obstacle_anchor(grid, obstacles_data, cell, GRID_W, GRID_H)


func get_placed_at(cell: Vector2i) -> Dictionary:
	var key: String = get_placed_key(cell)
	if key == "":
		return {}
	return placed[key]


func get_placed_key(cell: Vector2i) -> String:
	return BuildingGrid.get_placed_key(placed, cell)


func place_item(cell: Vector2i, item_id: String) -> bool:
	return _actions.place_item(cell, item_id)


func cancel_construction(cell: Vector2i) -> bool:
	return _actions.cancel_construction(cell)


func upgrade_building(cell: Vector2i) -> bool:
	return _actions.upgrade_building(cell)


func start_demolish(cell: Vector2i) -> bool:
	return _actions.start_demolish(cell)


func clear_obstacle(cell: Vector2i) -> bool:
	return _actions.clear_obstacle(cell)


func get_upgrade_cost(p: Dictionary) -> float:
	var item: Dictionary = get_item(p.get("item_id", ""))
	return BuildingBalance.get_upgrade_cost(item, int(p.get("level", 1)))


func get_demolish_refund(p: Dictionary) -> float:
	var item: Dictionary = get_item(p.get("item_id", ""))
	return BuildingBalance.get_demolish_refund(item, int(p.get("level", 1)))

func reset_state() -> void:
	## 新游戏开局：重新生成空网格与随机障碍、清空已放置建筑并重算基础加成
	## （登录新建游戏时调用，避免新建游戏继承上次存档的建造状态）
	grid = BuildingGrid.init_grid(GRID_W, GRID_H)
	BuildingGrid.generate_obstacles(grid, obstacles_data, GRID_W, GRID_H)
	placed = {}
	_snapshot_base_stats()
	_recalculate_bonuses()
	grid_changed.emit(Vector2i.ZERO)


## 统计区域内可拆除对象（只读，供确认框显示）：{buildings, refund, obstacles, clear_cost}
func preview_demolish(rect: Rect2i) -> Dictionary:
	var result := {"buildings": 0, "refund": 0.0, "obstacles": 0, "clear_cost": 0.0}
	for key: String in placed:
		var anchor: Vector2i = BuildingGrid.key_to_cell(key)
		if anchor.x >= rect.position.x and anchor.x < rect.position.x + rect.size.x and anchor.y >= rect.position.y and anchor.y < rect.position.y + rect.size.y:
			var p: Dictionary = placed[key]
			var item: Dictionary = get_item(p["item_id"])
			result["buildings"] += 1
			result["refund"] += BuildingBalance.get_demolish_refund(item, int(p["level"]))
	var anchors: Array[Vector2i] = []
	for x: int in range(maxi(0, rect.position.x), mini(GRID_W, rect.position.x + rect.size.x)):
		for y: int in range(maxi(0, rect.position.y), mini(GRID_H, rect.position.y + rect.size.y)):
			var mark: String = str(grid[x][y])
			if not mark.begins_with("obs:"):
				continue
			var anchor: Vector2i = BuildingGrid.find_obstacle_anchor(grid, obstacles_data, Vector2i(x, y), GRID_W, GRID_H)
			if anchor.x < 0 or anchors.has(anchor):
				continue
			var obs: Dictionary = get_obstacle_at(anchor)
			if obs.is_empty():
				continue
			anchors.append(anchor)
			result["obstacles"] += 1
			result["clear_cost"] += float(obs.get("clear_cost", 0))
	return result


## 区域内批量拆除：建筑立即拆除（返还 60% 建造+升级投入），障碍立即清除（扣清障费）
func batch_demolish(rect: Rect2i) -> Dictionary:
	var result: Dictionary = preview_demolish(rect)
	var do_clear: bool = GameState.gold >= float(result["clear_cost"])
	var removed: Array[String] = []
	for key: String in placed:
		var anchor: Vector2i = BuildingGrid.key_to_cell(key)
		if anchor.x >= rect.position.x and anchor.x < rect.position.x + rect.size.x and anchor.y >= rect.position.y and anchor.y < rect.position.y + rect.size.y:
			removed.append(key)
	for key: String in removed:
		var p: Dictionary = placed[key]
		var anchor: Vector2i = BuildingGrid.key_to_cell(key)
		BuildingGrid.release_cells(grid, anchor, int(p["width"]), int(p["height"]))
		placed.erase(key)
		building_demolished.emit(anchor, p["item_id"])
	if result["buildings"] > 0:
		GameState.add_gold(float(result["refund"]))
	if do_clear and result["obstacles"] > 0:
		var anchors: Array[Vector2i] = []
		for x: int in range(maxi(0, rect.position.x), mini(GRID_W, rect.position.x + rect.size.x)):
			for y: int in range(maxi(0, rect.position.y), mini(GRID_H, rect.position.y + rect.size.y)):
				var mark: String = str(grid[x][y])
				if not mark.begins_with("obs:"):
					continue
				var anchor: Vector2i = BuildingGrid.find_obstacle_anchor(grid, obstacles_data, Vector2i(x, y), GRID_W, GRID_H)
				if anchor.x < 0 or anchors.has(anchor):
					continue
				var obs: Dictionary = get_obstacle_at(anchor)
				if obs.is_empty():
					continue
				anchors.append(anchor)
				BuildingGrid.release_cells(grid, anchor, int(obs.get("width", 1)), int(obs.get("height", 1)))
				obstacle_cleared.emit(anchor)
		GameState.add_gold(-float(result["clear_cost"]))
	else:
		result["obstacles"] = 0
		result["clear_cost"] = 0.0
	grid_changed.emit(Vector2i.ZERO)
	return result


## 统计区域内可升级建筑（只读）：{count, cost}（已满级/施工中跳过）
func preview_upgrade(rect: Rect2i) -> Dictionary:
	var result := {"count": 0, "cost": 0.0}
	for key: String in placed:
		var p: Dictionary = placed[key]
		if p.get("op", "") != "" or not p.get("completed", false):
			continue
		var anchor: Vector2i = BuildingGrid.key_to_cell(key)
		if anchor.x < rect.position.x or anchor.x >= rect.position.x + rect.size.x \
				or anchor.y < rect.position.y or anchor.y >= rect.position.y + rect.size.y:
			continue
		if int(p["level"]) >= BuildingBalance.MAX_LEVEL:
			continue
		result["count"] += 1
		result["cost"] += get_upgrade_cost(p)
	return result


## 区域内已完工建筑批量升级（立即完成，跳过施工时间）；返回 {upgraded, cost, skipped}
func batch_upgrade(rect: Rect2i) -> Dictionary:
	var result := {"upgraded": 0, "cost": 0.0, "skipped": 0}
	for key: String in placed:
		var p: Dictionary = placed[key]
		if p.get("op", "") != "" or not p.get("completed", false):
			continue
		var anchor: Vector2i = BuildingGrid.key_to_cell(key)
		if anchor.x < rect.position.x or anchor.x >= rect.position.x + rect.size.x \
				or anchor.y < rect.position.y or anchor.y >= rect.position.y + rect.size.y:
			continue
		if int(p["level"]) >= BuildingBalance.MAX_LEVEL:
			result["skipped"] += 1
			continue
		var cost: float = get_upgrade_cost(p)
		if GameState.gold < cost:
			result["skipped"] += 1
			continue
		GameState.add_gold(-cost)
		p["level"] = int(p["level"]) + 1
		result["upgraded"] += 1
		result["cost"] += cost
	if result["upgraded"] > 0:
		_recalculate_bonuses()
		grid_changed.emit(Vector2i.ZERO)
	return result


func expand_grid(extra_w: int, extra_h: int) -> void:
	## 扩大地图：右侧追加列、下侧追加行（消费金币由 UI 层处理），
	## 地图尺寸随存档持久化（restore_state 以存档网格尺寸为准）
	for x: int in range(extra_w):
		var column: Array = []
		for y: int in range(GRID_H + extra_h):
			column.append("")
		grid.append(column)
	for x: int in range(GRID_W):
		for y: int in range(GRID_H, GRID_H + extra_h):
			grid[x].append("")
	GRID_W += extra_w
	GRID_H += extra_h
	grid_changed.emit(Vector2i.ZERO)


func restore_state(grid_data: Array, placed_data: Dictionary, base_stats: Dictionary) -> void:
	# 恢复网格/建筑/基础快照并重算加成（SaveManager 加载时调用）
	# 存档网格尺寸优先（地图扩大持久化）；异常存档（空/损坏）时回退默认生成，避免绘制越界
	if grid_data.size() > 0 and grid_data[0] is Array and (grid_data[0] as Array).size() > 0:
		GRID_W = grid_data.size()
		GRID_H = (grid_data[0] as Array).size()
		grid = grid_data
	else:
		grid = BuildingGrid.init_grid(GRID_W, GRID_H)
		BuildingGrid.generate_obstacles(grid, obstacles_data, GRID_W, GRID_H)
	placed = placed_data
	base_gold_rate = float(base_stats.get("gold_rate", 0.0))
	base_pop_max = int(base_stats.get("pop_max", 0))
	base_pop_growth_rate = float(base_stats.get("pop_growth_rate", 0.0))
	base_tech_rate = float(base_stats.get("tech_rate", 0.0))
	base_culture_rate = float(base_stats.get("culture_rate", 0.0))
	base_happiness = int(base_stats.get("happiness", 0))
	_recalculate_bonuses()
	grid_changed.emit(Vector2i.ZERO)


func _process(delta: float) -> void:
	# 推进建造/升级/拆除进度（暂停时不动；随游戏倍速加速）
	if TimeManager.is_paused:
		return
	var step: float = delta * TimeManager.time_speed  # 施工进度随倍速加速
	var finished: Array[String] = []
	for key: String in placed:
		var p: Dictionary = placed[key]
		if p["op"] != "":
			p["remaining"] = float(p["remaining"]) - step
			if p["remaining"] <= 0.0:
				p["remaining"] = 0.0
				finished.append(key)
	for key: String in finished:
		_process_finished(key)


func _process_finished(key: String) -> void:
	var p: Dictionary = placed[key]
	var cell: Vector2i = BuildingGrid.key_to_cell(key)
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
			var anchor: Vector2i = BuildingGrid.key_to_cell(key)
			placed.erase(key)
			BuildingGrid.release_cells(grid, anchor, int(p["width"]), int(p["height"]))
			GameState.add_gold(refund)
			_recalculate_bonuses()
			grid_changed.emit(anchor)
			building_demolished.emit(anchor, item_id)


func _snapshot_base_stats() -> void:
	base_gold_rate = GameState.gold_rate
	base_pop_max = GameState.pop_max
	base_pop_growth_rate = GameState.pop_growth_rate
	base_tech_rate = GameState.tech_rate
	base_culture_rate = GameState.culture_rate
	base_happiness = GameState.happiness


func _recalculate_bonuses() -> void:
	var bonuses: Dictionary = BuildingBalance.collect_bonuses(placed, get_item)
	GameState.gold_rate = base_gold_rate + float(bonuses.get("gold_rate", 0.0))
	GameState.pop_max = base_pop_max + int(bonuses.get("pop_max", 0))
	GameState.pop_growth_rate = base_pop_growth_rate + float(bonuses.get("pop_growth_rate", 0.0))
	GameState.tech_rate = base_tech_rate + float(bonuses.get("tech_rate", 0.0))
	GameState.culture_rate = base_culture_rate + float(bonuses.get("culture_rate", 0.0))
	# 幸福度只增不降：建筑带来下限，防止月度波动抹掉建筑价值
	if GameState.happiness < base_happiness + int(bonuses.get("happiness", 0)):
		GameState.set_happiness(base_happiness + int(bonuses.get("happiness", 0)))
	bonus_updated.emit()


# ================= 内部类（同系统小模块，原独立文件已合并） =================

# === 建造数据加载（原 building_data.gd）===
class BuildingData:
	extends RefCounted

	## 建造数据加载：读取 data/buildings.json，提供建筑/装饰/障碍物查询。
	## 设计依据：docs/design/game_design.md 3.7（数据驱动，平衡调整只改 JSON）

	const DATA_PATH: String = "res://data/buildings.json"
	const DEFAULT_GRID_W: int = 25
	const DEFAULT_GRID_H: int = 14
	const DEFAULT_CELL_SIZE: int = 40


	static func load_all() -> Dictionary:
		## 返回 {buildings, decorations, obstacles, grid_w, grid_h, cell_size}
		var result: Dictionary = {
			"buildings": {},
			"decorations": {},
			"obstacles": {},
			"grid_w": DEFAULT_GRID_W,
			"grid_h": DEFAULT_GRID_H,
			"cell_size": DEFAULT_CELL_SIZE,
		}
		var file: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
		if file == null:
			push_error("无法读取 buildings.json")
			return result
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is not Dictionary:
			push_error("buildings.json 格式错误")
			return result
		# 网格尺寸以 JSON 为准（数据驱动），缺失时回退默认值
		result["grid_w"] = int(parsed.get("grid_width", DEFAULT_GRID_W))
		result["grid_h"] = int(parsed.get("grid_height", DEFAULT_GRID_H))
		result["cell_size"] = int(parsed.get("cell_size", DEFAULT_CELL_SIZE))
		for b: Dictionary in parsed.get("buildings", []):
			result["buildings"][b["id"]] = b
		for d: Dictionary in parsed.get("decorations", []):
			result["decorations"][d["id"]] = d
		for o: Dictionary in parsed.get("obstacles", []):
			result["obstacles"][o["id"]] = o
		return result


	static func get_item(buildings: Dictionary, decorations: Dictionary, item_id: String) -> Dictionary:
		if buildings.has(item_id):
			return buildings[item_id]
		if decorations.has(item_id):
			return decorations[item_id]
		return {}


# === 建造数值平衡（原 building_balance.gd）===
class BuildingBalance:
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


# === 网格工具（原 building_grid.gd）===
class BuildingGrid:
	extends RefCounted

	## 网格工具：网格初始化、随机障碍生成、占用/释放、锚点与占位查询。
	## 静态方法，grid/placed 等可变状态以参数传入（Dictionary/Array 引用传递）。
	## 设计依据：docs/design/game_design.md 3.7


	static func init_grid(w: int, h: int) -> Array:
		# grid[x][y]："" 空 / "occ" 被占用 / "obs:岩石" 障碍
		var grid: Array = []
		for x: int in range(w):
			var column: Array = []
			for y: int in range(h):
				column.append("")
			grid.append(column)
		return grid


	static func generate_obstacles(grid: Array, obstacles_data: Dictionary, grid_w: int, grid_h: int) -> void:
		# 随机生成岩石/树木/湖泊，点缀地图并创造"清障"玩法
		var plan: Array = []
		for i: int in range(randi_range(5, 7)):
			plan.append("rock")
		for i: int in range(randi_range(4, 6)):
			plan.append("tree")
		for i: int in range(randi_range(1, 2)):
			plan.append("lake")
		for obs_id: String in plan:
			if not obstacles_data.has(obs_id):
				continue
			var obs: Dictionary = obstacles_data[obs_id]
			var cell: Vector2i = find_free_cell(grid, int(obs["width"]), int(obs["height"]), grid_w, grid_h)
			if cell.x < 0:
				continue
			# 锚点格标记为 obs:xxx，其余格标记 occ（占用但不参与清障定位）
			for dx: int in range(int(obs["width"])):
				for dy: int in range(int(obs["height"])):
					var mark: String = "obs:" + obs_id if dx == 0 and dy == 0 else "occ"
					grid[cell.x + dx][cell.y + dy] = mark


	static func find_free_cell(grid: Array, w: int, h: int, grid_w: int, grid_h: int) -> Vector2i:
		for attempt: int in range(60):
			var x: int = randi_range(0, grid_w - w)
			var y: int = randi_range(0, grid_h - h)
			if cells_free(grid, Vector2i(x, y), w, h):
				return Vector2i(x, y)
		return Vector2i(-1, -1)


	static func cells_free(grid: Array, cell: Vector2i, w: int, h: int) -> bool:
		for dx: int in range(w):
			for dy: int in range(h):
				if grid[cell.x + dx][cell.y + dy] != "":
					return false
		return true


	static func occupy_cells(grid: Array, cell: Vector2i, w: int, h: int, mark: String) -> void:
		for dx: int in range(w):
			for dy: int in range(h):
				grid[cell.x + dx][cell.y + dy] = mark


	static func release_cells(grid: Array, cell: Vector2i, w: int, h: int) -> void:
		for dx: int in range(w):
			for dy: int in range(h):
				grid[cell.x + dx][cell.y + dy] = ""


	static func is_obstacle(grid: Array, obstacles_data: Dictionary, cell: Vector2i, grid_w: int, grid_h: int) -> bool:
		return find_obstacle_anchor(grid, obstacles_data, cell, grid_w, grid_h).x >= 0


	static func get_obstacle_at(grid: Array, obstacles_data: Dictionary, cell: Vector2i, grid_w: int, grid_h: int) -> Dictionary:
		var anchor: Vector2i = find_obstacle_anchor(grid, obstacles_data, cell, grid_w, grid_h)
		if anchor.x < 0:
			return {}
		var mark: String = str(grid[anchor.x][anchor.y])
		return obstacles_data.get(mark.substr(4), {})


	static func find_obstacle_anchor(grid: Array, obstacles_data: Dictionary, cell: Vector2i, grid_w: int, grid_h: int) -> Vector2i:
		# 若该格本身是锚点（obs:xxx）直接返回；否则检查它是否属于某个障碍的延伸格
		if cell.x < 0 or cell.y < 0:
			return Vector2i(-1, -1)
		var mark: String = str(grid[cell.x][cell.y])
		if mark.begins_with("obs:"):
			return cell
		if mark != "occ":
			return Vector2i(-1, -1)
		for x: int in range(maxi(0, cell.x - 2), mini(cell.x + 3, grid_w)):
			for y: int in range(maxi(0, cell.y - 2), mini(cell.y + 3, grid_h)):
				var m: String = str(grid[x][y])
				if m.begins_with("obs:"):
					var obs: Dictionary = obstacles_data.get(m.substr(4), {})
					var w: int = int(obs.get("width", 1))
					var h: int = int(obs.get("height", 1))
					if cell.x >= x and cell.x < x + w and cell.y >= y and cell.y < y + h:
						return Vector2i(x, y)
		return Vector2i(-1, -1)


	static func get_placed_key(placed: Dictionary, cell: Vector2i) -> String:
		# 返回包含该格子的建筑锚点 key（"x,y"），用于取消建造等操作
		for key: String in placed:
			var p: Dictionary = placed[key]
			var anchor: Vector2i = key_to_cell(key)
			if cell.x >= anchor.x and cell.x < anchor.x + int(p["width"]) and cell.y >= anchor.y and cell.y < anchor.y + int(p["height"]):
				return key
		return ""


	static func key_to_cell(key: String) -> Vector2i:
		var parts: PackedStringArray = key.split(",")
		return Vector2i(int(parts[0]), int(parts[1]))


# === 建筑操作（原 building_actions.gd）===
class BuildingActions:
	extends RefCounted

	## 建筑操作：放置/取消建造/升级/拆除/清除障碍。
	## 作为 BuildingSystem 的协作者，通过 system 引用访问状态（grid/placed）与信号，
	## 使 Autoload 保持职责单一（状态 + 计时 + 委托）。

	var system: Node  # BuildingSystem 实例（动态访问其 grid/placed/信号）


	func _init(building_system: Node) -> void:
		system = building_system


	## 放置建筑：选中建筑 → 点击网格放置，消费金币
	func place_item(cell: Vector2i, item_id: String) -> bool:
		var item: Dictionary = system.get_item(item_id)
		if item.is_empty() or cell.x < 0 or cell.y < 0:
			return false
		var w: int = int(item.get("width", 1))
		var h: int = int(item.get("height", 1))
		if cell.x + w > system.GRID_W or cell.y + h > system.GRID_H:
			return false
		if not BuildingGrid.cells_free(system.grid, cell, w, h):
			return false
		if GameState.gold < float(item.get("cost", 0.0)):
			return false
		GameState.add_gold(-float(item.get("cost", 0.0)))
		BuildingGrid.occupy_cells(system.grid, cell, w, h, "occ")
		var key: String = "%d,%d" % [cell.x, cell.y]
		system.placed[key] = {
			"item_id": item_id,
			"width": w,
			"height": h,
			"remaining": float(item.get("build_time", 0.0)),
			"total": float(item.get("build_time", 0.0)),
			"completed": false,
			"level": 1,
			"op": "build",
		}
		system.building_placed.emit(cell, item_id)
		return true


	## 取消建造：仅建造中可取消，释放格子并退还金币
	func cancel_construction(cell: Vector2i) -> bool:
		var key: String = system.get_placed_key(cell)
		if key.is_empty():
			return false
		var p: Dictionary = system.placed[key]
		if p["op"] != "build":
			return false
		var item: Dictionary = system.get_item(p["item_id"])
		var anchor: Vector2i = BuildingGrid.key_to_cell(key)
		system.placed.erase(key)
		BuildingGrid.release_cells(system.grid, anchor, int(p["width"]), int(p["height"]))
		GameState.add_gold(float(item.get("cost", 0.0)))
		system.construction_cancelled.emit(anchor, p["item_id"])
		system.grid_changed.emit(anchor)
		return true


	## 升级建筑：消耗金币与时间，等级+1，加成 = 基础 × 等级
	func upgrade_building(cell: Vector2i) -> bool:
		var key: String = system.get_placed_key(cell)
		if key.is_empty():
			return false
		var p: Dictionary = system.placed[key]
		if p["op"] != "" or int(p["level"]) >= BuildingBalance.MAX_LEVEL:
			return false
		var cost: float = system.get_upgrade_cost(p)
		if GameState.gold < cost:
			return false
		GameState.add_gold(-cost)
		var item: Dictionary = system.get_item(p["item_id"])
		p["remaining"] = float(item.get("build_time", 0.0)) * BuildingBalance.UPGRADE_TIME_RATIO * float(p["level"])
		p["total"] = p["remaining"]
		p["op"] = "upgrade"
		system.grid_changed.emit(cell)
		return true


	## 拆除建筑：需时间，完成后返还建造+升级总费用的一部分
	func start_demolish(cell: Vector2i) -> bool:
		var key: String = system.get_placed_key(cell)
		if key.is_empty():
			return false
		var p: Dictionary = system.placed[key]
		if p["op"] != "":
			return false
		var item: Dictionary = system.get_item(p["item_id"])
		p["remaining"] = float(item.get("build_time", 0.0)) * BuildingBalance.DEMOLISH_TIME_RATIO
		p["total"] = p["remaining"]
		p["op"] = "demolish"
		system.grid_changed.emit(cell)
		return true


	## 清除障碍：花费金币解锁可建造区域（自动定位锚点，大障碍点击任意格均可清除）
	func clear_obstacle(cell: Vector2i) -> bool:
		var anchor: Vector2i = system.get_obstacle_anchor(cell)
		var obs: Dictionary = system.get_obstacle_at(anchor)
		if obs.is_empty():
			return false
		if GameState.gold < float(obs.get("clear_cost", 0.0)):
			return false
		GameState.add_gold(-float(obs.get("clear_cost", 0.0)))
		BuildingGrid.release_cells(system.grid, anchor, int(obs.get("width", 1)), int(obs.get("height", 1)))
		system.obstacle_cleared.emit(anchor)
		system.grid_changed.emit(anchor)
		return true







