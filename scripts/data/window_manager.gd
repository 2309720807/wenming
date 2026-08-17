extends Node

## 窗口等比例缩放管理（Autoload 单例）
## 背景：Godot 4.7.1 在 canvas_items 拉伸模式下，窗口调整大小后 content_scale_factor
## 不自动更新（引擎 bug），导致画面内容不随窗口缩放。此管理器监听窗口尺寸变化，
## 手动计算并设置 content_scale_factor，实现 1280×720 设计分辨率的等比例缩放。

const DESIGN_SIZE: Vector2 = Vector2(1280, 720)


func _ready() -> void:
	get_window().size_changed.connect(_on_size_changed)
	_on_size_changed()


func _on_size_changed() -> void:
	# factor = 短边比例，保证 1280×720 内容完整可见且不变形
	var win: Window = get_window()
	var factor: float = minf(float(win.size.x) / DESIGN_SIZE.x, float(win.size.y) / DESIGN_SIZE.y)
	if factor <= 0.0:
		factor = 1.0
	get_viewport().content_scale_factor = factor