class_name BuildingFeedback
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
