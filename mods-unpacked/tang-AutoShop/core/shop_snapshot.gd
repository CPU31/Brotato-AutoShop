extends Reference

# 依据：本机 items/global/category.gd 的枚举顺序。
const CATEGORY_ITEM = 0
const CATEGORY_WEAPON = 1


static func read_slot(slot, index):
	if not is_instance_valid(slot):
		return {"slot": index, "error": "invalid_slot"}
	# 依据：本机 ui/menus/shop/shop_item.gd 的商品状态字段。
	for key in ["active", "item_data", "value", "locked"]:
		if not has_property(slot, key):
			return {"slot": index, "error": "missing_slot_property:" + key}
	if not slot.get("active"):
		return {"slot": index, "active": false}
	var data = slot.get("item_data")
	if not is_instance_valid(data):
		return {"slot": index, "error": "missing_item_data"}
	# 依据：本机 items/global/item_parent_data.gd 的物品身份字段。
	for key in ["my_id", "name"]:
		if not has_property(data, key):
			return {"slot": index, "error": "missing_item_property:" + key}
	if not data.has_method("get_category"):
		return {"slot": index, "error": "missing_get_category"}
	var category = data.get_category()
	var price = slot.get("value")
	if not (price is int or price is float) or price < 0 or price != int(price):
		return {"slot": index, "error": "invalid_price"}
	# 这里只报告已核对的分类，不把所有非武器都猜成普通道具。
	return {
		"slot": index, "active": true,
		"id": str(data.get("my_id")),
		"name": data.tr(str(data.get("name"))),
		"name_key": str(data.get("name")),
		"price": int(price), "locked": slot.get("locked"),
		"category": category, "is_weapon": category == CATEGORY_WEAPON,
		"is_item": category == CATEGORY_ITEM
	}


static func has_property(object, key):
	if not is_instance_valid(object):
		return false
	for property in object.get_property_list():
		if property.name == key:
			return true
	return false


static func read_shop(shop, run_data, valid_ids, rerolls):
	if not is_instance_valid(shop) or not shop.is_inside_tree() or not shop.is_visible_in_tree():
		return {"error": "shop_closed"}
	for method in ["_get_shop_items_container", "_on_RerollButton_pressed"]:
		if not shop.has_method(method):
			return {"error": "missing_shop_api"}
	for method in ["get_player_gold", "get_player_currency", "get_player_locked_shop_items", "get_player_effect_bool", "get_player_count"]:
		if not is_instance_valid(run_data) or not run_data.has_method(method):
			return {"error": "missing_run_data_api"}
	if run_data.get_player_count() != 1:
		return {"error": "coop_not_supported"}
	var container = shop._get_shop_items_container(0)
	if not has_property(container, "_shop_items"):
		return {"error": "missing_slots"}
	var slots = container.get("_shop_items")
	var costs = shop.get("_reroll_price") if has_property(shop, "_reroll_price") else []
	var counters = shop.get("_reroll_count") if has_property(shop, "_reroll_count") else []
	if not slots is Array or not costs is Array or costs.empty():
		return {"error": "invalid_shop_state"}
	if not counters is Array or counters.empty() or not (counters[0] is int or counters[0] is float):
		return {"error": "invalid_reroll_counter"}
	if not (costs[0] is int or costs[0] is float) or costs[0] < 0 or costs[0] != int(costs[0]):
		return {"error": "invalid_reroll_price"}
	var items = []
	for index in range(slots.size()):
		var item = read_slot(slots[index], index)
		item["catalog_valid"] = valid_ids.has(item.get("id", ""))
		items.append(item)
	# 依据：RunData 货币 API、Keys.hp_shop_hash、BaseShop 刷新前的锁定数量检查。
	return {
		"items": items, "gold": run_data.get_player_gold(0),
		"currency": run_data.get_player_currency(0),
		"hp_shop": run_data.get_player_effect_bool(Keys.hp_shop_hash, 0),
		"reroll_cost": costs[0], "auto_rerolls": rerolls,
		"reroll_blocked": run_data.get_player_locked_shop_items(0).size() >= 4
	}
