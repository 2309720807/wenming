extends Node

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var win: Window = get_window()
	print("--- authoritative data ---")
	print("win.size (logical): ", win.size)
	print("DisplayServer.window_get_size: ", DisplayServer.window_get_size())
	print("screen size: ", DisplayServer.screen_get_size())
	print("screen DPI: ", DisplayServer.screen_get_dpi())
	print("allow_hidpi: ", ProjectSettings.get_setting("display/window/dpi/allow_hidpi"))
	print("stretch mode: ", ProjectSettings.get_setting("display/window/stretch/mode"))
	print("aspect: ", ProjectSettings.get_setting("display/window/stretch/aspect"))
	print("content_scale_factor: ", win.content_scale_factor)
	print("content_scale_size: ", win.content_scale_size)
	print("visible_rect: ", get_viewport().get_visible_rect().size)
	win.size = Vector2i(1500, 844)
	await get_tree().process_frame
	await get_tree().process_frame
	print("--- after win.size=1500x844 ---")
	print("win.size: ", win.size)
	print("DisplayServer.window_get_size: ", DisplayServer.window_get_size())
	print("content_scale_factor: ", win.content_scale_factor)
	print("content_scale_size: ", win.content_scale_size)
	print("visible_rect: ", get_viewport().get_visible_rect().size)
	get_tree().quit()