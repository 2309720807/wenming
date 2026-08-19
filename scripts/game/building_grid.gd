class_name BuildingGrid
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
		if cell.x >= anchor.x and cell.x < anchor.x + int(p["width"]) \
				and cell.y >= anchor.y and cell.y < anchor.y + int(p["height"]):
			return key
	return ""


static func key_to_cell(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))
