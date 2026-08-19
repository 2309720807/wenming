extends Node

## 建造系统（Autoload 单例）：网格地图状态、建筑放置/建造进度/障碍清除、加成重算
## 数据来源：data/buildings.json（BuildingData 加载）
## 模块划分：BuildingData（数据加载）、BuildingGrid（网格/障碍）、
##           BuildingBalance（费用/加成）、BuildingActions（建筑操作）
## 设计依据：docs/design/game_design.md 3.7

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

# === 数据配置（由 JSON 加载）===
var buildings_data: Dictionary = {}
var decorations_data: Dictionary = {}
var obstacles_data: Dictionary = {}

# === 网格状态 ===
# grid[x][y]："" 空 / "occ" 被占用 / "obs:岩石" 障碍
var grid: Array = []
# placed："x,y" -> {"item_id", "width", "height", "remaining", "total", "completed", "level", "op"}
# op："" 空闲 / "build" 建造中 / "upgrade" 升级中 / "demolish" 拆除中
var placed: Dictionary = {}

# === 基础数值快照（重算加成时以它们为基准）===
var base_gold_rate: float = 0.0
var base_pop_max: int = 0
var base_pop_growth_rate: float = 0.0
var base_tech_rate: float = 0.0
var base_culture_rate: float = 0.0
var base_happiness: int = 0

var _actions: BuildingActions


func _ready() -> void:
	_load_data()
	grid = BuildingGrid.init_grid(GRID_W, GRID_H)
	BuildingGrid.generate_obstacles(grid, obstacles_data, GRID_W, GRID_H)
	_snapshot_base_stats()
	_actions = BuildingActions.new(self)
	grid_changed.emit(Vector2i.ZERO)


func _load_data() -> void:
	var data: Dictionary = BuildingData.load_all()
	buildings_data = data["buildings"]
	decorations_data = data["decorations"]
	obstacles_data = data["obstacles"]
	GRID_W = data["grid_w"]
	GRID_H = data["grid_h"]
	cell_size = data["cell_size"]


# === 查询 ===

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


func get_placed_list() -> Dictionary:
	return placed


# === 建筑操作（委托 BuildingActions）===

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


# === 费用计算（委托 BuildingBalance）===

func get_upgrade_cost(p: Dictionary) -> float:
	var item: Dictionary = get_item(p.get("item_id", ""))
	return BuildingBalance.get_upgrade_cost(item, int(p.get("level", 1)))


func get_demolish_refund(p: Dictionary) -> float:
	var item: Dictionary = get_item(p.get("item_id", ""))
	return BuildingBalance.get_demolish_refund(item, int(p.get("level", 1)))


# === 施工计时 ===

func _process(delta: float) -> void:
	# 推进建造/升级/拆除进度（暂停时不动；随游戏倍速加速）
	if TimeManager.is_paused:
		return
	var step: float = delta * TimeManager.time_speed
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
	var bonuses: Dictionary = BuildingBalance.collect_bonuses(placed, get_item)
	GameState.gold_rate = base_gold_rate + float(bonuses.get("gold_rate", 0.0))
	GameState.pop_max = base_pop_max + int(bonuses.get("pop_max", 0))
	GameState.pop_growth_rate = base_pop_growth_rate + float(bonuses.get("pop_growth_rate", 0.0))
	GameState.tech_rate = base_tech_rate + float(bonuses.get("tech_rate", 0.0))
	GameState.culture_rate = base_culture_rate + float(bonuses.get("culture_rate", 0.0))
	# 幸福度只增不降：建筑带来的幸福度下限，防止月度波动抹掉建筑价值
	if GameState.happiness < base_happiness + int(bonuses.get("happiness", 0)):
		GameState.set_happiness(base_happiness + int(bonuses.get("happiness", 0)))
	bonus_updated.emit()
