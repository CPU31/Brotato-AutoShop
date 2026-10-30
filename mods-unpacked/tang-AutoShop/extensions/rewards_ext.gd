extends "res://ui/menus/ingame/upgrades_ui_player_container.gd"


func show_item(item_data):
	# 依据：UpgradesUIPlayerContainer.show_item，普通方法覆盖需要保留父级逻辑。
	.show_item(item_data)
	var mod = get_node_or_null("/root/ModLoader/tang-AutoShop")
	if is_instance_valid(mod) and is_instance_valid(mod.rewards):
		mod.rewards.offer(self)
