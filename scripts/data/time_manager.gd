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

	# Autoload 单例可直接以全局标识符访问
	if new_year != GameState.year or new_month != GameState.month:
		GameState.set_month(new_year, new_month)
		_process_monthly_update()
		month_processed.emit(new_year, new_month)


func _process_monthly_update() -> void:
	# 资源增长：走 GameState 的 add_* API，触发信号通知 UI 刷新
	GameState.add_gold(GameState.gold_rate)
	GameState.add_food(GameState.food_rate)
	GameState.add_wood(GameState.wood_rate)
	GameState.add_stone(GameState.stone_rate)
	GameState.add_metal(GameState.metal_rate)

	# 人口增长（受幸福度影响）：小数累积，满 1 才转化人口
	var growth_modifier: float = GameState.happiness / 100.0
	GameState.accumulate_population_growth(GameState.pop_growth_rate * growth_modifier)

	# 科技和文化进度
	GameState.add_tech(GameState.tech_rate)
	GameState.add_culture(GameState.culture_rate)

	# 幸福度小幅波动
	GameState.set_happiness(
		GameState.happiness + randi_range(-1, 2)
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


func reset_time() -> void:
	## 新游戏开局：游戏时间归零（第 1 年 1 月），避免继承上次存档时间
	game_time = 0.0
	GameState.set_month(1, 1)


func sync_to_save(year: int, month: int) -> void:
	## 加载存档后对齐游戏时间：game_time 换算为存档年月对应的累计秒数，
	## 避免 _process 用"本次启动运行时长"覆盖存档时间（修复：不同存档进入后时间被抹平）
	game_time = float(((year - 1) * 12 + (month - 1)) * SECONDS_PER_MONTH)
