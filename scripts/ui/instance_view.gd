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


# ================= 战场网格（内部类，3D 化） =================

class InstanceGrid:
	extends Control

	## 副本战场 3D 化：SubViewport + Node3D + Camera3D + 光照，
	## 敌方设施与进攻单位均由 MilitaryMeshes.build_unit_model（冻结契约，只读）生成；
	## 战斗推进由父类在 2D 像素空间完成，本类负责换算到 3D 并驱动弹幕动画。
	## 对外接口：enemy_placed / army 属性由父类同步（仅坐标换算到 3D，战斗模拟在父类像素空间）。
	## 注意：设施/单位模型经 MilitaryMeshes 契约生成（只读，来自 res://scripts/ui/military_meshes.gd）。

	const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")

	# --- 3D 世界参数（每格为 CELL3D 世界单位；父类像素坐标按 CELL3D/CELL 等比映射） ---
	const CELL3D: float = 4.0          # 3D 世界单元尺寸(世界单位/格)
	const CAM_DIST: float = 68.0       # 摄像机到目标距离(世界单位)
	const CAM_PITCH: float = 0.6       # 俯视俯角(弧度)
	const CAM_YAW_INIT: float = -0.7   # 初始轨道方位角(弧度)
	const CAM_YAW_SPEED: float = 0.05  # 战斗时轨道旋转角速度(弧度/秒)
	const PROJ_FLIGHT: float = 0.4     # 弹幕飞行时间(秒)
	const PROJ_INTERVAL: float = 0.4   # 单个单位/设施的发射间隔(秒)

	# 父类同步的战场数据（接口不变）
	var enemy_placed: Dictionary = {}
	var army: Array = []

	# === 3D 节点 ===
	var _viewport: SubViewport
	var _container: SubViewportContainer
	var _world: Node3D
	var _camera: Camera3D
	var _ground_root: Node3D
	var _unit_root: Node3D     # 敌方设施模型挂点
	var _army_root: Node3D     # 进攻单位模型挂点
	var _proj_root: Node3D     # 弹幕/特效挂点

	# === 摄像机状态 ===
	var _yaw: float = CAM_YAW_INIT
	var _cam_target: Vector3 = Vector3.ZERO

	# === 运行时状态 ===
	var _enemy_node_map: Dictionary = {}   # key -> {root, fill, width, pos}
	var _army_node_map: Dictionary = {}    # gid -> {root, fill, width, pos}
	var _army_gid_count: int = 0
	var _fire_army: Dictionary = {}        # gid -> 发射冷却
	var _fire_enemy: Dictionary = {}       # key -> 发射冷却
	var _projectiles: Array[Dictionary] = []
	var _particles: Array[Dictionary] = []


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)  # 明确开启逐帧处理(同步单位位置/弹幕/摄像机)
		_build_3d_world()


	func _process(delta: float) -> void:
		_update_viewport_size()  # 每帧同步子视口分辨率(父级缩放变化不触发 TRANSFORM_CHANGED，轮询最可靠)
		_sync_enemy_models()
		_sync_army_models()
		_fire_projectiles(delta)
		_tick_projectiles(delta)
		_tick_particles(delta)
		_update_camera_orbit(delta)


	func _notification(what: int) -> void:
		# 控件尺寸/全局缩放变化 → 同步子视口分辨率(防 3D 画面拉伸模糊)
		if what == NOTIFICATION_RESIZED or what == NOTIFICATION_TRANSFORM_CHANGED:
			_update_viewport_size()


	# === 3D 世界构建 ===

	func _build_3d_world() -> void:
		# 子视口容器：锚点左上角，尺寸/缩放由 _update_viewport_size 手动管理(同 grid_view)
		_container = SubViewportContainer.new()
		_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_container.position = Vector2.ZERO
		_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_container.stretch = false  # stretch=true 时容器强制子视口=容器尺寸，无法手动提高渲染分辨率
		add_child(_container)
		_viewport = SubViewport.new()
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_viewport.transparent_bg = false  # 不透明背景，避免 3D 世界外透出下方 2D 界面
		_viewport.size = _physical_size()
		_container.add_child(_viewport)
		set_notify_transform(true)
		_world = Node3D.new()
		_world.name = "InstanceWorld3D"
		_viewport.add_child(_world)
		# 光照：主光 + 补光 + 环境(深蓝战场夜空)
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.rotation_degrees = Vector3(-52, -38, 0)
		sun.light_energy = 1.1
		sun.light_color = Color(1.0, 0.96, 0.9)
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 300.0
		_world.add_child(sun)
		var fill := DirectionalLight3D.new()
		fill.name = "Fill"
		fill.rotation_degrees = Vector3(-30, 130, 0)
		fill.light_energy = 0.4
		fill.light_color = Color(0.6, 0.75, 1.0)
		_world.add_child(fill)
		var env := WorldEnvironment.new()
		var sky := Environment.new()
		sky.background_mode = Environment.BG_COLOR
		sky.background_color = Color(0.02, 0.05, 0.12)
		sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		sky.ambient_light_color = Color(0.5, 0.62, 0.9)
		sky.ambient_light_energy = 0.7
		env.environment = sky
		_world.add_child(env)
		# 挂点根节点
		_ground_root = Node3D.new()
		_ground_root.name = "Ground"
		_world.add_child(_ground_root)
		_unit_root = Node3D.new()
		_unit_root.name = "EnemyUnits"
		_world.add_child(_unit_root)
		_army_root = Node3D.new()
		_army_root.name = "ArmyUnits"
		_world.add_child(_army_root)
		_proj_root = Node3D.new()
		_proj_root.name = "Projectiles"
		_world.add_child(_proj_root)
		# 摄像机：轻微俯视轨道(注视网格中心)
		_camera = Camera3D.new()
		_camera.fov = 45.0
		_camera.near = 0.5
		_camera.far = 2000.0
		_world.add_child(_camera)
		_cam_target = _grid_center_world()
		_update_camera()
		_build_ground()


	func _build_ground() -> void:
		for child: Node in _ground_root.get_children():
			child.queue_free()
		# 地面：逐格 4 顶点四边形，顶点色区分深蓝基地地面(边缘一圈带红调 = 敌军领地感)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var vc: int = 0
		for x: int in range(GRID_W):
			for y: int in range(GRID_H):
				st.set_color(_ground_color(x, y))
				var x0: float = x * CELL3D
				var x1: float = (x + 1) * CELL3D
				var z0: float = y * CELL3D
				var z1: float = (y + 1) * CELL3D
				st.add_vertex(Vector3(x0, 0.0, z0))
				st.add_vertex(Vector3(x1, 0.0, z0))
				st.add_vertex(Vector3(x1, 0.0, z1))
				st.add_vertex(Vector3(x0, 0.0, z1))
				st.add_index(vc)
				st.add_index(vc + 1)
				st.add_index(vc + 2)
				st.add_index(vc)
				st.add_index(vc + 2)
				st.add_index(vc + 3)
				vc += 4
		var ground := MeshInstance3D.new()
		ground.mesh = st.commit()
		var gmat := StandardMaterial3D.new()
		gmat.vertex_color_use_as_albedo = true
		gmat.roughness = 0.85
		gmat.metallic = 0.0
		ground.material_override = gmat
		_ground_root.add_child(ground)
		# 网格线(俯视可辨格的半透明蓝线)
		var lines := ImmediateMesh.new()
		var lc := Color(0.35, 0.5, 0.85, 0.35)
		lines.surface_begin(Mesh.PRIMITIVE_LINES)
		for x: int in range(GRID_W + 1):
			for zseg: int in range(GRID_H):
				lines.surface_set_color(lc)
				lines.surface_add_vertex(Vector3(x * CELL3D, 0.02, zseg * CELL3D))
				lines.surface_add_vertex(Vector3(x * CELL3D, 0.02, (zseg + 1) * CELL3D))
		for y: int in range(GRID_H + 1):
			for xseg: int in range(GRID_W):
				lines.surface_set_color(lc)
				lines.surface_add_vertex(Vector3(xseg * CELL3D, 0.02, y * CELL3D))
				lines.surface_add_vertex(Vector3((xseg + 1) * CELL3D, 0.02, y * CELL3D))
		lines.surface_end()
		var line_mesh := MeshInstance3D.new()
		line_mesh.mesh = lines
		var lmat := StandardMaterial3D.new()
		lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lmat.vertex_color_use_as_albedo = true
		line_mesh.material_override = lmat
		_ground_root.add_child(line_mesh)


	func _ground_color(x: int, y: int) -> Color:
		# 确定性种子：随机色阶但每次重建一致(不闪烁)；基地地面深蓝，边缘一圈带红调
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260815 + x * 73856093 + y * 19349663
		var t: float = rng.randf_range(0.85, 1.0)
		var col: Color = Color(0.05, 0.1, 0.2).lerp(Color(0.09, 0.17, 0.3), t)
		var edge: bool = x == 0 or x == GRID_W - 1 or y == 0 or y == GRID_H - 1
		if edge:
			col = col.lerp(Color(0.42, 0.12, 0.12), 0.45)
		return col


	func _grid_center_world() -> Vector3:
		return Vector3(GRID_W * CELL3D * 0.5, 0.0, GRID_H * CELL3D * 0.5)


	func _update_camera() -> void:
		# 轨道式轻微俯视：以网格中心为注视点，方位角 _yaw + 俯角 CAM_PITCH 绕行
		var horiz: float = cos(CAM_PITCH) * CAM_DIST
		var pos := _cam_target + Vector3(cos(_yaw) * horiz, sin(CAM_PITCH) * CAM_DIST, sin(_yaw) * horiz)
		_camera.position = pos
		_camera.look_at(_cam_target, Vector3.UP)


	func _update_camera_orbit(delta: float) -> void:
		# 战斗进行中(既搜寻到目标又已出兵)缓慢轨道旋转，营造轻微俯视轨道感；其余时间静止
		if not enemy_placed.is_empty() and not army.is_empty():
			_yaw += CAM_YAW_SPEED * delta
		_update_camera()


	# === 子视口分辨率(同 grid_view：渲染分辨率=布局×缩放×超采样，显示时按 1/factor 反向缩放) ===

	func _physical_size() -> Vector2i:
		var factor: float = 1.0
		if WindowManager.has_method("current_scale_factor"):
			factor = WindowManager.current_scale_factor()
		var ss: float = 1.0
		if WindowManager.has_method("supersample_factor"):
			ss = WindowManager.supersample_factor()
		return Vector2i(maxi(64, int(size.x * factor * ss)), maxi(64, int(size.y * factor * ss)))


	func _update_viewport_size() -> void:
		if _viewport == null or _container == null:
			return
		var target: Vector2i = _physical_size()
		if target != _viewport.size:
			_viewport.size = target
			_container.size = Vector2(target)
		var factor: float = 1.0
		if WindowManager.has_method("current_scale_factor"):
			factor = WindowManager.current_scale_factor()
		var ss: float = 1.0
		if WindowManager.has_method("supersample_factor"):
			ss = WindowManager.supersample_factor()
		var inv: Vector2 = Vector2(1.0 / (factor * ss), 1.0 / (factor * ss))
		if _container.scale != inv:
			_container.scale = inv


	# === 像素→3D 世界换算工具 ===

	func _origin_px() -> Vector2:
		var grid_px: Vector2 = Vector2(GRID_W, GRID_H) * CELL
		return Vector2((size.x - grid_px.x) / 2.0, (size.y - grid_px.y) / 2.0)


	func _cell_footprint_px_center(key: String) -> Vector2:
		# 设施覆盖区域(锚点 + 占地 w×h)的像素中心；单格时与父类 _cell_center 一致
		var parts: PackedStringArray = key.split(",")
		var gx: int = int(parts[0])
		var gy: int = int(parts[1])
		var d: Dictionary = enemy_placed[key]
		var w: float = float(d.get("w", 1))
		var h: float = float(d.get("h", 1))
		return _origin_px() + Vector2((gx + w * 0.5) * CELL, (gy + h * 0.5) * CELL)


	func _px_to_world3(px: Vector2) -> Vector3:
		# 父类像素坐标 -> 3D 世界：比例 CELL3D/CELL，Y 为地面高度 0
		var origin: Vector2 = _origin_px()
		return Vector3((px.x - origin.x) / CELL * CELL3D, 0.0, (px.y - origin.y) / CELL * CELL3D)


	func _cell_footprint_center(gx: int, gy: int, w: int, h: int) -> Vector3:
		return Vector3((gx + float(w) * 0.5) * CELL3D, 0.0, (gy + float(h) * 0.5) * CELL3D)


	# === 敌方设施模型同步 ===

	func _sync_enemy_models() -> void:
		var wanted: Dictionary = {}
		for key: String in enemy_placed:
			if _ensure_enemy_model(key):
				wanted[key] = true
		var to_remove: Array[String] = []
		for key: String in _enemy_node_map:
			if not wanted.has(key):
				to_remove.append(key)
		for key: String in to_remove:
			var info: Dictionary = _enemy_node_map[key]
			_spawn_hit_sparks(Vector3(info.get("pos", _grid_center_world())), Color(1.0, 0.5, 0.25))
			(info["root"] as Node).queue_free()
			_enemy_node_map.erase(key)
			_fire_enemy.erase(key)


	func _ensure_enemy_model(key: String) -> bool:
		var info: Dictionary = _enemy_node_map.get(key, {})
		if not info.is_empty():
			_update_enemy_bar(key)
			return true
		var d: Dictionary = enemy_placed[key]
		var parts: PackedStringArray = key.split(",")
		var gx: int = int(parts[0])
		var gy: int = int(parts[1])
		var w: int = int(d.get("w", 1))
		var h: int = int(d.get("h", 1))
		var model: Node3D = MilitaryMeshes.build_unit_model(d["unit_id"], CELL3D, 1)
		var root := Node3D.new()
		root.name = "Enemy_" + key
		root.position = _cell_footprint_center(gx, gy, w, h)
		# 多格设施(兵营 2×2/避难所 2×2)按占地缩放，使模型铺满 footprint
		var fs: float = float(maxi(w, h))
		root.scale = Vector3(fs, fs, fs)
		root.add_child(model)
		var bar: Dictionary = _make_hp_bar(CELL3D * 0.9, CELL3D * 0.12, Color(0.9, 0.3, 0.3))
		var barnode: MeshInstance3D = bar["bg"]
		barnode.position = Vector3(0, CELL3D * 1.7, 0)
		root.add_child(barnode)
		var label := Label3D.new()
		label.text = str(MilitarySystem.units_data.get(d["unit_id"], {}).get("name", "?"))
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 18
		label.pixel_size = 0.006
		label.outline_size = 3
		label.outline_modulate = Color(0, 0, 0, 0.85)
		label.position = Vector3(0, CELL3D * 2.0, 0)
		root.add_child(label)
		_unit_root.add_child(root)
		info = {"root": root, "fill": bar["fill"], "width": bar["width"], "pos": root.position}
		_enemy_node_map[key] = info
		_update_enemy_bar(key)
		return true


	func _update_enemy_bar(key: String) -> void:
		var info: Dictionary = _enemy_node_map[key]
		var d: Dictionary = enemy_placed[key]
		var ratio: float = clampf(float(d["hp"]) / maxf(float(d["max_hp"]), 0.001), 0.0, 1.0)
		_set_hp_ratio(info, ratio)


	# === 进攻单位模型同步 ===

	func _sync_army_models() -> void:
		var seen: Dictionary = {}
		for u in army:
			var gid: int = _ensure_army_gid(u)
			seen[gid] = true
			var info: Dictionary = _army_node_map[gid]
			# 出兵后战斗未开始时单位还没有 pos 键（战斗开始才初始化），防御性取默认原点
			var wp: Vector3 = _px_to_world3(Vector2(u.get("pos", Vector2.ZERO)))
			(info["root"] as Node3D).position = wp
			info["pos"] = wp
			var ratio: float = clampf(float(u["hp"]) / maxf(float(u["max_hp"]), 0.001), 0.0, 1.0)
			_set_hp_ratio(info, ratio)
		var to_remove: Array[int] = []
		for gid: int in _army_node_map:
			if not seen.has(gid):
				to_remove.append(gid)
		for gid: int in to_remove:
			var info: Dictionary = _army_node_map[gid]
			_spawn_hit_sparks(Vector3(info.get("pos", _grid_center_world())), Color(1.0, 0.9, 0.4))
			(info["root"] as Node).queue_free()
			_army_node_map.erase(gid)
			_fire_army.erase(gid)


	func _ensure_army_gid(u: Dictionary) -> int:
		# 用自增 gid 标识每个出兵记录：父类重建数组时幸存记录字典引用不变，gid 稳定可追踪
		var gid: int = int(u.get("_gid", 0))
		if gid != 0 and _army_node_map.has(gid):
			return gid
		_army_gid_count += 1
		gid = _army_gid_count
		u["_gid"] = gid
		var root := Node3D.new()
		root.name = "Army_%d" % gid
		var model: Node3D = MilitaryMeshes.build_unit_model(str(u["unit_id"]), CELL3D, 1)
		root.add_child(model)
		var bar: Dictionary = _make_hp_bar(CELL3D * 0.7, CELL3D * 0.1, Color(0.4, 1.0, 0.6))
		var barnode: MeshInstance3D = bar["bg"]
		barnode.position = Vector3(0, CELL3D * 1.4, 0)
		root.add_child(barnode)
		_army_root.add_child(root)
		_army_node_map[gid] = {"root": root, "fill": bar["fill"], "width": bar["width"],
				"pos": _px_to_world3(Vector2(u.get("pos", Vector2.ZERO)))}
		return gid


	# === 血量条(背景 + 按比例缩放的填充) ===

	func _make_hp_bar(width: float, height: float, color: Color) -> Dictionary:
		var bg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(width, height, height * 1.2)
		bg.mesh = bm
		var bmat := StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.albedo_color = Color(0, 0, 0, 0.7)
		bg.material_override = bmat
		var fill := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(width, height, height * 1.2)
		fill.mesh = fm
		var fmat := StandardMaterial3D.new()
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fmat.albedo_color = color
		fill.material_override = fmat
		fill.position.z = 0.02  # 稍前移避免与背景 z-fighting
		bg.add_child(fill)
		return {"bg": bg, "fill": fill, "width": width}


	func _set_hp_ratio(info: Dictionary, ratio: float) -> void:
		# 填充从左端向右按比例缩放(原点平移到左缘)：fill.scale.x + fill.position.x 组合实现左对齐
		var fill: MeshInstance3D = info["fill"]
		var width: float = info["width"]
		var r: float = clampf(ratio, 0.001, 1.0)
		fill.scale.x = r
		fill.position.x = -width * (1.0 - r) * 0.5


	# === 远程弹幕攻击(攻防双方，视觉抛物线弹道) ===

	func _fire_projectiles(delta: float) -> void:
		# 距离判定沿用父类像素空间(与伤害 tick 对齐)；仅远程(attack_type=ranged)发射弹幕
		for u in army:
			if str(u.get("attack_type", "melee")) != "ranged":
				continue
			var tk: String = str(u.get("target", ""))
			if tk == "" or not enemy_placed.has(tk):
				continue
			var pos_px: Vector2 = Vector2(u["pos"])
			var target_px: Vector2 = _cell_footprint_px_center(tk)
			var atk_range: float = float(u.get("range", 26.0))
			if pos_px.distance_to(target_px) > atk_range:
				continue
			var gid: int = int(u.get("_gid", 0))
			if gid == 0:
				continue
			if float(_fire_army.get(gid, 0.0)) > 0.0:
				continue
			_fire_army[gid] = PROJ_INTERVAL
			_spawn_projectile(str(u["unit_id"]), _px_to_world3(pos_px), _px_to_world3(target_px), -1)
		# 防御方远程设施(turret/aa)在射程内反击
		for key: String in enemy_placed:
			var d: Dictionary = enemy_placed[key]
			var unit: Dictionary = MilitarySystem.units_data.get(d["unit_id"], {})
			if str(unit.get("attack_type", "melee")) != "ranged":
				continue
			if float(unit.get("attack", 0)) <= 0.0:
				continue
			var dpos_px: Vector2 = _cell_footprint_px_center(key)
			var d_range: float = float(unit.get("range", 90.0))
			var best: int = -1
			var best_dist: float = 1e9
			for i: int in range(army.size()):
				var u: Dictionary = army[i]
				var dist: float = dpos_px.distance_to(Vector2(u["pos"]))
				if dist < best_dist:
					best_dist = dist
					best = i
			if best < 0 or best_dist > d_range:
				continue
			if float(_fire_enemy.get(key, 0.0)) > 0.0:
				continue
			_fire_enemy[key] = PROJ_INTERVAL
			var tu: Dictionary = army[best]
			# 防御弹幕追踪目标单位(进攻单位在移动)，命中更准
			_spawn_projectile(str(d["unit_id"]), _px_to_world3(dpos_px), _px_to_world3(Vector2(tu["pos"])), int(tu.get("_gid", -1)))
		# 冷却递减
		for gid: int in _fire_army:
			_fire_army[gid] = maxf(0.0, float(_fire_army[gid]) - delta)
		for key: String in _fire_enemy:
			_fire_enemy[key] = maxf(0.0, float(_fire_enemy[key]) - delta)


	func _spawn_projectile(unit_id: String, from: Vector3, to: Vector3, track_gid: int = -1) -> void:
		var kind: String
		var color: Color
		match unit_id:
			"archer":
				kind = "arrow"
				color = Color(0.75, 0.6, 0.35)
			"catapult":
				kind = "stone"
				color = Color(0.4, 0.4, 0.45)
			"turret":
				kind = "shell"
				color = Color(1.0, 0.6, 0.25)
			"aa":
				kind = "missile"
				color = Color(0.9, 0.35, 0.3)
			_:
				kind = "stone"
				color = Color(0.8, 0.8, 0.85)
		var launch: Vector3 = from + Vector3(0, CELL3D * 0.8, 0)
		var target: Vector3 = to + Vector3(0, CELL3D * 0.5, 0)
		var node: MeshInstance3D = _make_projectile_mesh(kind, color)
		node.position = launch
		# 初始朝飞行方向(仅设一次，避免逐帧重算切线抖动)
		var dir: Vector3 = (target - launch).normalized()
		if dir.length() > 0.001:
			node.look_at(launch + dir, Vector3.UP)
		_proj_root.add_child(node)
		var dist: float = (target - launch).length()
		var arc: float = clampf(dist * 0.15, CELL3D * 0.4, CELL3D * 2.2)
		_projectiles.append({"node": node, "from": launch, "to": target, "t": 0.0,
				"dur": PROJ_FLIGHT, "arc": arc, "kind": kind, "color": color,
				"track_gid": track_gid, "prev": Vector3.ZERO})


	func _make_projectile_mesh(kind: String, color: Color) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		if kind == "stone":
			var sm := SphereMesh.new()
			sm.radius = CELL3D * 0.14
			sm.height = CELL3D * 0.28
			mi.mesh = sm
		else:
			# 箭矢/炮弹/导弹：沿 Z 轴细长盒，便于 look_at 朝向飞行方向
			var bm := BoxMesh.new()
			bm.size = Vector3(CELL3D * 0.07, CELL3D * 0.07, CELL3D * 0.9)
			mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.4
		mi.material_override = mat
		return mi


	func _tick_projectiles(delta: float) -> void:
		var done: Array[int] = []
		for i: int in range(_projectiles.size()):
			var p: Dictionary = _projectiles[i]
			# 追踪弹幕：每帧把命中点更新为目标的当前世界坐标(防御弹打移动部队)
			var tg: int = int(p.get("track_gid", -1))
			if tg >= 0 and _army_node_map.has(tg):
				var ti: Dictionary = _army_node_map[tg]
				p["to"] = Vector3(ti["pos"]) + Vector3(0, CELL3D * 0.5, 0)
			p["t"] = float(p["t"]) + delta / PROJ_FLIGHT
			var t: float = minf(float(p["t"]), 1.0)
			var pos: Vector3 = _parabola(Vector3(p["from"]), Vector3(p["to"]), float(p["arc"]), t)
			var node: Node3D = p["node"]
			node.position = pos
			if t >= 1.0:
				_spawn_hit_sparks(pos, Color(p["color"]))
				node.queue_free()
				done.append(i)
		for i: int in range(done.size()):
			var idx: int = int(done[done.size() - 1 - i])
			_projectiles.remove_at(idx)


	func _parabola(from: Vector3, to: Vector3, arc: float, t: float) -> Vector3:
		# 抛物线：直线插值 + 顶点处 sin(t*PI) 抬升(落地回到 to)
		var base: Vector3 = from.lerp(to, t)
		return base + Vector3(0, arc * sin(t * PI), 0)


	# === 命中/死亡火花粒子 ===

	func _spawn_hit_sparks(pos: Vector3, color: Color) -> void:
		for i: int in range(8):
			var ang: float = randf() * TAU
			_spawn_particle(pos, Vector3(cos(ang) * randf_range(8, 22), randf_range(4, 14), sin(ang) * randf_range(8, 22)),
					color, CELL3D * 0.05, 0.45)


	func _spawn_particle(pos: Vector3, vel: Vector3, color: Color, size: float, life: float) -> void:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = size
		sm.height = size * 2.0
		mi.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mi.material_override = mat
		mi.position = pos
		_proj_root.add_child(mi)
		_particles.append({"node": mi, "vel": vel, "life": life, "max_life": life})


	func _tick_particles(delta: float) -> void:
		var done: Array[int] = []
		for i: int in range(_particles.size()):
			var pt: Dictionary = _particles[i]
			pt["life"] = float(pt["life"]) - delta
			var node: MeshInstance3D = pt["node"]
			node.position = node.position + Vector3(pt["vel"]) * delta
			var a: float = clampf(float(pt["life"]) / maxf(float(pt["max_life"]), 0.001), 0.0, 1.0)
			(node.material_override as StandardMaterial3D).albedo_color.a = a
			if float(pt["life"]) <= 0.0:
				done.append(i)
		for i: int in range(done.size()):
			var idx: int = int(done[done.size() - 1 - i])
			(_particles[idx]["node"] as Node).queue_free()
			_particles.remove_at(idx)
