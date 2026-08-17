extends Control

## 临时测试：持续保存渲染 buffer + 打印状态（配合外部拖拽）

var _t: float = 0.0
var _n: int = 0


func _process(delta: float) -> void:
	_t += delta
	if _t > 2.0:
		_t = 0.0
		_n += 1
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("C:/Users/Administrator/AppData/Local/Temp/opencode/buf_%02d.png" % _n)
		print("[", _n, "] buffer=", img.get_size(),
				" win.size=", get_window().size,
				" win.pos=", get_window().position,
				" csf=", get_viewport().content_scale_factor)