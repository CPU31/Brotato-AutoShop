extends "res://ui/menus/shop/shop.gd"

# 依据：用户设置的商店初始化延迟；Godot 3 自动沿继承链调用 _ready。
const AUTOSHOP_MIN_DELAY = 0.2


func _ready():
	call_deferred("_autoshop_attach")


func _autoshop_attach():
	var mod = get_node_or_null("/root/ModLoader/tang-AutoShop")
	if not is_instance_valid(mod) or mod.get("config_loaded") != true:
		return
	var delay = max(AUTOSHOP_MIN_DELAY, mod.config.get("confirm_delay", AUTOSHOP_MIN_DELAY))
	yield(get_tree().create_timer(delay), "timeout")
	if is_inside_tree() and is_instance_valid(mod) and mod.has_method("attach_shop"):
		mod.attach_shop(self)
