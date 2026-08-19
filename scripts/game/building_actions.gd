class_name BuildingActions
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
