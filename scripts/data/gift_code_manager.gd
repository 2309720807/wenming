extends Node

## 礼包码管理器（Autoload 单例）
## 加载 data/gift_codes.json，校验并发放礼包奖励，防止重复兑换。
## 数据层职责：验证逻辑与发奖在此处理，UI 层仅调用 redeem()。

const GIFT_CODES_PATH: String = "res://data/gift_codes.json"

var _codes: Dictionary = {}
var _redeemed: Dictionary = {}  # 已兑换码（本次运行内防重复）


func _ready() -> void:
	_load_codes()


func _load_codes() -> void:
	if not FileAccess.file_exists(GIFT_CODES_PATH):
		push_warning("礼包码配置文件不存在: %s" % GIFT_CODES_PATH)
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(GIFT_CODES_PATH))
	if data is Dictionary and data.get("codes") is Dictionary:
		_codes = data["codes"]


## 兑换礼包码，返回 {ok: bool, message: String}
func redeem(code_text: String) -> Dictionary:
	var code: String = code_text.strip_edges().to_upper()
	if code.is_empty():
		return {"ok": false, "message": "请输入礼包码"}
	if not _codes.has(code):
		return {"ok": false, "message": "无效的礼包码"}
	if _redeemed.has(code):
		return {"ok": false, "message": "该礼包码已兑换过"}
	var reward: Dictionary = _codes[code]
	_redeemed[code] = true
	GameState.add_gold(float(reward.get("gold", 0)))
	return {
		"ok": true,
		"message": "兑换成功：%s（金币 +%d）" % [reward.get("desc", "礼包"), int(reward.get("gold", 0))],
	}
