extends Control
class_name ExploreMap

## 地图与探索界面：左侧建筑菜单 + 中央网格建设区
## 设计依据：docs/design/game_design.md 3.7

@onready var menu: BuildingMenu = %MenuList
@onready var grid_view: GridView = %GridView
@onready var info_panel: PanelContainer = %InfoPanel
@onready var info_title: Label = %InfoTitle
@onready var info_desc: Label = %InfoDesc
@onready var info_hint: Label = %InfoHint
@onready var action_panel: PanelContainer = %ActionPanel
@onready var action_title: Label = %ActionTitle
@onready var action_desc: Label = %ActionDesc
@onready var action_upgrade_btn: Button = %ActionUpgradeBtn
@onready var action_demolish_btn: Button = %ActionDemolishBtn
@onready var action_close_btn: Button = %ActionCloseBtn

var selected_item: Dictionary = {}
var action_key: String = ""  # 操作面板当前建筑的 placed key


func _ready() -> void:
	_connect_signals()
	info_panel.hide()
	action_panel.hide()
	info_hint.text = "选择左侧建筑后，点击网格放置；点击障碍可花费金币清除"
	_add_summary_panel()


func _add_summary_panel() -> void:
	# 建筑产出总览：悬于网格下方空白区，鼠标穿透不阻挡建造点击
	var summary := MapSummary.new()
	summary.name = "SummaryPanel"
	summary.anchor_left = 0.0
	summary.anchor_top = 0.0
	summary.anchor_right = 0.0
	summary.anchor_bottom = 0.0
	summary.offset_left = 260.0
	summary.offset_top = 596.0
	summary.offset_right = 1270.0
	summary.offset_bottom = 680.0
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(summary)


func _connect_signals() -> void:
	menu.item_selected.connect(_on_item_selected)
	grid_view.hover_changed.connect(_on_hover_changed)
	grid_view.cell_clicked.connect(_on_cell_clicked)
	BuildingSystem.grid_changed.connect(func(_cell: Vector2i) -> void: grid_view.queue_redraw())
	BuildingSystem.building_placed.connect(_on_building_placed)
	BuildingSystem.building_completed.connect(_on_building_completed)
	BuildingSystem.obstacle_cleared.connect(_on_obstacle_cleared)
	BuildingSystem.building_upgraded.connect(_on_building_upgraded)
	BuildingSystem.building_demolished.connect(_on_building_demolished)
	action_upgrade_btn.pressed.connect(_on_upgrade_pressed)
	action_demolish_btn.pressed.connect(_on_demolish_pressed)
	action_close_btn.pressed.connect(_close_action_panel)


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
		return
	if BuildingSystem.is_obstacle(cell):
		var obs: Dictionary = BuildingSystem.get_obstacle_at(cell)
		_show_info(obs["name"], "清除需 %d 金币\n点击障碍即可清除" % int(obs["clear_cost"]))
	elif selected_item.is_empty():
		var placed: Dictionary = BuildingSystem.get_placed_at(cell)
		if not placed.is_empty():
			var item: Dictionary = BuildingSystem.get_item(placed["item_id"])
			match placed["op"]:
				"build":
					_show_info(item["name"], "建造中（%.0f%%）…点击可取消建造" % \
							((1.0 - float(placed["remaining"]) / float(placed["total"])) * 100.0))
				"upgrade":
					_show_info(item["name"], "升级中（%.0f%%）…" % \
							((1.0 - float(placed["remaining"]) / float(placed["total"])) * 100.0))
				"demolish":
					_show_info(item["name"], "拆除中（%.0f%%）…" % \
							((1.0 - float(placed["remaining"]) / float(placed["total"])) * 100.0))
				_:
					_show_info(item["name"],
							"%s\nLv.%d · 点击可升级或拆除" % [item["bonus_desc"], int(placed["level"])])
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


# === 操作面板（升级/拆除）===

func _open_action_panel(key: String) -> void:
	# 点击已完工建筑弹出操作面板：显示等级、加成、升级费用与拆除返还
	var p: Dictionary = BuildingSystem.placed[key]
	var item: Dictionary = BuildingSystem.get_item(p["item_id"])
	action_key = key
	var level: int = int(p["level"])
	action_title.text = "%s  Lv.%d" % [item["name"], level]
	action_desc.text = "%s\n\n升级费用：%d 金币\n拆除返还：%d 金币" % [
		item["bonus_desc"],
		int(BuildingSystem.get_upgrade_cost(p)),
		int(BuildingSystem.get_demolish_refund(p)),
	]
	if level >= BuildingSystem.MAX_LEVEL:
		action_upgrade_btn.text = "已达最高等级"
		action_upgrade_btn.disabled = true
	else:
		action_upgrade_btn.text = "升级至 Lv.%d（%d 金币）" % [
			level + 1, int(BuildingSystem.get_upgrade_cost(p)),
		]
		action_upgrade_btn.disabled = GameState.gold < BuildingSystem.get_upgrade_cost(p)
	action_demolish_btn.text = "拆除（返还 %d 金币）" % int(BuildingSystem.get_demolish_refund(p))
	action_panel.show()


func _close_action_panel() -> void:
	action_panel.hide()
	action_key = ""


func _on_upgrade_pressed() -> void:
	if action_key.is_empty():
		return
	var cell: Vector2i = _key_to_cell(action_key)
	if BuildingSystem.upgrade_building(cell):
		info_hint.text = "开始升级，完成后加成提升！"
		_close_action_panel()
		grid_view.queue_redraw()
	else:
		info_hint.text = "无法升级：金币不足或已达最高等级"


func _on_demolish_pressed() -> void:
	if action_key.is_empty():
		return
	var cell: Vector2i = _key_to_cell(action_key)
	if BuildingSystem.start_demolish(cell):
		info_hint.text = "开始拆除…完成后返还金币"
		_close_action_panel()
		grid_view.queue_redraw()
	else:
		info_hint.text = "无法拆除：建筑正在施工中"


# === 建造反馈 ===

func _on_building_placed(_cell: Vector2i, _item_id: String) -> void:
	pass


func _on_building_completed(cell: Vector2i, _item_id: String) -> void:
	grid_view.completion_effects["%d,%d" % [cell.x, cell.y]] = 0.0
	grid_view.queue_redraw()
	info_hint.text = "建造完成！"


func _on_building_upgraded(cell: Vector2i, _item_id: String, level: int) -> void:
	grid_view.completion_effects["%d,%d" % [cell.x, cell.y]] = 0.0
	grid_view.queue_redraw()
	info_hint.text = "升级完成！当前 Lv.%d" % level


func _on_building_demolished(_cell: Vector2i, _item_id: String) -> void:
	grid_view.queue_redraw()
	info_hint.text = "拆除完成"


func _on_obstacle_cleared(_cell: Vector2i) -> void:
	grid_view.queue_redraw()


# === 工具 ===

func _grid_view_can_build(cell: Vector2i) -> bool:
	var w: int = int(selected_item.get("width", 1))
	var h: int = int(selected_item.get("height", 1))
	return grid_view.can_build_at(cell, w, h)


func _show_info(title: String, desc: String) -> void:
	info_title.text = title
	info_desc.text = desc
	info_panel.show()


func _key_to_cell(key: String) -> Vector2i:
	var parts: PackedStringArray = key.split(",")
	return Vector2i(int(parts[0]), int(parts[1]))