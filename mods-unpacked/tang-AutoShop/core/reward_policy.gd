extends Reference


static func decide(id, category, config):
	if not config.get("enabled", false):
		return {"action": "stop", "reason": "disabled"}
	if id.empty() or not category in [0, 1]:
		return {"action": "stop", "reason": "unsupported_reward"}
	# 发现道具不消费金币，不应用商店价格上限或留金币规则。
	if category == 0 and config.get("whitelist", []).has(id):
		return {"action": "take", "id": id}
	# 用户明确要求：不在白名单的发现道具直接回收；空白名单在此表示全部回收。
	return {"action": "recycle", "id": id}
