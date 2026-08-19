extends Node

## 存档管理（Autoload 单例）
## 开发者调试用本地存档：user://saves/ 目录，JSON 格式，按角色名保存。
## 规则依据：AGENTS.md 3.2（调试工具）；数据层职责：序列化/反序列化/目录管理

const SAVE_DIR: String = "user://saves/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


## 保存当前游戏状态到指定角色存档，返回 {ok, file_name, message}
func save_game(role_name: String) -> Dictionary:
	var name_clean: String = role_name.strip_edges()
	if name_clean.is_empty():
		return {"ok": false, "file_name": "", "message": "请输入存档角色名"}
	if name_clean.contains("/") or name_clean.contains("\\") or name_clean.contains(":"):
		return {"ok": false, "file_name": "", "message": "角色名不能包含 / \\ : 字符"}
	var file_name: String = name_clean + ".json"
	var file := FileAccess.open(SAVE_DIR + file_name, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "file_name": file_name, "message": "存档写入失败"}
	file.store_string(JSON.stringify(_collect_state()))
	return {"ok": true, "file_name": file_name, "message": "已保存存档：%s" % name_clean}


func _collect_state() -> Dictionary:
	# GameState 全量 + BuildingSystem（网格/建筑/基础快照）
	return {
		"player_name": GameState.player_name,
		"year": GameState.year, "month": GameState.month,
		"gold": GameState.gold, "gold_rate": GameState.gold_rate,
		"population": GameState.population, "pop_max": GameState.pop_max,
		"pop_growth_rate": GameState.pop_growth_rate,
		"happiness": GameState.happiness,
		"food": GameState.food, "food_rate": GameState.food_rate,
		"wood": GameState.wood, "wood_rate": GameState.wood_rate,
		"stone": GameState.stone, "stone_rate": GameState.stone_rate,
		"metal": GameState.metal, "metal_rate": GameState.metal_rate,
		"tech_points": GameState.tech_points, "tech_rate": GameState.tech_rate,
		"culture_points": GameState.culture_points, "culture_rate": GameState.culture_rate,
		"grid": BuildingSystem.grid,
		"placed": BuildingSystem.placed,
		"base_stats": {
			"gold_rate": BuildingSystem.base_gold_rate,
			"pop_max": BuildingSystem.base_pop_max,
			"pop_growth_rate": BuildingSystem.base_pop_growth_rate,
			"tech_rate": BuildingSystem.base_tech_rate,
			"culture_rate": BuildingSystem.base_culture_rate,
			"happiness": BuildingSystem.base_happiness,
		},
	}


## 加载存档并恢复游戏状态，返回 {ok, message}
func load_game(file_name: String) -> Dictionary:
	var path: String = SAVE_DIR + file_name
	if not FileAccess.file_exists(path):
		return {"ok": false, "message": "存档不存在"}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is not Dictionary:
		return {"ok": false, "message": "存档文件损坏"}
	GameState.restore_state(parsed)
	BuildingSystem.restore_state(
		parsed.get("grid", []), parsed.get("placed", {}), parsed.get("base_stats", {}))
	return {"ok": true, "message": "已加载存档：%s" % file_name.trim_suffix(".json")}


## 列出全部存档摘要 [{file_name, player_name, gold, year, month, modified}]，新存档在前
func list_saves() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if f.ends_with(".json"):
			var summary := _read_summary(f)
			if not summary.is_empty():
				result.append(summary)
		f = dir.get_next()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("modified", 0)) > int(b.get("modified", 0)))
	return result


func _read_summary(file_name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_DIR + file_name))
	if parsed is not Dictionary:
		return {}
	return {
		"file_name": file_name,
		"player_name": parsed.get("player_name", "未知角色"),
		"gold": int(parsed.get("gold", 0)),
		"year": int(parsed.get("year", 1)),
		"month": int(parsed.get("month", 1)),
		"modified": FileAccess.get_modified_time(SAVE_DIR + file_name),
	}


## 删除存档，返回是否成功
func delete_save(file_name: String) -> bool:
	var path: String = SAVE_DIR + file_name
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK
