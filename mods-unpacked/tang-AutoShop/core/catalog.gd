extends Reference

const Snapshot = preload("res://mods-unpacked/tang-AutoShop/core/shop_snapshot.gd")
const PRESET_NAMES = ["蜂蜜", "导弹", "被腐蚀的碎片", "grind的魔法树叶", "镜子"]
# 依据：本机对应 *_data.tres 的 my_id；前三区域来自基础包，后两件含 DLC。
const PRESET_IDS = ["item_honey", "item_missile", "item_corrupted_shard", "item_grinds_magical_leaf", "item_mirror"]


static func read(service):
	var catalog = []
	var ids = {}
	# 依据：本机 singletons/item_service.gd:export items。
	if not Snapshot.has_property(service, "items"):
		return catalog
	var items = service.get("items")
	if not items is Array:
		return catalog
	for item in items:
		if not is_shop_item(item):
			continue
		if not Snapshot.has_property(item, "my_id") or not Snapshot.has_property(item, "name"):
			continue
		var id = str(item.get("my_id"))
		if id.empty() or ids.has(id):
			continue
		ids[id] = true
		var icon = null
		# 依据：本机 item_parent_data.gd:get_icon，包含当前皮肤。
		if item.has_method("get_icon"):
			icon = item.get_icon()
		catalog.append({"id": id, "name": item.tr(str(item.get("name"))), "icon": icon, "data": item})
	catalog.sort_custom(load("res://mods-unpacked/tang-AutoShop/core/catalog.gd").new(), "_sort_name")
	return catalog


static func is_shop_item(item):
	if not is_instance_valid(item) or not item.has_method("get_category"):
		return false
	if item.get_category() != Snapshot.CATEGORY_ITEM:
		return false
	# 依据：ItemService.init_unlocked_pool 排除不可掉落和 max_nb=0 的物品。
	# Hextech phenomenal_evil/loot.gd 生成的角色部件明确设置 can_be_looted=false。
	if not Snapshot.has_property(item, "can_be_looted") or item.get("can_be_looted") != true:
		return false
	return Snapshot.has_property(item, "max_nb") and item.get("max_nb") != 0


func _sort_name(a, b):
	return a.name.nocasecmp_to(b.name) < 0


static func resolve_presets(catalog):
	var ids = []
	var missing = []
	for index in range(PRESET_NAMES.size()):
		var name = PRESET_NAMES[index]
		var matches = []
		for item in catalog:
			if item.id == PRESET_IDS[index]:
				matches.append(item.id)
		if matches.size() == 1:
			ids.append(matches[0])
		else:
			missing.append(name)
	return {"ids": ids, "missing": missing}
