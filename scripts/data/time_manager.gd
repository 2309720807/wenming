extends Node

## 时间管理器（Autoload 单例）
## 控制游戏时间流逝，触发月度更新

# === 信号 ===
signal month_processed(year: int, month: int)
signal speed_changed(new_speed: float)
signal paused_changed(is_paused: bool)

# === 时间设置 ===
const SECONDS_PER_MONTH: float = 5.0  # 现实5秒 = 游戏1个月

# === 时间状态 ===
var game_time: float = 0.0
var time_speed: float = 1.0
var is_paused: bool = false


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	if is_paused:
		return

	game_time += delta * time_speed

	var current_month_index: int = int(game_time / SECONDS_PER_MONTH) + 1
	var new_year: int = (current_month_index - 1) / 12 + 1
	var new_month: int = ((current_month_index - 1) % 12) + 1

	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state:
		if new_year != game_state.year or new_month != game_state.month:
			game_state.set_month(new_year, new_month)
			_process_monthly_update()
			month_processed.emit(new_year, new_month)


func _process_monthly_update() -> void:
	var game_state: Node = get_node_or_null("/root/GameState")
	if not game_state:
		return

	# 资源增长
	game_state.gold += game_state.gold_rate
	game_state.food += game_state.food_rate
	game_state.wood += game_state.wood_rate
	game_state.stone += game_state.stone_rate
	game_state.metal += game_state.metal_rate

	# 人口增长（受幸福度影响）
	var growth_modifier: float = game_state.happiness / 100.0
	var new_pop: int = game_state.population + int(game_state.pop_growth_rate * growth_modifier)
	game_state.set_population(mini(new_pop, game_state.pop_max))

	# 科技和文化进度
	game_state.add_tech(game_state.tech_rate)
	game_state.add_culture(game_state.culture_rate)

	# 幸福度小幅波动
	game_state.set_happiness(
		game_state.happiness + randi_range(-1, 2)
	)


func set_speed(speed: float) -> void:
	time_speed = speed
	speed_changed.emit(speed)


func toggle_pause() -> void:
	is_paused = not is_paused
	paused_changed.emit(is_paused)


func get_speed() -> float:
	return time_speed


func get_pause_state() -> bool:
	return is_paused
