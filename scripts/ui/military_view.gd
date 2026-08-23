extends Control

## 军事与防御界面：右上角军事/防御切换，默认军事。
## 军事页：消耗金币+科技点制造军事设施（进入库存）。
## 防御页：军事基地网格建设，从库存部署设施，可扩大基地；军事规模达标后人机攻城。
## 设计依据：docs/design/game_design.md 3.12

const FONT_HEAVY: Font = preload("res://assets/fonts/SourceHanSansCN-Heavy.ttf")
const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")
const FONT_SERIF: Font = preload("res://assets/fonts/SourceHanSerifCN-Regular.otf")

var _current_page: String = "military"  # military / defense
var _selected_unit: String = ""          # 防御页选中的库存设施 id
var _info_label: Label
var _inventory_box: VBoxContainer
var _base_grid: MilitaryBaseGrid
var _military_panel: VBoxContainer
var _defense_panel: VBoxContainer


func _ready() -> void:
	WindowManager.setup_scale_root(self)
	_build_ui()
	MilitarySystem.inventory_changed.connect(_refresh_inventory)
	# 防御页库存按钮随库存变化实时刷新（拖动批量部署时数字同步）
	MilitarySystem.inventory_changed.connect(func() -> void:
		if _current_page == "defense":
			_refresh_defense_panel())
	MilitarySystem.base_changed.connect(func(_c: Vector2i) -> void: _refresh_base_info())
	MilitarySystem.siege_triggered.connect(func(wave: int, power: int) -> void:
		_info_label.text = "⚔ 人机攻城来袭！第 %d 波（战力 %d）" % [wave, power])
	MilitarySystem.siege_resolved.connect(func(victory: bool, destroyed: int) -> void:
		if victory:
			_info_label.text = "🛡 成功击退攻城！获得奖励"
		else:
			_info_label.text = "💥 基地被攻破，损失 %d 个设施" % destroyed)
	_switch_page("military")


func _build_ui() -> void:
	# 科幻渐变背景（深蓝星空感）
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

	# 顶部资源栏（全局资源可见，同主界面顶栏信息）
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
	title.text = "⚔ 军事与防御"
	title.add_theme_font_override("font", FONT_HEAVY)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.4, 0.82, 1, 1))
	top.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var btn_military := Button.new()
	btn_military.text = "军事"
	btn_military.custom_minimum_size = Vector2(96, 38)
	btn_military.add_theme_font_override("font", FONT_BOLD)
	btn_military.add_theme_font_size_override("font_size", 15)
	btn_military.pressed.connect(func() -> void: _switch_page("military"))
	top.add_child(btn_military)
	var btn_defense := Button.new()
	btn_defense.text = "防御"
	btn_defense.custom_minimum_size = Vector2(96, 38)
	btn_defense.add_theme_font_override("font", FONT_BOLD)
	btn_defense.add_theme_font_size_override("font_size", 15)
	btn_defense.pressed.connect(func() -> void: _switch_page("defense"))
	top.add_child(btn_defense)
	var btn_back := Button.new()
	btn_back.text = "返回主界面"
	btn_back.custom_minimum_size = Vector2(130, 38)
	btn_back.add_theme_font_override("font", FONT_BOLD)
	btn_back.add_theme_font_size_override("font_size", 14)
	btn_back.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/ui/main_ui.tscn"))
	top.add_child(btn_back)

	# 内容区
	var content := HBoxContainer.new()
	content.position = Vector2(16, 112)
	content.custom_minimum_size = Vector2(1248, 540)
	content.add_theme_constant_override("separation", 14)
	add_child(content)

	# 左：军事页（制造列表）/ 防御页（库存列表）
	_military_panel = VBoxContainer.new()
	_military_panel.custom_minimum_size = Vector2(380, 560)
	_military_panel.add_theme_constant_override("separation", 8)
	content.add_child(_military_panel)
	_defense_panel = VBoxContainer.new()
	_defense_panel.custom_minimum_size = Vector2(380, 560)
	_defense_panel.add_theme_constant_override("separation", 8)
	content.add_child(_defense_panel)

	# 右：基地网格 / 信息
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	content.add_child(right)

	_base_grid = MilitaryBaseGrid.new()
	_base_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_base_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_base_grid.custom_minimum_size = Vector2(600, 420)
	_base_grid.unit_selected.connect(func(unit_id: String) -> void:
		_selected_unit = unit_id
		_base_grid.selected_unit = unit_id
		_refresh_defense_panel())
	_base_grid.remove_requested.connect(func(cell: Vector2i) -> void:
		MilitarySystem.remove_unit(cell))
	_base_grid.upgrade_requested.connect(_on_base_upgrade_requested)
	_base_grid.place_requested.connect(func(cell: Vector2i) -> void:
		# 部署选中设施到基地（从库存扣减）
		if _selected_unit.is_empty():
			return
		if MilitarySystem.place_unit(_selected_unit, cell):
			_info_label.text = "已部署设施到基地"
		else:
			_info_label.text = "部署失败：库存不足或位置不可用")
	right.add_child(_base_grid)

	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size = Vector2(0, 60)
	_info_label.add_theme_font_override("font", FONT_SERIF)
	_info_label.add_theme_font_size_override("font_size", 14)
	_info_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1, 0.95))
	right.add_child(_info_label)


func _switch_page(page: String) -> void:
	_current_page = page
	_military_panel.visible = (page == "military")
	_defense_panel.visible = (page == "defense")
	_base_grid.edit_mode = (page == "defense")
	if page == "military":
		_build_military_page()
	else:
		_refresh_defense_panel()


# === 军事页：制造 ===

func _build_military_page() -> void:
	for child: Node in _military_panel.get_children():
		child.queue_free()
	var head := Label.new()
	head.text = "制造军事设施（消耗金币 + 科技点）"
	head.add_theme_font_override("font", FONT_BOLD)
	head.add_theme_font_size_override("font_size", 16)
	head.add_theme_color_override("font_color", Color(0.5, 0.8, 1, 0.95))
	_military_panel.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_military_panel.add_child(scroll)
	_inventory_box = VBoxContainer.new()
	_inventory_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_inventory_box)
	_refresh_inventory()


func _refresh_inventory() -> void:
	if _inventory_box == null:
		return
	for child: Node in _inventory_box.get_children():
		child.queue_free()
	for unit_id: String in MilitarySystem.units_data:
		var unit: Dictionary = MilitarySystem.units_data[unit_id]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _make_card_style())
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("margin_left", 12)
		vbox.add_theme_constant_override("margin_right", 12)
		vbox.add_theme_constant_override("margin_top", 8)
		vbox.add_theme_constant_override("margin_bottom", 8)
		vbox.add_theme_constant_override("separation", 4)
		card.add_child(vbox)
		var name_label := Label.new()
		name_label.text = "%s · 库存 %d" % [unit.get("name", ""), int(MilitarySystem.inventory.get(unit_id, 0))]
		name_label.add_theme_font_override("font", FONT_BOLD)
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", Color(1, 0.85, 0.5, 1))
		vbox.add_child(name_label)
		var desc := Label.new()
		desc.text = "%s\n消耗：%d 金币 + %d 科技点 · 占地 %dx%d" % [
			unit.get("desc", ""), int(unit.get("cost_gold", 0)), int(unit.get("cost_tech", 0)),
			int(unit.get("width", 1)), int(unit.get("height", 1))]
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_override("font", FONT_SERIF)
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(0.72, 0.8, 0.92, 0.9))
		vbox.add_child(desc)
		# 批量制造：×1 / ×5 / ×10（资源不足自动停止）
		var make_row := HBoxContainer.new()
		make_row.add_theme_constant_override("separation", 8)
		vbox.add_child(make_row)
		for count: int in [1, 5, 10]:
			var make_btn := Button.new()
			make_btn.text = "制造 ×%d" % count
			make_btn.custom_minimum_size = Vector2(0, 34)
			make_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			make_btn.add_theme_font_override("font", FONT_BOLD)
			make_btn.add_theme_font_size_override("font_size", 13)
			make_btn.pressed.connect(_make_batch.bind(unit_id, count))
			make_row.add_child(make_btn)
		_inventory_box.add_child(card)


# === 防御页：库存选择 ===

func _refresh_defense_panel() -> void:
	if _defense_panel == null:
		return
	for child: Node in _defense_panel.get_children():
		child.queue_free()
	var head := Label.new()
	head.text = "选择库存设施部署到基地（右键拆除）"
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_font_override("font", FONT_BOLD)
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(0.5, 0.8, 1, 0.95))
	_defense_panel.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_defense_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	for unit_id: String in MilitarySystem.units_data:
		# 基地部署只展示防御型设施（offense 进攻单位为副本所用，不占基地）
		if MilitarySystem.units_data[unit_id].get("role", "defense") != "defense":
			continue
		var count: int = int(MilitarySystem.inventory.get(unit_id, 0))
		var unit: Dictionary = MilitarySystem.units_data[unit_id]
		var btn := Button.new()
		var selected: bool = (unit_id == _selected_unit)
		btn.text = "%s ×%d%s" % [unit.get("name", ""), count, "  ✅" if selected else ""]
		btn.custom_minimum_size = Vector2(0, 36)
		btn.add_theme_font_override("font", FONT_BOLD)
		btn.add_theme_font_size_override("font_size", 14)
		btn.disabled = (count <= 0)
		btn.pressed.connect(_on_inventory_btn_pressed.bind(unit_id))
		box.add_child(btn)
	# 扩大基地
	var upgrade_btn := Button.new()
	upgrade_btn.text = "⬆ 批量升级"
	upgrade_btn.custom_minimum_size = Vector2(0, 36)
	upgrade_btn.add_theme_font_override("font", FONT_BOLD)
	upgrade_btn.add_theme_font_size_override("font_size", 13)
	upgrade_btn.pressed.connect(func() -> void:
		_base_grid.set_upgrade_mode(not _base_grid.upgrade_mode))
	_defense_panel.add_child(upgrade_btn)
	var expand_btn := Button.new()
	expand_btn.text = "扩大基地（+2x+2）"
	expand_btn.custom_minimum_size = Vector2(0, 36)
	expand_btn.add_theme_font_override("font", FONT_BOLD)
	expand_btn.add_theme_font_size_override("font_size", 13)
	expand_btn.pressed.connect(func() -> void:
		var result: Dictionary = MilitarySystem.expand_base()
		_info_label.text = result["message"])
	_defense_panel.add_child(expand_btn)
	_refresh_base_info()


func _make_batch(unit_id: String, count: int) -> void:
	## 批量制造：连续制造 count 个，资源不足时自动停止
	var made: int = 0
	for i: int in range(count):
		var result: Dictionary = MilitarySystem.manufacture(unit_id)
		if result["ok"]:
			made += 1
		else:
			if made == 0:
				_info_label.text = result["message"]
			break
	if made > 0:
		_info_label.text = "已批量制造「%s」×%d（库存 %d）" % [
			MilitarySystem.units_data.get(unit_id, {}).get("name", unit_id),
			made, int(MilitarySystem.inventory.get(unit_id, 0))]


func _on_base_upgrade_requested(rect: Rect2i) -> void:
	## 基地批量升级：确认后区域内设施立即升级（每级攻击/生命 +25%），消耗金币+科技
	var dialog := ConfirmationDialog.new()
	dialog.title = "批量升级"
	dialog.dialog_text = "确定升级框选区域内的军事设施吗？\n（每级攻击/生命 +25%，消耗金币+科技）"
	dialog.ok_button_text = "执行升级"
	dialog.cancel_button_text = "取消"
	dialog.confirmed.connect(func() -> void:
		var result: Dictionary = MilitarySystem.batch_upgrade(rect)
		if int(result["upgraded"]) > 0:
			_info_label.text = "批量升级完成：%d 座升级（%d 金币 + %d 科技）" % [
				int(result["upgraded"]), int(result["cost_gold"]), int(result["cost_tech"])]
		else:
			_info_label.text = "没有设施被升级（资源不足或区域内无设施）")
	dialog.close_requested.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _on_inventory_btn_pressed(unit_id: String) -> void:
	## 库存设施按钮：选中/取消选中，并同步基地网格的选中设施
	_selected_unit = unit_id if _selected_unit != unit_id else ""
	_base_grid.selected_unit = _selected_unit
	_refresh_defense_panel()


func _refresh_base_info() -> void:
	if _base_grid == null:
		return
	_base_grid.queue_redraw()
	if _current_page == "defense":
		_info_label.text = "军事规模：%d（攻城阈值 %d）· 基地 %dx%d · 已部署 %d" % [
			MilitarySystem.military_score(), MilitarySystem.SIEGE_THRESHOLD,
			MilitarySystem.BASE_W, MilitarySystem.BASE_H, MilitarySystem.base_placed.size()]


func _make_card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.11, 0.22, 0.95)
	sb.border_color = Color(0.3, 0.55, 0.9, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	return sb


# ================= 军事基地网格（内部类） =================

class MilitaryBaseGrid:
	extends Control

	## 军事基地网格 3D 化：SubViewport 渲染（参考 grid_view.gd 架构）+ 地面平铺 + MilitaryMeshes 契约生成设施模型，
	## 轨道摄像机（滚轮缩放 / 左键拖动旋转）+ 射线拾取；保留选中 / 部署 / 拆除 / 批量升级框选交互；
	## 远程防御设施（turret/aa）周期性向基地外侧发射弹幕（抛物线视觉）。
	## 设计依据：docs/design/game_design.md 3.12（3D 化 + 弹幕表现）

	signal unit_selected(unit_id: String)  # 点击已部署设施时选中其类型
	signal remove_requested(cell: Vector2i)
	signal place_requested(cell: Vector2i)  # 点击空白格部署选中设施
	signal upgrade_requested(rect: Rect2i)  # 批量升级框选完成

	const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")

	# === 3D 网格与摄像机参数 ===
	const CELL: float = 6.0                    # 每格 3D 世界单位（基地 15×10 → 90×60）
	const CAM_DIST_BASE: float = 150.0         # 初始摄像机距离（可看全基地）
	const CAM_DIST_MIN: float = 38.0
	const CAM_DIST_MAX: float = 420.0
	const CAM_YAW_INIT: float = 0.0            # 面向基地正南（轻微斜视）
	const CAM_PITCH_INIT: float = 0.6
	const CAM_PITCH_MIN: float = 0.12
	const CAM_PITCH_MAX: float = 1.35
	const ROTATE_SPEED: float = 0.006
	const HIGHLIFT: float = 0.25               # 高亮拾升量（防 z-fighting / 被地面遮挡）

	# === 弹幕（远程防御）参数 ===
	const BARRAGE_INTERVAL: float = 2.5        # 每 2.5 秒发射（错相）
	const BARRAGE_RANGE: float = 34.0          # 弹体飞离基地外侧的距离
	const PROJECTILE_DUR: float = 1.15         # 单发飞行时间（秒）
	const ARC_HEIGHT: float = 13.0             # 抛物线弹道峰值高度

	var edit_mode: bool = false
	var selected_unit: String = ""  # 父类同步的当前选中设施 id
	var _hover_cell: Vector2i = Vector2i(-1, -1)

	# === 批量升级框选 ===
	var upgrade_mode: bool = false
	var _select_start: Vector2i = Vector2i(-1, -1)
	var _select_end: Vector2i = Vector2i(-1, -1)

	# === 拖动交互状态 ===
	var _mouse_left_down: bool = false
	var _press_pos: Vector2 = Vector2.ZERO
	var _press_cell: Vector2i = Vector2i(-1, -1)
	var _click_armed: bool = false  # 按下在空白格，等待拖动/单击判定
	var _dragging: bool = false
	var _rotating: bool = false      # 左键拖动旋转视角
	var _last_drag_cell: Vector2i = Vector2i(-1, -1)
	var _last_mouse_pos: Vector2 = Vector2.ZERO
	const DRAG_THRESHOLD: float = 6.0  # 超过该像素距离视为拖动而非单击

	# === 摄像机状态 ===
	var _cam_dist: float = CAM_DIST_BASE
	var _yaw: float = CAM_YAW_INIT
	var _pitch: float = CAM_PITCH_INIT
	var _cam_target: Vector3 = Vector3.ZERO  # 注视点（基地中心）

	# === 3D 节点 ===
	var _viewport: SubViewport
	var _viewport_container: SubViewportContainer  # 手动管理尺寸/缩放（见 _update_viewport_size）
	var _world: Node3D
	var _camera: Camera3D
	var _ground_root: Node3D
	var _object_root: Node3D
	var _highlight: MeshInstance3D  # 悬停/框选高亮
	var _sun: DirectionalLight3D

	# === 弹幕 / 粒子状态 ===
	var _defenders: Array[Dictionary] = []     # [{key, center, timer}] 远程防御设施（turret/aa）
	var _barrages: Array[Dictionary] = []      # [{node, start, target, t, dur, arc}] 在途弹体
	var _particles: Array[Dictionary] = []     # [{node, vel, life, max_life}] 命中粒子


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_build_3d_world()
		_cam_target = Vector3(float(MilitarySystem.BASE_W) * CELL * 0.5, 0.0,
				float(MilitarySystem.BASE_H) * CELL * 0.5)
		_cam_dist = maxf(CAM_DIST_BASE, float(maxi(MilitarySystem.BASE_W, MilitarySystem.BASE_H)) * CELL * 1.15)
		_update_camera()
		# 数据层变化 → 3D 重建（部署/拆除/升级/扩大基地/攻城破坏均会发出）
		MilitarySystem.base_changed.connect(func(_c: Vector2i) -> void: _rebuild_all())
		_rebuild_all()


	func _process(delta: float) -> void:
		_update_viewport_size()  # 每帧同步子视口分辨率（父级缩放变化不触发 TRANSFORM_CHANGED，轮询可靠）
		_tick_barrages(delta)
		_tick_particles(delta)


	# === 3D 世界构建 ===

	func _build_3d_world() -> void:
		var vpc := SubViewportContainer.new()
		vpc.set_anchors_preset(Control.PRESET_TOP_LEFT)
		vpc.position = Vector2.ZERO
		vpc.stretch = false  # 手动管理缩放，任意分辨率不模糊（同 grid_view.gd）
		vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 关键：让鼠标事件穿透到 MilitaryBaseGrid._gui_input（拖动旋转/滚轮缩放）
		add_child(vpc)
		_viewport_container = vpc
		var vp := SubViewport.new()
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.size = _physical_size()
		vpc.add_child(vp)
		_viewport = vp
		set_notify_transform(true)  # 监听根缩放变化（窗口/界面缩放时更新子视口分辨率）
		_world = Node3D.new()
		_world.name = "BaseWorld3D"
		vp.add_child(_world)
		# 光照：日光 + 冷色补光 + 环境（深蓝军事基地夜色基调）
		_sun = DirectionalLight3D.new()
		_sun.rotation_degrees = Vector3(-48, -34, 0)
		_sun.light_energy = 1.0
		_sun.light_color = Color(0.85, 0.92, 1.0)
		_sun.shadow_enabled = true
		_sun.shadow_bias = 0.02
		_world.add_child(_sun)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-30, 130, 0)
		fill.light_energy = 0.4
		fill.light_color = Color(0.6, 0.72, 1.0)
		_world.add_child(fill)
		var env := WorldEnvironment.new()
		var sky := Environment.new()
		sky.background_mode = Environment.BG_COLOR
		sky.background_color = Color(0.012, 0.02, 0.05)
		sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		sky.ambient_light_color = Color(0.35, 0.45, 0.65)
		sky.ambient_light_energy = 0.7
		env.environment = sky
		_world.add_child(env)
		_ground_root = Node3D.new()
		_ground_root.name = "Ground"
		_world.add_child(_ground_root)
		_object_root = Node3D.new()
		_object_root.name = "Objects"
		_world.add_child(_object_root)
		_camera = Camera3D.new()
		_camera.fov = 42.0
		_camera.near = 0.5
		_camera.far = 6000.0
		_world.add_child(_camera)
		# 悬停/框选高亮（蓝色半透明地面矩形）
		_highlight = MeshInstance3D.new()
		_highlight.visible = false
		_highlight.mesh = _make_flat_quad(1.0, 1.0)
		_highlight.material_override = _make_flat_mat(Color(0.4, 0.8, 1.0, 0.3))
		_object_root.add_child(_highlight)


	# 深蓝灰军事混凝土地面：确定性种子，每格微差色阶（重建不变）
	const GROUND_SHADES: Array[Color] = [
		Color(0.10, 0.14, 0.22, 1.0),
		Color(0.13, 0.18, 0.28, 1.0),
		Color(0.09, 0.12, 0.19, 1.0),
	]

	func _ground_shade(gx: int, gy: int) -> Color:
		var seed: int = 31 * gx + 17 * gy
		return GROUND_SHADES[abs(seed) % GROUND_SHADES.size()]


	func _build_ground() -> void:
		for child: Node in _ground_root.get_children():
			child.queue_free()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var vc: int = 0
		var cw: int = MilitarySystem.BASE_W
		var ch: int = MilitarySystem.BASE_H
		for x: int in range(cw):
			for y: int in range(ch):
				st.set_color(_ground_shade(x, y))
				st.add_vertex(Vector3(x * CELL, 0.0, y * CELL))
				st.add_vertex(Vector3((x + 1) * CELL, 0.0, y * CELL))
				st.add_vertex(Vector3((x + 1) * CELL, 0.0, (y + 1) * CELL))
				st.add_vertex(Vector3(x * CELL, 0.0, (y + 1) * CELL))
				st.add_index(vc); st.add_index(vc + 1); st.add_index(vc + 2)
				st.add_index(vc); st.add_index(vc + 2); st.add_index(vc + 3)
				vc += 4
		var ground := MeshInstance3D.new()
		ground.mesh = st.commit()
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.92
		mat.metallic = 0.02
		ground.material_override = mat
		_ground_root.add_child(ground)
		# 格子线（贴合平面 y=0）
		var lines := ImmediateMesh.new()
		var line_color := Color(0.32, 0.5, 0.78, 0.35)
		lines.surface_begin(Mesh.PRIMITIVE_LINES)
		for x: int in range(cw + 1):
			lines.surface_set_color(line_color)
			lines.surface_add_vertex(Vector3(x * CELL, 0.03, 0.0))
			lines.surface_add_vertex(Vector3(x * CELL, 0.03, ch * CELL))
		for y: int in range(ch + 1):
			lines.surface_set_color(line_color)
			lines.surface_add_vertex(Vector3(0.0, 0.03, y * CELL))
			lines.surface_add_vertex(Vector3(cw * CELL, 0.03, y * CELL))
		lines.surface_end()
		var lm := MeshInstance3D.new()
		lm.name = "GridLines"
		lm.mesh = lines
		var lmat := StandardMaterial3D.new()
		lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lmat.vertex_color_use_as_albedo = true
		lm.material_override = lmat
		_ground_root.add_child(lm)


	# === 重建全部设施 ===

	func _rebuild_all() -> void:
		if _object_root == null:
			return
		# 清理在途弹体与粒子（数据变化重建时不遗留指向已释放节点的引用）
		for b: Dictionary in _barrages:
			(b["node"] as Node).queue_free()
		_barrages.clear()
		for pt: Dictionary in _particles:
			(pt["node"] as Node).queue_free()
		_particles.clear()
		for child: Node in _object_root.get_children():
			if child != _highlight:
				child.queue_free()
		_defenders.clear()
		_hover_cell = Vector2i(-1, -1)
		_build_ground()
		for key: String in MilitarySystem.base_placed:
			var p: Dictionary = MilitarySystem.base_placed[key]
			_spawn_unit(MilitarySystem._key_to_cell(key), p)
			var uid: String = p["unit_id"]
			if uid == "turret" or uid == "aa":
				_register_defender(key, p)
		_update_hover_highlight()


	func _spawn_unit(anchor: Vector2i, p: Dictionary) -> void:
		var unit_id: String = p["unit_id"]
		var w: int = int(p["width"])
		var h: int = int(p["height"])
		# 冻结契约：设施模型由 MilitaryMeshes 生成（2×2 模型已含比例），只读禁改
		var model: Node3D = MilitaryMeshes.build_unit_model(unit_id, CELL, int(p.get("level", 1)))
		model.name = "U_%d,%d" % [anchor.x, anchor.y]
		model.position = Vector3((anchor.x + w * 0.5) * CELL, 0.0, (anchor.y + h * 0.5) * CELL)
		_object_root.add_child(model)
		# 等级 >1 显示金色 "Lv.N" 徽章（Label3D 广告牌，参考 grid_view.gd）
		var lv: int = int(p.get("level", 1))
		if lv > 1:
			var badge := Label3D.new()
			badge.text = "Lv.%d" % lv
			badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			badge.font_size = maxi(6, int(CELL * 0.32))
			badge.outline_size = maxi(2, int(CELL * 0.05))
			badge.outline_modulate = Color(0, 0, 0, 0.85)
			badge.modulate = Color(1.0, 0.9, 0.45, 1.0)
			badge.no_depth_test = true
			badge.position = Vector3(0.0, CELL * 1.7, 0.0)
			badge.pixel_size = 0.005
			model.add_child(badge)


	# === 远程防御弹幕 ===

	func _register_defender(key: String, p: Dictionary) -> void:
		var anchor: Vector2i = MilitarySystem._key_to_cell(key)
		var c: Vector3 = Vector3((anchor.x + int(p["width"]) * 0.5) * CELL, 0.0,
				(anchor.y + int(p["height"]) * 0.5) * CELL)
		# 错相：用 key 哈希确定性生成初始计时（0~间隔），避免所有设施同帧齐射
		var phase: float = (abs(hash(key)) % 1000) / 1000.0 * BARRAGE_INTERVAL
		_defenders.append({"key": key, "center": c, "timer": phase})


	func _fire_shot(def: Dictionary) -> void:
		var start: Vector3 = Vector3(def["center"])
		start.y = CELL * 0.6  # 炮口高度
		# 无真实敌人：向基地外侧离中心远端方向发射（弹幕展示）
		var base_center: Vector3 = Vector3(float(MilitarySystem.BASE_W) * CELL * 0.5, 0.0,
				float(MilitarySystem.BASE_H) * CELL * 0.5)
		var dir: Vector3 = start - base_center
		if dir.length() < 0.1:
			dir = Vector3.RIGHT
		dir = Vector3(dir.x, 0.0, dir.z).normalized()
		var target: Vector3 = start + dir * BARRAGE_RANGE
		var proj := MeshInstance3D.new()
		proj.name = "Proj_" + String(def["key"])
		var sm := SphereMesh.new()
		sm.radius = CELL * 0.09
		sm.height = CELL * 0.18
		sm.radial_segments = 8
		sm.rings = 4
		proj.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.62, 0.25)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.4, 0.1)
		mat.emission_energy_multiplier = 1.6
		proj.material_override = mat
		_object_root.add_child(proj)
		_barrages.append({"node": proj, "start": start, "target": target, "t": 0.0,
				"dur": PROJECTILE_DUR, "arc": ARC_HEIGHT})


	func _tick_barrages(delta: float) -> void:
		# 发射计时（错相：各设施初始计时不同）
		for i: int in range(_defenders.size()):
			var def: Dictionary = _defenders[i]
			def["timer"] = float(def["timer"]) + delta
			if float(def["timer"]) >= BARRAGE_INTERVAL:
				def["timer"] = float(def["timer"]) - BARRAGE_INTERVAL
				_fire_shot(def)
		# 推进弹体（抛物线，命中后消失+粒子）
		var done: Array[int] = []
		for i: int in range(_barrages.size()):
			var b: Dictionary = _barrages[i]
			var t: float = float(b["t"]) + delta
			b["t"] = t
			var k: float = t / float(b["dur"])
			if k >= 1.0:
				_spawn_impact_burst(Vector3(b["target"]))
				done.append(i)
				continue
			var start: Vector3 = Vector3(b["start"])
			var target: Vector3 = Vector3(b["target"])
			var pos: Vector3 = start.lerp(target, k)
			pos.y += float(b["arc"]) * 4.0 * k * (1.0 - k)  # 抛物线弧顶
			(b["node"] as Node3D).position = pos
		for j: int in range(done.size()):
			var idx: int = int(done[done.size() - 1 - j])
			(_barrages[idx]["node"] as Node).queue_free()
			_barrages.remove_at(idx)


	func _emit_particle(pos: Vector3, vel: Vector3, color: Color, size: float, life: float) -> void:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = size
		sm.height = size * 2.0
		mi.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mat
		mi.position = pos
		_object_root.add_child(mi)
		_particles.append({"node": mi, "vel": vel, "life": life, "max_life": life})


	func _tick_particles(delta: float) -> void:
		var done: Array[int] = []
		for i: int in range(_particles.size()):
			var pt: Dictionary = _particles[i]
			pt["life"] = float(pt["life"]) - delta
			var node: MeshInstance3D = pt["node"]
			node.position = node.position + Vector3(pt["vel"]) * delta
			var alpha: float = clampf(float(pt["life"]) / float(pt["max_life"]), 0.0, 1.0)
			(node.material_override as StandardMaterial3D).albedo_color.a = alpha
			if float(pt["life"]) <= 0.0:
				done.append(i)
		for j: int in range(done.size()):
			var idx: int = int(done[done.size() - 1 - j])
			(_particles[idx]["node"] as Node).queue_free()
			_particles.remove_at(idx)


	func _spawn_impact_burst(pos: Vector3) -> void:
		for i: int in range(8):
			var ang: float = randf() * TAU
			_emit_particle(pos, Vector3(cos(ang), randf_range(0.5, 2.2), sin(ang)) * 34.0,
					Color(1.0, 0.55, 0.2), CELL * 0.045, 0.5)


	# === 摄像机 ===

	func _update_camera() -> void:
		if _camera == null:
			return
		var offset := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _cam_dist
		_camera.position = _cam_target + offset
		_camera.look_at(_cam_target, Vector3.UP)


	# === 射线拾取（基地地面为水平面 y=0）===

	func _screen_to_ground(screen_pos: Vector2) -> Vector3:
		var factor: float = 1.0
		if WindowManager.has_method("current_scale_factor"):
			factor = WindowManager.current_scale_factor()
		var ss: float = 1.0
		if WindowManager.has_method("supersample_factor"):
			ss = WindowManager.supersample_factor()
		var vp_px := screen_pos * factor * ss
		var ray_origin: Vector3 = _camera.project_ray_origin(vp_px)
		var ray_dir: Vector3 = _camera.project_ray_normal(vp_px)
		if absf(ray_dir.y) < 0.0001:
			return Vector3.ZERO
		var t: float = -ray_origin.y / ray_dir.y
		if t < 0.0:
			return Vector3.ZERO
		return ray_origin + ray_dir * t


	func _screen_to_cell(screen_pos: Vector2) -> Vector2i:
		var hit: Vector3 = _screen_to_ground(screen_pos)
		if hit == Vector3.ZERO:
			return Vector2i(-1, -1)
		var x: int = int(hit.x / CELL)
		var y: int = int(hit.z / CELL)
		if x < 0 or y < 0 or x >= MilitarySystem.BASE_W or y >= MilitarySystem.BASE_H:
			return Vector2i(-1, -1)
		return Vector2i(x, y)


	# === 高亮（悬停单格 / 批量升级框选）===

	func _selection_rect() -> Rect2i:
		return Rect2i(mini(_select_start.x, _select_end.x), mini(_select_start.y, _select_end.y),
				abs(_select_end.x - _select_start.x) + 1, abs(_select_end.y - _select_start.y) + 1)


	func _update_hover_highlight() -> void:
		if _highlight == null:
			return
		# 升级框选：蓝色半透明矩形盖选区域
		if upgrade_mode and _select_start.x >= 0 and _select_end.x >= 0:
			var r: Rect2i = _selection_rect()
			var sw: float = float(r.size.x) * CELL
			var sh: float = float(r.size.y) * CELL
			_highlight.mesh = _make_flat_quad(sw, sh)
			_highlight.position = Vector3(float(r.position.x) * CELL + sw * 0.5, HIGHLIFT,
					float(r.position.y) * CELL + sh * 0.5)
			_highlight.visible = true
			(_highlight.material_override as StandardMaterial3D).albedo_color = Color(0.35, 0.8, 1.0, 0.28)
			return
		# 单格悬停高亮
		if _hover_cell.x >= 0 and _hover_cell.y >= 0:
			_highlight.mesh = _make_flat_quad(CELL, CELL)
			_highlight.position = Vector3((_hover_cell.x + 0.5) * CELL, HIGHLIFT, (_hover_cell.y + 0.5) * CELL)
			_highlight.visible = true
			(_highlight.material_override as StandardMaterial3D).albedo_color = Color(0.4, 0.8, 1.0, 0.25)
			return
		_highlight.visible = false


	func _make_flat_quad(w: float, h: float) -> Mesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var hx: float = w * 0.5
		var hz: float = h * 0.5
		st.set_color(Color.WHITE)
		st.add_vertex(Vector3(-hx, 0.0, -hz))
		st.add_vertex(Vector3(hx, 0.0, -hz))
		st.add_vertex(Vector3(hx, 0.0, hz))
		st.add_vertex(Vector3(-hx, 0.0, hz))
		# 绕序反转：法线朝上（+Y），俯视可见（修复：反绕序法线朝下被剔除）
		st.add_index(0); st.add_index(2); st.add_index(1)
		st.add_index(0); st.add_index(3); st.add_index(2)
		return st.commit()


	func _make_flat_mat(color: Color) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED  # 双面渲染，任意视角可见
		return m


	# === 输入 ===

	func _gui_input(event: InputEvent) -> void:
		# 滚轮缩放：任意页面可用（查看基地 3D 视距）
		if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_WHEEL_UP
				or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if event.pressed:
				var factor: float = 0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.14
				_cam_dist = clampf(_cam_dist * factor, CAM_DIST_MIN, CAM_DIST_MAX)
				_update_camera()
			return
		if not edit_mode:
			return
		# 升级框选：优先处理（左键拖动框选，右键退出）
		if upgrade_mode:
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					_select_start = _screen_to_cell(event.position)
					_select_end = _select_start
				else:
					if _select_start.x >= 0 and _select_end.x >= 0:
						upgrade_requested.emit(_selection_rect())
					_select_start = Vector2i(-1, -1)
					_select_end = Vector2i(-1, -1)
				_update_hover_highlight()
				return
			elif event is InputEventMouseMotion:
				if _select_start.x >= 0:
					_select_end = _screen_to_cell(event.position)
					_update_hover_highlight()
				return
			elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				set_upgrade_mode(false)
				return
		# 左键按下：记录拖动起点；点击已部署设施立即选中其类型；点击空白则待拖动/单击判定
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_mouse_left_down = true
			_press_pos = event.position
			_last_mouse_pos = event.position
			_press_cell = _screen_to_cell(event.position)
			_last_drag_cell = Vector2i(-1, -1)
			var placed_key: String = MilitarySystem.get_placed_key(_press_cell)
			if placed_key != "":
				unit_selected.emit(MilitarySystem.base_placed[placed_key]["unit_id"])
				_click_armed = false
			else:
				_click_armed = true
			return
		# 鼠标移动：更新悬停 + 判定拖动（批量部署 / 旋转视角）
		if event is InputEventMouseMotion:
			var c: Vector2i = _screen_to_cell(event.position)
			if c != _hover_cell:
				_hover_cell = c
				_update_hover_highlight()
			if _mouse_left_down and not _rotating and not _dragging 					and event.position.distance_to(_press_pos) > DRAG_THRESHOLD:
				if _click_armed and not selected_unit.is_empty():
					_dragging = true         # 拖动批量部署（划过可建格连续放置）
					_click_armed = false
					_last_drag_cell = Vector2i(-1, -1)
				else:
					_rotating = true         # 左键拖动旋转视角
					_click_armed = false
			if _dragging:
				if c.x >= 0 and c != _last_drag_cell:
					_last_drag_cell = c
					place_requested.emit(c)
			if _rotating:
				var delta: Vector2 = event.position - _last_mouse_pos
				_yaw -= delta.x * ROTATE_SPEED
				_pitch = clampf(_pitch + delta.y * ROTATE_SPEED, CAM_PITCH_MIN, CAM_PITCH_MAX)
				_update_camera()
			_last_mouse_pos = event.position
			return
		# 左键松开：判定单击（部署/取消选择）或结束拖动/旋转
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_mouse_left_down = false
			if _rotating:
				_rotating = false
				return
			if _dragging:
				_dragging = false
				_click_armed = false
				return
			if _click_armed:
				_click_armed = false
				if not selected_unit.is_empty():
					place_requested.emit(_press_cell)
				else:
					unit_selected.emit("")
			return
		# 右键：拆除设施 / 取消拖动
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			var c: Vector2i = _screen_to_cell(event.position)
			if MilitarySystem.get_placed_key(c) != "":
				remove_requested.emit(c)
			_mouse_left_down = false
			_dragging = false
			_rotating = false
			_click_armed = false


	# === 工具（父类接口，保持兼容）===

	func set_upgrade_mode(on: bool) -> void:
		## 批量升级框选模式开关（左键拖动框选，右键退出）
		upgrade_mode = on
		_select_start = Vector2i(-1, -1)
		_select_end = Vector2i(-1, -1)
		_update_hover_highlight()


	# === 子视口尺寸同步（同 grid_view.gd）===

	func _physical_size() -> Vector2i:
		var factor: float = 1.0
		if WindowManager.has_method("current_scale_factor"):
			factor = WindowManager.current_scale_factor()
		var ss: float = 1.0
		if WindowManager.has_method("supersample_factor"):
			ss = WindowManager.supersample_factor()
		return Vector2i(maxi(64, int(size.x * factor * ss)), maxi(64, int(size.y * factor * ss)))


	func _update_viewport_size() -> void:
		if _viewport == null or _viewport_container == null:
			return
		var target: Vector2i = _physical_size()
		if target != _viewport.size:
			_viewport.size = target
			_viewport_container.size = Vector2(target)
		var factor: float = 1.0
		if WindowManager.has_method("current_scale_factor"):
			factor = WindowManager.current_scale_factor()
		var ss: float = 1.0
		if WindowManager.has_method("supersample_factor"):
			ss = WindowManager.supersample_factor()
		var inv: Vector2 = Vector2(1.0 / (factor * ss), 1.0 / (factor * ss))
		if _viewport_container.scale != inv:
			_viewport_container.scale = inv


	func _notification(what: int) -> void:
		# 控件尺寸/全局缩放变化 → 同步子视口分辨率（防 3D 画面拉伸模糊）
		if what == NOTIFICATION_RESIZED or what == NOTIFICATION_TRANSFORM_CHANGED:
			_update_viewport_size()
