extends Node

const Snapshot = preload("res://mods-unpacked/tang-AutoShop/core/shop_snapshot.gd")
const Decision = preload("res://mods-unpacked/tang-AutoShop/core/decision.gd")
# 原生购买冷却为 0.05 秒；动作间隔留半秒，便于玩家看清变化和及时接管。
const ACTION_DELAY = 0.5
const MAX_BUSY_RETRIES = 3
# 不限制正常刷新次数；仅防止 Mod 改出永远免费的商店导致无界自动流程。
const MAX_CONSECUTIVE_FREE_REROLLS = 100

var host
var token = 0
var running = false
var last_reason = "待命"


func stop(reason = "manual_interrupt"):
	token += 1
	if running:
		host.log_line("STOP " + reason)
	running = false
	last_reason = reason
	if is_instance_valid(host):
		host.status_changed()


func start(shop):
	stop("restart")
	if not is_instance_valid(shop) or not host.config_loaded:
		last_reason = "没有可用的单人商店"
		host.log_line("STOP no_shop")
		return
	if host.panel_open() or get_tree().paused:
		last_reason = "配置面板或暂停菜单已打开"
		return
	var config = host.config.duplicate(true)
	if not config.enabled:
		last_reason = "disabled"
		host.log_line("STOP disabled")
		return
	var has_loaded_target = config.whitelist.empty()
	for id in config.whitelist:
		if host.valid_ids.has(id):
			has_loaded_target = true
	if not has_loaded_target:
		last_reason = "no_loaded_targets"
		host.log_line("STOP no_loaded_targets")
		return
	running = true
	last_reason = "执行中"
	host.status_changed()
	var current_token = token
	_drive(weakref(shop), config, current_token)


func _drive(shop_ref, config, current_token):
	var count = 0
	var busy_retries = 0
	var free_rerolls = 0
	while current_token == token and running:
		var shop = shop_ref.get_ref()
		if not is_instance_valid(shop) or not shop.is_inside_tree():
			stop("shop_closed")
			return
		if get_tree().paused or host.panel_open():
			stop("paused")
			return
		var go = shop.get("_player_pressed_go_button")
		if go is Array and not go.empty() and go[0]:
			stop("leaving_shop")
			return
		var state = host.snapshot(shop, count)
		if state.has("error"):
			stop(str(state.error))
			return
		var container = shop._get_shop_items_container(0)
		if Snapshot.has_property(container, "_is_delay_active") and container.get("_is_delay_active"):
			busy_retries += 1
			if busy_retries > MAX_BUSY_RETRIES:
				stop("shop_busy")
				return
			yield(get_tree().create_timer(ACTION_DELAY), "timeout")
			continue
		busy_retries = 0
		if config.verbose:
			for item in state.items:
				var report = item.duplicate(true)
				report["reason"] = Decision.explain(item, state, config)
				host.log_line("CANDIDATE " + JSON.print(report), config.dry_run)
		var action = Decision.decide(state, config)
		if action.action == "stop":
			if can_depart(state, config, action.reason):
				_depart(shop_ref, config, current_token, count)
				return
			stop(action.reason)
			return
		host.log_line("ACTION " + JSON.print(action) + " gold=" + str(state.gold), config.dry_run)
		if config.dry_run:
			stop("dry_run_decision_only")
			return
		if action.action == "buy":
			if not container.has_method("on_shop_item_buy_button_pressed"):
				stop("missing_buy_api")
				return
			var slots = container.get("_shop_items")
			if action.slot < 0 or action.slot >= slots.size():
				stop("invalid_slot_index")
				return
			var slot = slots[action.slot]
			# 依据：ShopItemsContainer 原生入口处理扣款、信号、商品失活和购买冷却；返回 void。
			container.on_shop_item_buy_button_pressed(slot)
			if is_instance_valid(slot) and slot.get("active") == true:
				stop("purchase_not_completed")
				return
			host.log_line("BUY_CONFIRMED " + action.id)
		else:
			var previous_count = shop.get("_reroll_count")[0]
			# 依据：BaseShop 原生刷新入口返回 void，内部扣款并增加 _reroll_count。
			shop._on_RerollButton_pressed(0)
			if shop.get("_reroll_count")[0] <= previous_count:
				stop("reroll_not_completed")
				return
			count += 1
			free_rerolls = free_rerolls + 1 if action.price == 0 else 0
			if free_rerolls >= MAX_CONSECUTIVE_FREE_REROLLS:
				stop("free_reroll_guard")
				return
		yield(get_tree().create_timer(ACTION_DELAY), "timeout")


static func can_depart(state, config, reason):
	return config.get("auto_depart", false) and config.get("enabled", false) and reason == "insufficient_gold" and state.get("reroll_cost", 0) > 0 and state.get("gold", 0) < state.reroll_cost


func _depart(shop_ref, config, current_token, count):
	if config.dry_run:
		host.log_line("AUTO_DEPART would_depart=true", true)
		stop("dry_run_decision_only")
		return
	# 在离店前再等待半秒；这段时间内人工操作仍能通过 token 取消。
	yield(get_tree().create_timer(ACTION_DELAY), "timeout")
	if current_token != token or not running:
		return
	if host.panel_open() or get_tree().paused:
		stop("paused")
		return
	var shop = shop_ref.get_ref()
	if not is_instance_valid(shop) or not shop.is_inside_tree() or not shop.is_visible_in_tree():
		stop("shop_closed")
		return
	var state = host.snapshot(shop, count)
	if state.has("error") or not can_depart(state, config, Decision.decide(state, config).get("reason", "")):
		stop("auto_depart_state_changed")
		return
	for method in ["_get_go_button", "_on_GoButton_pressed"]:
		if not shop.has_method(method):
			stop("missing_go_api")
			return
	var button = shop._get_go_button(0)
	var pressed = shop.get("_player_pressed_go_button")
	if not is_instance_valid(button) or not button.is_visible_in_tree() or button.get("disabled") != false or not pressed is Array or pressed.empty() or pressed[0]:
		stop("go_unavailable")
		return
	host.log_line("AUTO_DEPART gold=" + str(state.gold) + " reroll_cost=" + str(state.reroll_cost))
	stop("auto_depart")
	# 依据：BaseShop._on_GoButton_pressed(0) 保存当前局并切换战斗场景，不能自行切场景。
	shop._on_GoButton_pressed(0)
