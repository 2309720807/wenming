extends Node

## 军事系统（Autoload 单例）：军事设施制造库存、军事基地建设、军事规模与攻城事件。
## 设计依据：docs/design/game_design.md 3.12（军事与防御）
## 数据层职责：数据加载、制造/部署、规模计算、攻城触发；UI 见 military_view.gd

# === 信号 ===
signal inventory_changed  # 库存变化（制造/部署后刷新制造页）
signal base_changed(cell: Vector2i)  # 基地网格变化
signal siege_triggered(wave: int, power: int)  # 人机攻城触发
signal siege_resolved(victory: bool, destroyed: int)  # 攻城结算

const DATA_PATH: String = "res://data/military.json"
const SIEGE_THRESHOLD: int = 30  # 军事规模达到该值后可能触发攻城
const EXPAND_COST_BASE: int = 300  # 基地扩大基础费用（金币）

var units_data: Dictionary = {}
var BASE_W: int = 15
var BASE_H: int = 10
var cell_size: int = 40

var inventory: Dictionary = {}  # unit_id -> 已制造未部署数量
var base_grid: Array = []       # 基地网格（同主地图格式："" / "occ"）
var base_placed: Dictionary = {}  # "x,y" -> {unit_id, hp, max_hp}
var expansions: int = 0          # 基地扩大次数
var _siege_cooldown: float = 0.0  # 攻城冷却计时
var _last_score: int = 0


func _ready() -> void:
	_load_data()
	_reset_base()
	_siege_cooldown = 120.0


func _load_data() -> void:
	var file: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("无法读取 military.json")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("military.json 格式错误")
		return
	BASE_W = int(parsed.get("base_width", 15))
	BASE_H = int(parsed.get("base_height", 10))
	for u: Dictionary in parsed.get("units", []):
		units_data[u["id"]] = u


func _reset_base() -> void:
	base_grid = []
	for x: int in range(BASE_W):
		var column: Array = []
		for y: int in range(BASE_H):
			column.append("")
		base_grid.append(column)
	base_placed = {}


## 制造军事设施：消耗金币 + 科技点，进入库存
func manufacture(unit_id: String) -> Dictionary:
	var unit: Dictionary = units_data.get(unit_id, {})
	if unit.is_empty():
		return {"ok": false, "message": "未知设施"}
	var gold: float = float(unit.get("cost_gold", 0))
	var tech: float = float(unit.get("cost_tech", 0))
	if GameState.gold < gold or GameState.tech_points < tech:
		return {"ok": false, "message": "资源不足：需要 %d 金币 + %d 科技点" % [int(gold), int(tech)]}
	GameState.add_gold(-gold)
	GameState.add_tech(-tech)
	inventory[unit_id] = int(inventory.get(unit_id, 0)) + 1
	inventory_changed.emit()
	return {"ok": true, "message": "已制造「%s」×1（库存 %d）" % [unit.get("name", ""), inventory[unit_id]]}


## 从库存部署设施到基地
func place_unit(unit_id: String, cell: Vector2i) -> bool:
	if int(inventory.get(unit_id, 0)) <= 0:
		return false
	var unit: Dictionary = units_data.get(unit_id, {})
	if unit.is_empty() or cell.x < 0 or cell.y < 0:
		return false
	var w: int = int(unit.get("width", 1))
	var h: int = int(unit.get("height", 1))
	if cell.x + w > BASE_W or cell.y + h > BASE_H:
		return false
	if not _cells_free(cell, w, h):
		return false
	_occupy(cell, w, h)
	var key: String = "%d,%d" % [cell.x, cell.y]
	var hp: int = int(unit.get("hp", 100))
	base_placed[key] = {
		"unit_id": unit_id, "width": w, "height": h,
		"hp": hp, "max_hp": hp, "level": 1,
	}
	inventory[unit_id] = int(inventory[unit_id]) - 1
	inventory_changed.emit()
	base_changed.emit(cell)
	return true


## 拆除基地设施（返还 50% 制造资源）
func remove_unit(cell: Vector2i) -> bool:
	var key: String = get_placed_key(cell)
	if key == "":
		return false
	var p: Dictionary = base_placed[key]
	var unit: Dictionary = units_data.get(p["unit_id"], {})
	_release(cell, int(p["width"]), int(p["height"]))
	base_placed.erase(key)
	GameState.add_gold(float(unit.get("cost_gold", 0)) * 0.5)
	GameState.add_tech(float(unit.get("cost_tech", 0)) * 0.5)
	base_changed.emit(cell)
	return true


## 单设施升级费用（随等级递增）：金币/科技 = 制造费 × 0.6 × 等级
func upgrade_cost(unit: Dictionary, level: int) -> Dictionary:
	return {
		"gold": float(unit.get("cost_gold", 0)) * 0.6 * float(level),
		"tech": float(unit.get("cost_tech", 0)) * 0.6 * float(level),
	}


## 区域内设施批量升级（立即生效，每级攻击/生命 +25%）；返回 {upgraded, cost_gold, cost_tech, skipped}
func batch_upgrade(rect: Rect2i) -> Dictionary:
	var result := {"upgraded": 0, "cost_gold": 0.0, "cost_tech": 0.0, "skipped": 0}
	for key: String in base_placed:
		var p: Dictionary = base_placed[key]
		var anchor: Vector2i = _key_to_cell(key)
		if anchor.x < rect.position.x or anchor.x >= rect.position.x + rect.size.x \
				or anchor.y < rect.position.y or anchor.y >= rect.position.y + rect.size.y:
			continue
		var unit: Dictionary = units_data.get(p["unit_id"], {})
		var level: int = int(p.get("level", 1))
		var cost: Dictionary = upgrade_cost(unit, level)
		if GameState.gold < float(cost["gold"]) or GameState.tech_points < float(cost["tech"]):
			result["skipped"] += 1
			continue
		GameState.add_gold(-float(cost["gold"]))
		GameState.add_tech(-float(cost["tech"]))
		p["level"] = level + 1
		# 每级生命/攻击提升 25%
		p["max_hp"] = int(float(unit.get("hp", 100)) * pow(1.25, float(level)))
		p["hp"] = p["max_hp"]
		result["upgraded"] += 1
		result["cost_gold"] += float(cost["gold"])
		result["cost_tech"] += float(cost["tech"])
	if result["upgraded"] > 0:
		base_changed.emit(Vector2i.ZERO)
	return result


## 扩大军事基地：+2 列 +2 行，费用递增（金币 + 科技）
func expand_base() -> Dictionary:
	var cost_gold: int = EXPAND_COST_BASE * (expansions + 1)
	var cost_tech: int = 5 * (expansions + 1)
	if GameState.gold < cost_gold or GameState.tech_points < cost_tech:
		return {"ok": false, "message": "资源不足：扩大需要 %d 金币 + %d 科技点" % [cost_gold, cost_tech]}
	GameState.add_gold(-cost_gold)
	GameState.add_tech(-cost_tech)
	expansions += 1
	BASE_W += 2
	BASE_H += 2
	for x: int in range(2):
		var column: Array = []
		for y: int in range(BASE_H):
			column.append("")
		base_grid.append(column)
	for x: int in range(BASE_W - 2):
		for y: int in range(BASE_H - 2, BASE_H):
			base_grid[x].append("")
	base_changed.emit(Vector2i.ZERO)
	return {"ok": true, "message": "基地已扩大至 %dx%d" % [BASE_W, BASE_H]}


## 军事规模：库存战力 + 部署设施战力（含军械库加成）
func military_score() -> int:
	## 军事规模只统计防御角色（offense 进攻单位为副本所用，不参与基地防御）
	var score: int = 0
	for unit_id: String in inventory:
		if units_data.get(unit_id, {}).get("role", "defense") == "defense":
			score += int(inventory[unit_id]) * _unit_power(units_data.get(unit_id, {}))
	for key: String in base_placed:
		var p: Dictionary = base_placed[key]
		var level: int = int(p.get("level", 1))
		score += int(_unit_power(units_data.get(p["unit_id"], {})) * (1.0 + 0.2 * float(level - 1)))
	return score


func _unit_power(unit: Dictionary) -> int:
	var atk: float = float(unit.get("attack", 0))
	var hp: float = float(unit.get("hp", 50))
	return int(atk * 1.5 + hp * 0.2)


func _process(delta: float) -> void:
	# 攻城触发：军事规模达到阈值后周期性触发人机攻城
	if _siege_cooldown > 0.0:
		_siege_cooldown -= delta
		return
	if military_score() < SIEGE_THRESHOLD:
		_siege_cooldown = 60.0
		return
	_siege_cooldown = 180.0  # 每 3 分钟可能来一波
	if _last_score == military_score():
		if randf() > 0.35:
			return
	_trigger_siege()


func _trigger_siege() -> void:
	var wave: int = 1 + military_score() / 80
	var power: int = military_score() * 6 / 10 + wave * 40
	siege_triggered.emit(wave, power)
	# 简化解算：防御战力 vs 攻城战力
	var defense: int = military_score() * 10
	var victory: bool = defense >= power
	var destroyed: int = 0
	if victory:
		GameState.add_gold(power * 2)  # 击退奖励
	else:
		destroyed = _damage_units(randi_range(2, 5))
	siege_resolved.emit(victory, destroyed)
	_last_score = military_score()


func _damage_units(count: int) -> int:
	var keys: Array[String] = []
	for key: String in base_placed:
		keys.append(key)
	keys.shuffle()
	var destroyed: int = 0
	for i: int in range(mini(count, keys.size())):
		var key: String = keys[i]
		var p: Dictionary = base_placed[key]
		var cell: Vector2i = _key_to_cell(key)
		_release(cell, int(p["width"]), int(p["height"]))
		base_placed.erase(key)
		destroyed += 1
		base_changed.emit(cell)
	return destroyed


# === 网格工具 ===

func _cells_free(cell: Vector2i, w: int, h: int) -> bool:
	for dx: int in range(w):
		for dy: int in range(h):
			if str(base_grid[cell.x + dx][cell.y + dy]) != "":
				return false
	return true


func _occupy(cell: Vector2i, w: int, h: int) -> void:
	for dx: int in range(w):
		for dy: int in range(h):
			base_grid[cell.x + dx][cell.y + dy] = "occ"


func _release(cell: Vector2i, w: int, h: int) -> void:
	for dx: int in range(w):
		for dy: int in range(h):
			base_grid[cell.x + dx][cell.y + dy] = ""


func get_placed_key(cell: Vector2i) -> String:
	for key: String in base_placed:
		var p: Dictionary = base_placed[key]
		var anchor: Vector2i = _key_to_cell(key)
		if cell.x >= anchor.x and cell.x < anchor.x + int(p["width"]) and cell.y >= anchor.y and cell.y < anchor.y + int(p["height"]):
			return key
	return ""


func _key_to_cell(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))


# === 存档 ===

## 新游戏开局重置军事状态（登录新建角色时调用）：
## Autoload 单例跨角色存活，不重置会继承上一角色的基地/库存（修复：各角色军事数据串号）
func reset_state() -> void:
	inventory = {}
	expansions = 0
	_siege_cooldown = 0.0
	_reset_base()
	base_changed.emit(Vector2i.ZERO)


func collect_state() -> Dictionary:
	return {
		"inventory": inventory,
		"base_grid": base_grid,
		"base_placed": base_placed,
		"expansions": expansions,
		"base_w": BASE_W,
		"base_h": BASE_H,
	}


func restore_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	inventory = data.get("inventory", {})
	expansions = int(data.get("expansions", 0))
	var bw: int = int(data.get("base_w", BASE_W))
	var bh: int = int(data.get("base_h", BASE_H))
	BASE_W = bw
	BASE_H = bh
	var g: Array = data.get("base_grid", [])
	if g.size() == BASE_W and (g[0] as Array).size() == BASE_H:
		base_grid = g
	else:
		_reset_base()
	base_placed = data.get("base_placed", {})
	base_changed.emit(Vector2i.ZERO)
