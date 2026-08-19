extends Control
class_name ExploreMap

## 地图与探索界面：左侧建筑菜单 + 中央网格建设区
## 设计依据：docs/design/game_design.md 3.7
## 模块：building_action_panel.gd（操作面板）、building_info.gd（悬停文案）、map_summary.gd（汇总）

# 建筑产出总览面板定位（网格下方空白区，设计坐标系 1280×720）
const SUMMARY_RECT: Rect2 = Rect2(260, 596, 1010, 84)

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
	BuildingSystem.grid_changed.connect(func(_cell: Vector2i) -> void: grid_view.queue_redraw())
	BuildingSystem.building_completed.connect(_feedback.on_completed)
	BuildingSystem.building_upgraded.connect(_feedback.on_upgraded)
	BuildingSystem.building_demolished.connect(_feedback.on_demolished)
	BuildingSystem.obstacle_cleared.connect(_feedback.on_obstacle_cleared)
	action_upgrade_btn.pressed.connect(_on_upgrade_pressed)
	action_demolish_btn.pressed.connect(_on_demolish_pressed)
	%ActionCloseBtn.pressed.connect(_close_action_panel)


# === 菜单选择 ===

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
		_show_info(selected_item["name"], "点击放置（%d 金币）" % int(selected_item["cost"]))
	else:
		_show_info(selected_item["name"], "位置不可用：被占用或超出边界")


# === 点击 ===

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
	if BuildingSystem.upgrade_building(BuildingGrid.key_to_cell(key)):
		info_hint.text = "开始升级，完成后加成提升！"
		_close_action_panel()
		grid_view.queue_redraw()
	else:
		info_hint.text = "无法升级：金币不足或已达最高等级"


func _on_demolish_pressed() -> void:
	var key: String = _action_ctrl.current_key()
	if key.is_empty():
		return
	if BuildingSystem.start_demolish(BuildingGrid.key_to_cell(key)):
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
