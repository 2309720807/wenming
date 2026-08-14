class_name Enemy
extends StaticBody2D

## 测试敌人：静态靶子，受子弹伤害，血量归零销毁

@export var max_hp: int = 30

var hp: int


func _ready() -> void:
	hp = max_hp


func take_damage(amount: int) -> void:
	hp -= amount
	if hp <= 0:
		queue_free()