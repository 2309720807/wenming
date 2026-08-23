extends Control

## 副本探索界面（部落冲突式攻城肉鸽）：
## 🔍 搜索 → 生成人机防御基地（难度递增）→ 从军事库存排兵布阵 → ⚔ 开始战斗 → 战损与收获结算
## 设计依据：docs/design/game_design.md 3.11；军事设施见 MilitarySystem 库存（需求 6：未部署设施副本可用）

const FONT_HEAVY: Font = preload("res://assets/fonts/SourceHanSansCN-Heavy.ttf")
const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")
const FONT_SERIF: Font = preload("res://assets/fonts/SourceHanSerifCN-Regular.otf")

const GRID_W: int = 15
const GRID_H: int = 10
const CELL: int = 44

var _difficulty: int = 0              # 搜索次数（难度递增）
var _enemy_placed: Dictionary = {}    # AI 基地设施 "x,y" -> {unit_id, hp, max_hp, w, h}
var _army: Array[Dictionary] = []     # 出兵序列 [{unit_id, hp, atk, pos, target, speed}]
var _battle_active: bool = false
var _battle_timer: float = 0.0
var _settled: bool = false

var _grid: InstanceGrid
var _info_label: Label
var _army_label: Label
var _search_btn: Button
var _attack_btn: Button
var _result_label: Label


func _ready() -> void:
	WindowManager.setup_scale_root(self)
	_build_ui()


func _build_ui() -> void:
	# 背景
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.01, 0.03, 0.09, 1), Color(0.05, 0.1, 0.22, 1), Color(0.01, 0.02, 0.07, 1)])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0.5, 0)
	gtex.fill_to = Vector2(0.5, 1)
	var bg := TextureRect.new()
	bg.texture = gtex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 顶部资源栏（全局资源可见）
	var res_bar := ResourceBar.new()
	res_bar.name = "ResourceBar"
	res_bar.position = Vector2(0, 6)
	res_bar.size = Vector2(1280, 44)
	add_child(res_bar)

	# 顶栏
	var top := HBoxContainer.new()
	top.position = Vector2(16, 58)
	top.custom_minimum_size = Vector2(1248, 46)
	top.add_theme_constant_override("separation", 12)
	add_child(top)
	var title := Label.new()
	title.text = "⚔ 副本探索（攻城肉鸽）"
	title.add_theme_font_override("font", FONT_HEAVY)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.4, 0.82, 1, 1))
	top.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_search_btn = Button.new()
	_search_btn.text = "🔍 搜索"
	_search_btn.custom_minimum_size = Vector2(110, 40)
	_search_btn.add_theme_font_override("font", FONT_BOLD)
	_search_btn.add_theme_font_size_override("font_size", 15)
	_search_btn.pressed.connect(_on_search_pressed)
	top.add_child(_search_btn)
	var btn_back := Button.new()
	btn_back.text = "返回主界面"
	btn_back.custom_minimum_size = Vector2(130, 40)
	btn_back.add_theme_font_override("font", FONT_BOLD)
	btn_back.add_theme_font_size_override("font_size", 14)
	btn_back.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/ui/main_ui.tscn"))
	top.add_child(btn_back)

	# 主体：左出兵面板 + 中央战场
	var body := HBoxContainer.new()
	body.position = Vector2(16, 112)
	body.custom_minimum_size = Vector2(1248, 540)
	body.add_theme_constant_override("separation", 14)
	add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 560)
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)

	var head := Label.new()
	head.text = "排兵布阵（使用军事库存设施）"
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_font_override("font", FONT_BOLD)
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(0.5, 0.8, 1, 0.95))
	left.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	for unit_id: String in MilitarySystem.units_data:
		# 副本出兵只显示进攻型单位（防御设施不可用于进攻，见设计文档 3.11）
		if MilitarySystem.units_data[unit_id].get("role", "defense") != "offense":
			continue
		var unit: Dictionary = MilitarySystem.units_data[unit_id]
		var btn := Button.new()
		btn.text = "➤ %s（库存 %d）" % [unit.get("name", ""), int(MilitarySystem.inventory.get(unit_id, 0))]
		btn.custom_minimum_size = Vector2(0, 38)
		btn.add_theme_font_override("font", FONT_BOLD)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_add_army.bind(unit_id))
		box.add_child(btn)

	_army_label = Label.new()
	_army_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_army_label.add_theme_font_override("font", FONT_SERIF)
	_army_label.add_theme_font_size_override("font_size", 13)
	_army_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1, 0.95))
	left.add_child(_army_label)

	_attack_btn = Button.new()
	_attack_btn.text = "⚔ 开始战斗"
	_attack_btn.custom_minimum_size = Vector2(0, 42)
	_attack_btn.add_theme_font_override("font", FONT_HEAVY)
	_attack_btn.add_theme_font_size_override("font_size", 16)
	_attack_btn.add_theme_color_override("font_color", Color(1, 0.8, 0.4, 1))
	_attack_btn.pressed.connect(_on_attack_pressed)
	left.add_child(_attack_btn)

	# 中央战场
	_grid = InstanceGrid.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.custom_minimum_size = Vector2(660, 440)
	body.add_child(_grid)

	# 右侧信息
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(240, 560)
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	var info_head := Label.new()
	info_head.text = "战况信息"
	info_head.add_theme_font_override("font", FONT_BOLD)
	info_head.add_theme_font_size_override("font_size", 15)
	info_head.add_theme_color_override("font_color", Color(0.5, 0.8, 1, 0.95))
	right.add_child(info_head)
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_override("font", FONT_SERIF)
	_info_label.add_theme_font_size_override("font_size", 14)
	_info_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1, 0.95))
	right.add_child(_info_label)
	_result_label = Label.new()
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.add_theme_font_override("font", FONT_HEAVY)
	_result_label.add_theme_font_size_override("font_size", 15)
	right.add_child(_result_label)
	var hint := Label.new()
	hint.text = "玩法：\n🔍 搜索生成人机防御基地（难度递增）\n➤ 点击左侧设施出兵（消耗库存）\n⚔ 开始战斗：部队自动推进攻城\n✅ 胜利获得金币+科技奖励\n💥 战败部队损耗（无收获）\n\n参考部落冲突：有损耗也有收获，一般收获大于损耗"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_override("font", FONT_SERIF)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.55, 0.65, 0.8, 0.85))
	right.add_child(hint)

	_refresh_army_label()
	_info_label.text = "点击 🔍 搜索 生成目标基地"


# === 搜索 ===

func _on_search_pressed() -> void:
	if _battle_active:
		_info_label.text = "战斗进行中，无法搜索"
		return
	_difficulty += 1
	_army.clear()
	_refresh_army_label()
	_generate_enemy_base()
	_grid.enemy_placed = _enemy_placed
	_grid.army = _army
	_grid.queue_redraw()
	_result_label.text = ""
	_info_label.text = "已搜索到目标基地（第 %d 次搜索，难度 %d）\n点击左侧设施出兵后开始战斗" % [_difficulty, _difficulty]


func _generate_enemy_base() -> void:
	# 人机防御基地：按难度随机布局（城墙围边 + 炮塔/兵营/防空/避难所）
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Time.get_ticks_msec() * 31 + _difficulty * 977)
	_enemy_placed.clear()
	var occupied: Dictionary = {}
	# 城墙围边（左右两侧竖排）
	for y: int in range(GRID_H):
		for x: int in [0, GRID_W - 1]:
			if rng.randf() < 0.8:
				_enemy_placed["%d,%d" % [x, y]] = {
					"unit_id": "wall", "hp": 220, "max_hp": 220, "w": 1, "h": 1}
				occupied["%d,%d" % [x, y]] = true
	# 防御设施数量随难度递增
	var defs: Array[String] = ["turret", "turret", "barracks", "aa", "bunker"]
	var count: int = mini(12, 3 + _difficulty * 2)
	var placed: int = 0
	var guard: int = 0
	while placed < count and guard < 200:
		guard += 1
		var x: int = rng.randi_range(2, GRID_W - 4)
		var y: int = rng.randi_range(1, GRID_H - 3)
		var key: String = "%d,%d" % [x, y]
		if occupied.has(key):
			continue
		var unit_id: String = defs[rng.randi() % defs.size()]
		var unit: Dictionary = MilitarySystem.units_data.get(unit_id, {})
		var w: int = int(unit.get("width", 1))
		var h: int = int(unit.get("height", 1))
		# 简单冲突检测
		var clash: bool = false
		for dx: int in range(w):
			for dy: int in range(h):
				if occupied.has("%d,%d" % [x + dx, y + dy]):
					clash = true
		if clash:
			continue
		for dx: int in range(w):
			for dy: int in range(h):
				occupied["%d,%d" % [x + dx, y + dy]] = true
		_enemy_placed[key] = {
			"unit_id": unit_id, "hp": int(unit.get("hp", 100)),
			"max_hp": int(unit.get("hp", 100)), "w": w, "h": h}
		placed += 1


# === 出兵 ===

func _add_army(unit_id: String) -> void:
	if _battle_active:
		return
	if int(MilitarySystem.inventory.get(unit_id, 0)) <= 0:
		_info_label.text = "该设施库存不足，请先到军事界面制造"
		return
	MilitarySystem.inventory[unit_id] = int(MilitarySystem.inventory[unit_id]) - 1
	MilitarySystem.inventory_changed.emit()
	var unit: Dictionary = MilitarySystem.units_data[unit_id]
	_army.append({
		"unit_id": unit_id, "hp": float(unit.get("hp", 50)),
		"max_hp": float(unit.get("hp", 50)),
		"atk": float(unit.get("attack", 8)),
		"attack_type": unit.get("attack_type", "melee"),
		"range": float(unit.get("range", 26.0)),
	})
	_refresh_army_label()
	_info_label.text = "已出兵「%s」（剩余 %d 名部队）" % [unit.get("name", ""), _army.size()]


func _refresh_army_label() -> void:
	var parts: Array[String] = []
	var counts: Dictionary = {}
	for u in _army:
		counts[u["unit_id"]] = int(counts.get(u["unit_id"], 0)) + 1
	for unit_id: String in counts:
		parts.append("%s×%d" % [MilitarySystem.units_data.get(unit_id, {}).get("name", unit_id), counts[unit_id]])
	if parts.is_empty():
		_army_label.text = "出兵序列：空"
	else:
		_army_label.text = "出兵序列：%s（共 %d 名）" % [", ".join(parts), _army.size()]


# === 战斗 ===

func _on_attack_pressed() -> void:
	if _battle_active:
		return
	if _enemy_placed.is_empty():
		_info_label.text = "请先 🔍 搜索目标基地"
		return
	if _army.is_empty():
		_info_label.text = "请先出兵（左侧选择军事设施）"
		return
	_battle_active = true
	_settled = false
	_battle_timer = 0.0
	# 初始化单位位置（从战场左侧进入）
	var idx: int = 0
	for u in _army:
		u["pos"] = Vector2(30.0, 60.0 + float(idx) * 26.0)
		u["target"] = ""
		# 速度按兵种数据（远程慢、骑兵快）
		u["speed"] = float(MilitarySystem.units_data.get(u["unit_id"], {}).get("speed", 85.0))
		idx += 1
	_result_label.text = ""
	_info_label.text = "⚔ 战斗开始！部队正在推进..."
	_refresh_army_label()


func _process(delta: float) -> void:
	if not _battle_active:
		return
	_battle_timer += delta
	# 进攻单位推进 + 攻击
	var dead_units: Array[int] = []
	for i: int in range(_army.size()):
		var u: Dictionary = _army[i]
		# 寻找目标（最近的存活的防御设施）
		if str(u.get("target", "")) == "" or not _enemy_placed.has(u["target"]):
			u["target"] = _nearest_enemy(Vector2(u["pos"]))
			if u["target"] == "":
				# 没有目标：向基地中心推进
				u["pos"] = Vector2(u["pos"]) + Vector2(u["speed"], 0) * delta
				continue
		var target: Dictionary = _enemy_placed[u["target"]]
		var target_pos: Vector2 = _cell_center(u["target"])
		var pos: Vector2 = Vector2(u["pos"])
		var dist: float = pos.distance_to(target_pos)
		# 攻击距离：远程兵种（attack_type=ranged）在射程外停下攻击，近战贴近攻击
		var atk_range: float = float(u.get("range", 26.0)) if u.get("attack_type", "melee") == "ranged" else 26.0
		if dist > atk_range:
			pos += (target_pos - pos).normalized() * float(u["speed"]) * delta
			u["pos"] = pos
		else:
			# 攻击目标（5x 战斗节奏）
			target["hp"] = float(target["hp"]) - float(u["atk"]) * delta * 5.0
			if float(target["hp"]) <= 0.0:
				_enemy_placed.erase(u["target"])
				u["target"] = ""
	# 防御设施反击（攻击射程内最近的进攻单位）
	for key: String in _enemy_placed:
		var d: Dictionary = _enemy_placed[key]
		var unit: Dictionary = MilitarySystem.units_data.get(d["unit_id"], {})
		var atk: float = float(unit.get("attack", 0))
		if atk <= 0.0:
			continue
		var dpos: Vector2 = _cell_center(key)
		var best: int = -1
		var best_dist: float = 9999.0
		for i: int in range(_army.size()):
			var u: Dictionary = _army[i]
			var dist: float = dpos.distance_to(Vector2(u["pos"]))
			if dist < best_dist:
				best_dist = dist
				best = i
		# 防御设施按数据射程反击（ranged 远、wall 等无攻击自动跳过）
		var d_range: float = float(unit.get("range", 90.0))
		if best >= 0 and best_dist < d_range:
			_army[best]["hp"] = float(_army[best]["hp"]) - atk * delta * 5.0
	# 清理死亡单位
	var alive: Array[Dictionary] = []
	for u in _army:
		if float(u["hp"]) > 0.0:
			alive.append(u)
	_army = alive
	# 结束判定
	if _enemy_placed.is_empty():
		_settle_battle(true)
	elif _army.is_empty():
		_settle_battle(false)
	elif _battle_timer > 90.0:
		_settle_battle(false)
	_grid.enemy_placed = _enemy_placed
	_grid.army = _army
	_grid.queue_redraw()


func _nearest_enemy(pos: Vector2) -> String:
	var best_key: String = ""
	var best_dist: float = 99999.0
	for key: String in _enemy_placed:
		var dist: float = pos.distance_to(_cell_center(key))
		if dist < best_dist:
			best_dist = dist
			best_key = key
	return best_key


func _cell_center(key: String) -> Vector2:
	var parts: PackedStringArray = key.split(",")
	var gx: int = int(parts[0])
	var gy: int = int(parts[1])
	var grid_px: Vector2 = Vector2(GRID_W, GRID_H) * CELL
	var origin: Vector2 = Vector2((_grid.size.x - grid_px.x) / 2.0, (_grid.size.y - grid_px.y) / 2.0)
	return origin + Vector2(gx * CELL + CELL / 2.0, gy * CELL + CELL / 2.0)


func _settle_battle(victory: bool) -> void:
	_battle_active = false
	_settled = true
	if victory:
		var gold: int = 120 + _difficulty * 80 + _army.size() * 15
		var tech: int = 10 + _difficulty * 8
		GameState.add_gold(gold)
		GameState.add_tech(tech)
		_result_label.text = "✅ 攻城胜利！\n收获：金币 +%d · 科技 +%d\n（部队损耗 %d 名）" % [gold, tech, _difficulty + 2]
		_info_label.text = "胜利结算完成，可继续搜索更高难度目标"
	else:
		_result_label.text = "💥 攻城失败！\n部队全部损耗（无收获）\n提示：多制造设施、堆出兵数量"
		_info_label.text = "战败结算：部队已损耗，请回军事界面补充"
	_refresh_army_label()


# ================= 战场网格（内部类） =================

class InstanceGrid:
	extends Control

	## 副本战场：绘制 AI 防御基地与进攻单位，战斗动画帧驱动。

	const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")

	var enemy_placed: Dictionary = {}  # 父类同步的敌军设施
	var army: Array = []              # 父类同步的进攻单位

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var grid_px: Vector2 = Vector2(GRID_W, GRID_H) * CELL
		var origin: Vector2 = Vector2((size.x - grid_px.x) / 2.0, (size.y - grid_px.y) / 2.0)
		draw_rect(Rect2(origin, grid_px), Color(0.03, 0.06, 0.12, 0.92))
		for x: int in range(GRID_W):
			for y: int in range(GRID_H):
				draw_rect(Rect2(origin + Vector2(x, y) * CELL, Vector2(CELL, CELL)),
						Color(0.05, 0.1, 0.2, 0.5), false, 1.0)
		# 敌军设施
		for key: String in enemy_placed:
			var d: Dictionary = enemy_placed[key]
			var parts: PackedStringArray = key.split(",")
			var gx: int = int(parts[0])
			var gy: int = int(parts[1])
			var rect := Rect2(origin + Vector2(gx, gy) * CELL, Vector2(int(d["w"]) * CELL, int(d["h"]) * CELL))
			var c: Color = _enemy_color(d["unit_id"])
			draw_rect(Rect2(rect.position + Vector2(2, 3), rect.size), Color(0, 0, 0, 0.35))
			draw_rect(rect, c.darkened(0.5))
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.8)), c.lightened(0.1))
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.8)), c.lightened(0.5), false, 2.0)
			# 血量条
			var hp_ratio: float = float(d["hp"]) / float(d["max_hp"])
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 4)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(rect.position, Vector2(rect.size.x * hp_ratio, 4)), Color(0.9, 0.3, 0.3, 0.95))
			draw_string(FONT_BOLD, rect.position + Vector2(5, rect.size.y * 0.55),
					MilitarySystem.units_data.get(d["unit_id"], {}).get("name", "?"),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.95))
		# 进攻单位
		for u in army:
			var pos: Vector2 = Vector2(u["pos"])
			draw_circle(pos, 8.0, Color(0.4, 0.9, 1, 0.95))
			draw_circle(pos, 5.0, Color(1, 0.95, 0.8, 1.0))
			# 血量
			var hp_ratio: float = float(u["hp"]) / float(u["max_hp"])
			draw_rect(Rect2(pos + Vector2(-8, -14), Vector2(16, 3)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(pos + Vector2(-8, -14), Vector2(16 * hp_ratio, 3)), Color(0.4, 1, 0.6, 0.95))

	func _enemy_color(unit_id: String) -> Color:
		match unit_id:
			"turret": return Color(0.85, 0.3, 0.28)
			"wall": return Color(0.5, 0.52, 0.58)
			"barracks": return Color(0.75, 0.5, 0.2)
			"aa": return Color(0.8, 0.55, 0.25)
			"bunker": return Color(0.45, 0.7, 0.6)
			_: return Color(0.5, 0.6, 0.8)
