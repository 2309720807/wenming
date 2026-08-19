class_name BuildingData
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
