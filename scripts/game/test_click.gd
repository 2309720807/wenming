extends Control

## 临时测试：注入点击事件验证 InfoPanel 穿透 + 建造流程

var _t: float = 0.0
var _step: int = 0


func _process(delta: float) -> void:
	_t += delta
	match _step:
		0:
			if _t > 2.0:
				_click(132, 135)  # 菜单"住宅"卡片
				_step = 1
				_t = 0.0
		1:
			if _t > 0.6:
				var m: Control = get_node("Map")
				print("selected_item: ", m.selected_item)
				print("preview_item: ", m.grid_view.preview_item)
				print("MenuList children: ",
						get_node("Map/Layout/MenuPanel/VBox/Scroll/MenuList").get_child_count())
				_click(685, 490)  # InfoPanel 覆盖区域内的网格 (10,11)
				_step = 2
				_t = 0.0
		2:
			if _t > 1.0:
				print("placed keys: ", BuildingSystem.placed.keys())
				print("grid[10][11]: ", BuildingSystem.grid[10][11])
				print("gold: ", GameState.gold)
				var img: Image = get_viewport().get_texture().get_image()
				img.save_png("C:/Users/Administrator/AppData/Local/Temp/opencode/godot_click.png")
				_step = 3
		3:
			get_tree().quit()


func _click(x: float, y: float) -> void:
	var down := InputEventMouseButton.new()
	down.position = Vector2(x, y)
	down.global_position = Vector2(x, y)
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	Input.parse_input_event(down)
	var up := down.duplicate()
	up.pressed = false
	Input.parse_input_event(up)