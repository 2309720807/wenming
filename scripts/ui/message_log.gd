extends RichTextLabel
class_name MessageLog

## 消息日志组件：封装统一的消息样式（BBCode 颜色）。
## 设计依据：docs/design/game_design.md（界面 UI 布局 - 消息日志）
## 挂在主界面 MessageLog 节点上，避免 UI 脚本内联样式魔法值。

const MESSAGE_COLOR: String = "#88aacc"


func add_message(text: String) -> void:
	append_text("[color=%s]%s[/color]\n" % [MESSAGE_COLOR, text])
