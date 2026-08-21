class_name ExploreMap
extends Control

## 地图与探索界面：左侧建筑菜单 + 中央网格建设区
## 设计依据：docs/design/game_design.md 3.7
## 界面专属组件已合并为内部类（避免过度拆分，见 AGENTS.md 3.1）：
##   BuildingActionPanel（操作面板）、BuildingInfo（悬停文案）、BuildingFeedback（建造反馈）、MapSummary（建筑产出总览）

# 建筑产出总览面板定位（网格下方空白区，设计坐标系 1280×720）
const SUMMARY_RECT: Rect2 = Rect2(260, 596, 1010, 84)
const EXPAND_COST_BASE: int = 500  # 扩大地图基础费用（每次扩大递增 500）
const FONT_BTN: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")

@onready var menu: BuildingMenu = %MenuList
@onready var grid_view: GridView = %GridView
@onready var info_panel: PanelContainer = %InfoPanel
@onready var info_title: Label = %InfoTitle
@onready var info_desc: Label = %InfoDesc
@onready var info_hint: Label = %InfoHint
@onready var action_panel: PanelContainer = %ActionPanel
@onready var action_upgrade_btn: Button = %ActionUpgradeBtn
@onready var action_demolish_btn: Button = %ActionDemolishBtn

var selected_item: Dictionary = {}
var _action_ctrl: BuildingActionPanel
var _feedback: BuildingFeedback


func _ready() -> void:
	_action_ctrl = BuildingActionPanel.new()
	_action_ctrl.setup(action_panel, %ActionTitle, %ActionDesc,
			action_upgrade_btn, action_demolish_btn, %ActionCloseBtn)
	_feedback = BuildingFeedback.new()
	_feedback.setup(grid_view, info_hint)
	_connect_signals()
	info_panel.hide()
	action_panel.hide()
	info_hint.text = BuildingInfo.HINT_BASE
	_add_summary_panel()
	_build_top_buttons()


func _add_summary_panel() -> void:
	# 建筑产出总览：悬于网格下方空白区，鼠标穿透不阻挡建造点击
	var summary := MapSummary.new()
	summary.name = "SummaryPanel"
	summary.position = SUMMARY_RECT.position
	summary.size = SUMMARY_RECT.size
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(summary)


func _connect_signals() -> void:
	menu.item_selected.connect(_on_item_selected)
	grid_view.hover_changed.connect(_on_hover_changed)
	grid_view.cell_clicked.connect(_on_cell_clicked)
	grid_view.preview_cancel_requested.connect(_on_preview_cancel_requested)
	grid_view.drag_place_requested.connect(_on_drag_place_requested)
	grid_view.demolition_requested.connect(_on_demolition_requested)
	BuildingSystem.grid_changed.connect(func(_cell: Vector2i) -> void: grid_view.queue_redraw())
	BuildingSystem.building_completed.connect(_feedback.on_completed)
	BuildingSystem.building_upgraded.connect(_feedback.on_upgraded)
	BuildingSystem.building_demolished.connect(_feedback.on_demolished)
	BuildingSystem.obstacle_cleared.connect(_feedback.on_obstacle_cleared)
	action_upgrade_btn.pressed.connect(_on_upgrade_pressed)
	action_demolish_btn.pressed.connect(_on_demolish_pressed)
	%ActionCloseBtn.pressed.connect(_close_action_panel)



# === 右上角操作按钮（地图扩大 / 副本探索）===

func _build_top_buttons() -> void:
	# 地图按钮：消费金币扩大地图面积（每次 +2 列 +2 行，费用递增）
	var btn_map := Button.new()
	btn_map.name = "BtnMapExpand"
	btn_map.text = "🗺 地图"
	btn_map.custom_minimum_size = Vector2(88, 34)
	btn_map.position = Vector2(size.x - 196, 8)
	btn_map.add_theme_font_override("font", FONT_BTN)
	btn_map.add_theme_font_size_override("font_size", 14)
	btn_map.add_theme_stylebox_override("normal", _make_top_btn_style(Color(0.1, 0.3, 0.55, 0.9)))
	btn_map.add_theme_stylebox_override("hover", _make_top_btn_style(Color(0.15, 0.42, 0.75, 1.0)))
	btn_map.add_theme_stylebox_override("pressed", _make_top_btn_style(Color(0.07, 0.22, 0.42, 1.0)))
	btn_map.pressed.connect(_on_map_expand_pressed)
	add_child(btn_map)
	# 批量拆除按钮：框选区域批量拆除建筑与障碍（进入拆除模式后左键拖动框选）
	var btn_demolish := Button.new()
	btn_demolish.name = "BtnBatchDemolish"
	btn_demolish.text = "🧹 拆除"
	btn_demolish.custom_minimum_size = Vector2(88, 34)
	btn_demolish.position = Vector2(size.x - 292, 8)
	btn_demolish.add_theme_font_override("font", FONT_BTN)
	btn_demolish.add_theme_font_size_override("font_size", 14)
	btn_demolish.add_theme_stylebox_override("normal", _make_top_btn_style(Color(0.5, 0.25, 0.2, 0.9)))
	btn_demolish.add_theme_stylebox_override("hover", _make_top_btn_style(Color(0.7, 0.35, 0.28, 1.0)))
	btn_demolish.add_theme_stylebox_override("pressed", _make_top_btn_style(Color(0.35, 0.16, 0.12, 1.0)))
	btn_demolish.pressed.connect(_on_demolish_mode_pressed)
	add_child(btn_demolish)
	# 探索按钮：进入副本探索界面（攻城系统入口，见设计文档 3.11）
	var btn_explore := Button.new()
	btn_explore.name = "BtnInstanceExplore"
	btn_explore.text = "⚔ 探索"
	btn_explore.custom_minimum_size = Vector2(88, 34)
	btn_explore.position = Vector2(size.x - 100, 8)
	btn_explore.add_theme_font_override("font", FONT_BTN)
	btn_explore.add_theme_font_size_override("font_size", 14)
	btn_explore.add_theme_stylebox_override("normal", _make_top_btn_style(Color(0.4, 0.2, 0.5, 0.9)))
	btn_explore.add_theme_stylebox_override("hover", _make_top_btn_style(Color(0.55, 0.28, 0.68, 1.0)))
	btn_explore.add_theme_stylebox_override("pressed", _make_top_btn_style(Color(0.3, 0.14, 0.38, 1.0)))
	btn_explore.pressed.connect(_on_explore_pressed)
	add_child(btn_explore)


func _make_top_btn_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(0.5, 0.8, 1, 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	return sb


func _on_map_expand_pressed() -> void:
	# 每次扩大 +2 列 +2 行；费用随扩大次数递增（500/1000/1500...）
	var expansions: int = maxi(0, (BuildingSystem.GRID_W - BuildingSystem.BuildingData.DEFAULT_GRID_W) / 2)
	var cost: int = EXPAND_COST_BASE * (expansions + 1)
	if GameState.gold < cost:
		info_hint.text = "金币不足：扩大地图需要 %d 金币（当前 %d）" % [cost, int(GameState.gold)]
		return
	GameState.add_gold(-cost)
	BuildingSystem.expand_grid(2, 2)
	info_hint.text = "地图已扩大至 %d×%d（花费 %d 金币），可用滚轮缩放" % [
		BuildingSystem.GRID_W, BuildingSystem.GRID_H, cost]


func _on_explore_pressed() -> void:
	# 进入副本探索界面（攻城系统，见设计文档 3.11 副本与攻城）
	get_tree().change_scene_to_file("res://scenes/ui/instance/instance_map.tscn")


# === 菜单选择 ===

func _on_preview_cancel_requested() -> void:
	## 右键取消预选：同步清空左侧菜单选中态与选择信息
	menu.clear_selection()
	_on_item_selected({})


func _on_item_selected(item: Dictionary) -> void:
	selected_item = item
	grid_view.preview_item = item
	grid_view.queue_redraw()
	if item.is_empty():
		# 再次点击同一建筑 = 取消选择
		info_panel.hide()
		info_hint.text = "已取消选择"
		return
	_show_info(item["name"], "金币 %d · 占地 %dx%d\n%s" % [
		int(item["cost"]), int(item["width"]), int(item["height"]), item["bonus_desc"],
	])


# === 悬停 ===

func _on_hover_changed(cell: Vector2i) -> void:
	if cell.x < 0:
		info_panel.hide()  # 移出网格时清除残留信息
		return
	if BuildingSystem.is_obstacle(cell):
		var obs: Dictionary = BuildingSystem.get_obstacle_at(cell)
		_show_info(obs["name"], BuildingInfo.obstacle_desc(obs))
	elif selected_item.is_empty():
		var placed: Dictionary = BuildingSystem.get_placed_at(cell)
		if not placed.is_empty():
			var item: Dictionary = BuildingSystem.get_item(placed["item_id"])
			if placed["op"] == "":
				_show_info(item["name"], BuildingInfo.completed_desc(item, placed))
			else:
				_show_info(item["name"], BuildingInfo.construction_desc(item, placed))
		else:
			info_panel.hide()
	elif _grid_view_can_build(cell):
		if GameState.gold < float(selected_item.get("cost", 0)):
			_show_info(selected_item["name"], "金币不足，无法建造（需要 %d 金币，当前 %d）" % [
				int(selected_item["cost"]), int(GameState.gold)])
		else:
			_show_info(selected_item["name"], "点击放置（%d 金币）" % int(selected_item["cost"]))
	else:
		_show_info(selected_item["name"], "位置不可用：被占用或超出边界")


# === 点击 ===

func _on_demolish_mode_pressed() -> void:
	## 切换批量拆除模式（再次点击或右键退出）
	grid_view.set_demolish_mode(not grid_view.demolish_mode)
	if grid_view.demolish_mode:
		_on_preview_cancel_requested()
		info_hint.text = "批量拆除模式：左键拖动框选区域（建筑返还、障碍扣清障费），右键退出"
	else:
		info_hint.text = BuildingInfo.HINT_BASE


func _on_demolition_requested(rect: Rect2i) -> void:
	## 框选完成：统计区域内对象并确认后批量拆除
	var preview: Dictionary = BuildingSystem.preview_demolish(rect)
	if int(preview["buildings"]) == 0 and int(preview["obstacles"]) == 0:
		info_hint.text = "框选区域内没有可拆除对象"
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "批量拆除"
	dialog.dialog_text = "框选区域内：\n建筑 %d 座（返还 %d 金币）\n障碍 %d 个（清障费 %d 金币）\n\n确定执行批量拆除吗？" % [
		int(preview["buildings"]), int(preview["refund"]),
		int(preview["obstacles"]), int(preview["clear_cost"])]
	dialog.ok_button_text = "执行拆除"
	dialog.cancel_button_text = "取消"
	dialog.confirmed.connect(func() -> void:
		var result: Dictionary = BuildingSystem.batch_demolish(rect)
		info_hint.text = "批量拆除完成：建筑 %d 座（返还 %d 金币）、障碍 %d 个（清障费 %d）" % [
			int(result["buildings"]), int(result["refund"]),
			int(result["obstacles"]), int(result["clear_cost"])])
	dialog.close_requested.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _on_drag_place_requested(cell: Vector2i) -> void:
	## 左键按住拖动连续建造：划过可建区域自动放置（不改变选中态）
	if selected_item.is_empty() or BuildingSystem.is_obstacle(cell):
		return
	if BuildingSystem.place_item(cell, selected_item["id"]):
		grid_view.place_animations["%d,%d" % [cell.x, cell.y]] = 0.0
		grid_view.queue_redraw()


func _on_cell_clicked(cell: Vector2i) -> void:
	if cell.x < 0:
		return
	# 优先处理障碍清除（自动定位锚点格）
	if BuildingSystem.is_obstacle(cell):
		if BuildingSystem.clear_obstacle(cell):
			info_hint.text = "障碍已清除，该区域可以建造了"
		else:
			info_hint.text = "金币不足，无法清除障碍"
		return
	# 已放置建筑：施工中可取消/查看进度，已完工打开操作面板
	var placed: Dictionary = BuildingSystem.get_placed_at(cell)
	if not placed.is_empty():
		var item: Dictionary = BuildingSystem.get_item(placed["item_id"])
		match placed["op"]:
			"build":
				if BuildingSystem.cancel_construction(cell):
					grid_view.queue_redraw()
					info_hint.text = "已取消建造，返还 %d 金币" % int(item["cost"])
			"upgrade":
				info_hint.text = "升级中…点击无效"
			"demolish":
				info_hint.text = "拆除中…点击无效"
			_:
				_open_action_panel(BuildingSystem.get_placed_key(cell))
		return
	# 放置新建筑
	if selected_item.is_empty():
		info_hint.text = "请先在左侧菜单中选择一个建筑"
		return
	if BuildingSystem.place_item(cell, selected_item["id"]):
		grid_view.place_animations["%d,%d" % [cell.x, cell.y]] = 0.0
		grid_view.queue_redraw()
		info_hint.text = "%s 开始建造..." % selected_item["name"]
	else:
		info_hint.text = "无法建造：金币不足或位置被占用"



# === 操作面板（委托 BuildingActionPanel）===

func _open_action_panel(key: String) -> void:
	_action_ctrl.open(key)


func _close_action_panel() -> void:
	_action_ctrl.close()


func _on_upgrade_pressed() -> void:
	var key: String = _action_ctrl.current_key()
	if key.is_empty():
		return
	if BuildingSystem.upgrade_building(BuildingSystem.BuildingGrid.key_to_cell(key)):
		info_hint.text = "开始升级，完成后加成提升！"
		_close_action_panel()
		grid_view.queue_redraw()
	else:
		info_hint.text = "无法升级：金币不足或已达最高等级"


func _on_demolish_pressed() -> void:
	var key: String = _action_ctrl.current_key()
	if key.is_empty():
		return
	if BuildingSystem.start_demolish(BuildingSystem.BuildingGrid.key_to_cell(key)):
		info_hint.text = "开始拆除…完成后返还金币"
		_close_action_panel()
		grid_view.queue_redraw()
	else:
		info_hint.text = "无法拆除：建筑正在施工中"


# === 工具 ===

func _grid_view_can_build(cell: Vector2i) -> bool:
	var w: int = int(selected_item.get("width", 1))
	var h: int = int(selected_item.get("height", 1))
	return grid_view.can_build_at(cell, w, h)


func _show_info(title: String, desc: String) -> void:
	info_title.text = title
	info_desc.text = desc
	info_panel.show()


# ================= 内部类（原独立组件文件已合并） =================

# === 建筑操作面板控制器（原 building_action_panel.gd）===
class BuildingActionPanel:
	extends RefCounted

	## 建筑操作面板控制器：点击已完工建筑时显示等级/加成/升级费用/拆除返还。
	## 由 explore_map 创建并注入节点引用，职责与地图交互逻辑分离。
	## 设计依据：docs/design/game_design.md 3.7（升级与拆除）

	var panel: PanelContainer
	var title: Label
	var desc: Label
	var upgrade_btn: Button
	var demolish_btn: Button
	var close_btn: Button
	var action_key: String = ""


	func setup(panel_node: PanelContainer, title_node: Label, desc_node: Label,
			upgrade_node: Button, demolish_node: Button, close_node: Button) -> void:
		panel = panel_node
		title = title_node
		desc = desc_node
		upgrade_btn = upgrade_node
		demolish_btn = demolish_node
		close_btn = close_node


	func open(key: String) -> void:
		var p: Dictionary = BuildingSystem.placed[key]
		var item: Dictionary = BuildingSystem.get_item(p["item_id"])
		action_key = key
		var level: int = int(p["level"])
		title.text = "%s  Lv.%d" % [item.get("name", "?"), level]
		desc.text = "%s\n\n升级费用：%d 金币\n拆除返还：%d 金币" % [
			item.get("bonus_desc", ""),
			int(BuildingSystem.get_upgrade_cost(p)),
			int(BuildingSystem.get_demolish_refund(p)),
		]
		if level >= BuildingSystem.BuildingBalance.MAX_LEVEL:
			upgrade_btn.text = "已达最高等级"
			upgrade_btn.disabled = true
		else:
			upgrade_btn.text = "升级至 Lv.%d（%d 金币）" % [
				level + 1, int(BuildingSystem.get_upgrade_cost(p)),
			]
			upgrade_btn.disabled = GameState.gold < BuildingSystem.get_upgrade_cost(p)
		demolish_btn.text = "拆除（返还 %d 金币）" % int(BuildingSystem.get_demolish_refund(p))
		panel.show()


	func close() -> void:
		panel.hide()
		action_key = ""


	func current_key() -> String:
		return action_key


# === 地图信息文案（原 building_info.gd）===
class BuildingInfo:
	extends RefCounted

	## 地图信息文案：悬停/点击时显示的建筑/障碍/施工状态描述。
	## 与 explore_map 交互逻辑分离。
	## 设计依据：docs/design/game_design.md 3.7

	const HINT_BASE: String = "选择左侧建筑后，点击网格放置；点击障碍可花费金币清除"


	static func obstacle_desc(obs: Dictionary) -> String:
		return "清除需 %d 金币\n点击障碍即可清除" % int(obs["clear_cost"])


	static func construction_desc(item: Dictionary, placed: Dictionary) -> String:
		var progress: float = (1.0 - float(placed["remaining"]) / float(placed["total"])) * 100.0
		match placed["op"]:
			"build":
				return "建造中（%.0f%%）…点击可取消建造" % progress
			"upgrade":
				return "升级中（%.0f%%）…" % progress
			"demolish":
				return "拆除中（%.0f%%）…" % progress
		return ""


	static func completed_desc(item: Dictionary, placed: Dictionary) -> String:
		return "%s\nLv.%d · 点击可升级或拆除" % [item.get("bonus_desc", ""), int(placed["level"])]


# === 建造反馈（原 building_feedback.gd）===
class BuildingFeedback:
	extends RefCounted

	## 建造反馈：施工完成/升级/拆除/清障时的动画与提示。
	## 由 explore_map 创建并注入 grid_view 与提示标签引用。
	## 设计依据：docs/design/game_design.md 3.7

	var grid_view: GridView
	var hint: Label


	func setup(grid: GridView, hint_label: Label) -> void:
		grid_view = grid
		hint = hint_label


	func on_completed(cell: Vector2i, _item_id: String) -> void:
		grid_view.completion_effects["%d,%d" % [cell.x, cell.y]] = 0.0
		grid_view.queue_redraw()
		hint.text = "建造完成！"


	func on_upgraded(cell: Vector2i, _item_id: String, level: int) -> void:
		grid_view.completion_effects["%d,%d" % [cell.x, cell.y]] = 0.0
		grid_view.queue_redraw()
		hint.text = "升级完成！当前 Lv.%d" % level


	func on_demolished(_cell: Vector2i, _item_id: String) -> void:
		grid_view.queue_redraw()
		hint.text = "拆除完成"


	func on_obstacle_cleared(_cell: Vector2i) -> void:
		grid_view.queue_redraw()


# === 建筑产出总览面板（原 map_summary.gd）===
class MapSummary:
	extends PanelContainer

	## 建筑产出总览面板：实时汇总所有已建建筑/装饰的累计加成
	## 数据来源 BuildingSystem.placed（与 BuildingSystem._recalculate_bonuses 同口径）
	## 仅作展示，不参与游戏逻辑；监听 bonus_updated 信号刷新

	const FONT_BOLD: Font = preload("res://assets/fonts/SourceHanSansCN-Bold.ttf")
	const FONT_SERIF: Font = preload("res://assets/fonts/SourceHanSerifCN-Regular.otf")

	# 汇总项定义：key 对应 buildings.json 的 bonuses 字段；is_float 决定取整方式
	const STAT_DEFS: Array[Dictionary] = [
		{"key": "gold_rate", "label": "金币/月", "color": Color(1.0, 0.85, 0.4), "is_float": true},
		{"key": "pop_max", "label": "人口上限", "color": Color(0.5, 1.0, 0.7), "is_float": false},
		{"key": "pop_growth_rate", "label": "人口/月", "color": Color(0.6, 1.0, 0.8), "is_float": true},
		{"key": "tech_rate", "label": "科技/月", "color": Color(0.6, 0.8, 1.0), "is_float": true},
		{"key": "culture_rate", "label": "文化/月", "color": Color(1.0, 0.7, 0.9), "is_float": true},
		{"key": "happiness", "label": "幸福度", "color": Color(1.0, 0.8, 0.5), "is_float": false},
	]

	var _value_labels: Dictionary = {}  # stat key -> Label


	func _ready() -> void:
		_build_ui()
		BuildingSystem.bonus_updated.connect(refresh)
		refresh()


	func _build_ui() -> void:
		# 面板样式（与 InfoPanel 的 StyleBox_info 保持一致）
		var panel_style: StyleBoxFlat = StyleBoxFlat.new()
		panel_style.bg_color = Color(0.03, 0.06, 0.14, 0.9)
		panel_style.border_width_left = 1
		panel_style.border_width_top = 1
		panel_style.border_width_right = 1
		panel_style.border_width_bottom = 1
		panel_style.border_color = Color(0.25, 0.5, 0.85, 0.4)
		panel_style.corner_radius_top_left = 10
		panel_style.corner_radius_top_right = 10
		panel_style.corner_radius_bottom_right = 10
		panel_style.corner_radius_bottom_left = 10
		panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.3)
		panel_style.shadow_size = 8
		panel_style.shadow_offset = Vector2(0, 3)
		add_theme_stylebox_override("panel", panel_style)

		var vbox: VBoxContainer = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 6)
		vbox.add_theme_constant_override("margin_left", 14)
		vbox.add_theme_constant_override("margin_top", 10)
		vbox.add_theme_constant_override("margin_right", 14)
		vbox.add_theme_constant_override("margin_bottom", 10)
		add_child(vbox)

		var title: Label = Label.new()
		title.text = "建筑产出总览"
		title.add_theme_color_override("font_color", Color(0.42, 0.72, 1.0, 0.95))
		title.add_theme_font_override("font", FONT_BOLD)
		title.add_theme_font_size_override("font_size", 18)
		vbox.add_child(title)

		var hbox: HBoxContainer = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 22)
		vbox.add_child(hbox)

		for def: Dictionary in STAT_DEFS:
			_add_stat(hbox, def)


	func _add_stat(parent: Control, def: Dictionary) -> void:
		var col: VBoxContainer = VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var value: Label = Label.new()
		value.add_theme_color_override("font_color", def["color"])
		value.add_theme_font_override("font", FONT_BOLD)
		value.add_theme_font_size_override("font_size", 18)
		value.text = _format(0.0, def["is_float"])
		var name_label: Label = Label.new()
		name_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95, 0.8))
		name_label.add_theme_font_override("font", FONT_SERIF)
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.text = def["label"]
		col.add_child(value)
		col.add_child(name_label)
		parent.add_child(col)
		_value_labels[def["key"]] = value


	func refresh() -> void:
		# 与 BuildingSystem._recalculate_bonuses 同口径：累加所有 placed 的 bonuses × 等级
		var totals: Dictionary = {}
		for def: Dictionary in STAT_DEFS:
			totals[def["key"]] = 0.0
		for key: String in BuildingSystem.placed:
			var p: Dictionary = BuildingSystem.placed[key]
			var level: int = int(p["level"])
			var item: Dictionary = BuildingSystem.get_item(p["item_id"])
			var bonuses: Dictionary = item.get("bonuses", {})
			for def: Dictionary in STAT_DEFS:
				var stat_key: String = def["key"]
				totals[stat_key] += float(bonuses.get(stat_key, 0.0)) * float(level)
		for def: Dictionary in STAT_DEFS:
			var stat_key: String = def["key"]
			var label: Label = _value_labels[stat_key]
			var new_text: String = _format(float(totals[stat_key]), def["is_float"])
			if label.text != new_text:
				label.text = new_text
				UiAnim.value_flash(label)  # 数值变化闪烁提示


	func _format(value: float, is_float: bool) -> String:
		if is_float:
			return "+%.1f" % value
		return "+%d" % int(value)





