extends Reference


# 只依赖输入字典；不触碰游戏节点，不改变原始状态。
static func decide(state, config):
	if not config.get("enabled", false):
		return stop("disabled")
	var whitelist = config.get("whitelist", [])
	if whitelist.empty():
		return stop("empty_whitelist")
	if state.has("error"):
		return stop(str(state.error))
	var gold = state.gold
	var currency = state.currency
	var reserve = config.keep_gold
	for item in state.items:
		if item.has("error"):
			return stop("invalid_slot")
		if not item.get("active", false) or not item.get("is_item", false):
			continue
		if not whitelist.has(item.id) or not item.get("catalog_valid", false):
			continue
		if item.price < 0:
			return stop("invalid_price")
		if config.max_item_price >= 0 and item.price > config.max_item_price:
			continue
		# HP 商店使用游戏自身货币；至少保留 1 最大生命，材料预算仍约束刷新。
		var floor_value = 1 if state.hp_shop else reserve
		if currency - item.price >= floor_value:
			return {"action": "buy", "slot": item.slot, "id": item.id, "price": item.price}
	if state.get("reroll_blocked", false):
		return stop("all_locked")
	if config.max_rerolls >= 0 and state.auto_rerolls >= config.max_rerolls:
		return stop("max_rerolls")
	if state.reroll_cost < 0:
		return stop("invalid_reroll_price")
	if config.max_reroll_cost >= 0 and state.reroll_cost > config.max_reroll_cost:
		return stop("reroll_cost")
	if gold - state.reroll_cost < reserve:
		return stop("insufficient_gold")
	return {"action": "reroll", "price": state.reroll_cost}


static func stop(reason):
	return {"action": "stop", "reason": reason}


static func explain(item, state, config):
	if item.has("error"):
		return str(item.error)
	if not item.get("active", false):
		return "inactive_slot"
	if not item.get("is_item", false):
		return "weapon_or_non_item"
	if not config.whitelist.has(item.id):
		return "not_whitelisted"
	if not item.get("catalog_valid", false):
		return "unloaded_item"
	if config.max_item_price >= 0 and item.price > config.max_item_price:
		return "item_price_limit"
	var floor_value = 1 if state.hp_shop else config.keep_gold
	if state.currency - item.price < floor_value:
		return "insufficient_currency_or_reserve"
	return "buy_candidate"
