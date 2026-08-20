extends Node

## 存档管理（Autoload 单例）
## 开发者调试用本地存档：user://saves/ 目录，JSON 格式，按角色名保存。
## 规则依据：AGENTS.md 3.2（调试工具）；数据层职责：序列化/反序列化/目录管理

const SAVE_DIR: String = "user://saves/"
const AUTOSAVE_INTERVAL: float = 10.0  # 自动保存间隔（秒）
const AUTOSAVE_ROLE: String = "自动存档"
const LAST_SEEN_PATH: String = "user://saves/.last_seen"  # 上次结算时间戳

var _autosave_timer: Timer
var last_offline_gains: Dictionary = {}  # 最近一次离线挂机结算 {"seconds", "months", "gold"}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL
	_autosave_timer.timeout.connect(_on_autosave)
	add_child(_autosave_timer)
	_autosave_timer.start()
	_settle_offline_gains()


func _exit_tree() -> void:
	# 仅真实游戏场景（登录/主界面）退出时保存自动存档并记时间戳；
	# -s 测试脚本无 current_scene，不写入，避免污染用户存档目录
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	save_game(AUTOSAVE_ROLE)
	_write_last_seen()


func _settle_offline_gains() -> void:
	# 启动：读取上次退出时间戳 → 若有自动存档则加载并结算离线收益 → 写回自动存档
	var last: float = _read_last_seen()
	_write_last_seen()
	if last <= 0.0:
		return
	var elapsed: float = float(Time.get_unix_time_from_system()) - last
	if elapsed <= 0.0 or not FileAccess.file_exists(SAVE_DIR + AUTOSAVE_ROLE + ".json"):
		return
	var loaded: Dictionary = load_game(AUTOSAVE_ROLE + ".json")
	if not loaded["ok"]:
		return
	# 防御异常存档：网格全空且无建筑（如旧版本/测试残留）时重新生成开局障碍，
	# 避免把随机树/石头/湖泊等阻挡物覆盖掉
	if _grid_all_empty(BuildingSystem.grid) and BuildingSystem.placed.is_empty():
		BuildingSystem.BuildingGrid.generate_obstacles(BuildingSystem.grid, BuildingSystem.obstacles_data,
				BuildingSystem.GRID_W, BuildingSystem.GRID_H)
	last_offline_gains = OfflineGains.apply_offline(elapsed)
	# 离线结算推进了年月，重新对齐 TimeManager 时间，防止 _process 把时间覆盖回去
	TimeManager.sync_to_save(GameState.year, GameState.month)
	save_game(AUTOSAVE_ROLE)
	_write_last_seen()
	print("离线挂机结算：%.1f 秒（%.1f 月），金币 +%d" % [
		elapsed, last_offline_gains.get("months", 0.0), int(last_offline_gains.get("gold", 0)),
	])


func _read_last_seen() -> float:
	if not FileAccess.file_exists(LAST_SEEN_PATH):
		return 0.0
	return float(FileAccess.get_file_as_string(LAST_SEEN_PATH).strip_edges())


func _grid_all_empty(grid: Array) -> bool:
	for col: Array in grid:
		for mark: Variant in col:
			if str(mark) != "":
				return false
	return true


func _write_last_seen() -> void:
	var f := FileAccess.open(LAST_SEEN_PATH, FileAccess.WRITE)
	if f:
		f.store_string("%d" % int(Time.get_unix_time_from_system()))


func _on_autosave() -> void:
	# 仅在游戏主界面运行期间自动保存，避免登录/其他界面覆盖"自动存档"槽
	var scene: Node = get_tree().current_scene
	if scene == null or scene.name != "MainUI":
		return
	save_game(AUTOSAVE_ROLE)
	_write_last_seen()  # 同步结算点，崩溃时最多损失一个自动保存间隔


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
	# 同步游戏时间：避免 TimeManager 用"本次启动运行时长"覆盖存档年月（修复：不同存档进入后时间被抹平）
	TimeManager.sync_to_save(GameState.year, GameState.month)
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
