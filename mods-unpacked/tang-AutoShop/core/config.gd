extends Reference

const DEFAULTS = {
	"enabled": true, "dry_run": false, "whitelist": [], "keep_gold": 0,
	"max_item_price": -1, "max_rerolls": -1, "max_reroll_cost": -1,
	"buy_weapons": false, "buy_consumables": false, "auto_depart": false,
	"confirm_delay": 0.2, "verbose": true, "preset_initialized": false
}


static func sanitize(raw):
	var result = DEFAULTS.duplicate(true)
	var warnings = []
	if not raw is Dictionary:
		return {"config": result, "warnings": ["配置不是字典，使用默认值"]}
	for key in DEFAULTS:
		if not raw.has(key):
			continue
		var value = raw[key]
		var valid = false
		if DEFAULTS[key] is bool:
			valid = value is bool
		elif key == "whitelist":
			valid = value is Array
			if valid:
				var ids = []
				for id in value:
					if id is String and not id.empty() and not ids.has(id):
						ids.append(id)
					else:
						warnings.append("忽略空、重复或非字符串物品 ID")
				value = ids
		elif key == "confirm_delay":
			valid = (value is int or value is float) and value >= 0 and value <= 60
		else:
			valid = (value is int or value is float) and value == int(value)
			valid = valid and value >= (0 if key == "keep_gold" else -1)
			if valid:
				value = int(value)
		if valid:
			result[key] = value
		else:
			warnings.append("非法配置 " + key + "，回退默认值")
	# 用户明确禁止武器、消耗品、箱子，配置文件也不能绕过。
	result.buy_weapons = false
	result.buy_consumables = false
	return {"config": result, "warnings": warnings}
