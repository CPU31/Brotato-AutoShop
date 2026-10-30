extends Node

const Snapshot = preload("res://mods-unpacked/tang-AutoShop/core/shop_snapshot.gd")
const Policy = preload("res://mods-unpacked/tang-AutoShop/core/reward_policy.gd")
const SCAN_INTERVAL = 0.1
const ACTION_DELAY = 0.5
const MAX_BUSY_WAIT = 3.0

var host
var watches = {}
var elapsed = 0.0


func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS


func watch(container):
	if not is_instance_valid(container):
		return
	var key = container.get_instance_id()
	if not watches.has(key):
		watches[key] = {"ref": weakref(container), "signature": "", "blocked": "", "done": false, "due": 0, "busy_until": 0}


func offer(container):
	watch(container)
	# 原生 show_item 每次展示一件奖励都触发，即使两次展示同一个资源也视作不同奖励。
	var state = watches[container.get_instance_id()]
	state.signature = ""
	state.done = false
	state.blocked = ""


func cancel_all():
	var cancelled = false
	for state in watches.values():
		var container = state.ref.get_ref()
		if is_instance_valid(container) and container.is_visible_in_tree():
			var items = container.get("_items_container")
			if is_instance_valid(items) and items.is_visible_in_tree():
				state.blocked = _signature(container)
				state.done = true
				cancelled = true
	if cancelled:
		host.log_line("REWARD_STOP manual_interrupt")


func _signature(container):
	var data = container.get("_item_data")
	var consumable = container.get("_consumable_data")
	return (str(data.get_instance_id()) if is_instance_valid(data) else "none") + ":" + (str(consumable.get_instance_id()) if is_instance_valid(consumable) else "none")


func _process(delta):
	elapsed += delta
	if elapsed < SCAN_INTERVAL:
		return
	elapsed = 0.0
	for key in watches.keys():
		var container = watches[key].ref.get_ref()
		if not is_instance_valid(container):
			watches.erase(key)
			continue
		_scan(container, watches[key])


func _scan(container, state):
	if not host.config_loaded or not host.reward_single_player():
		return
	# 依据：UpgradesUIPlayerContainer.show_item / show_upgrades_for_level 切换两个容器。
	if not Snapshot.has_property(container, "_items_container"):
		return
	var items = container.get("_items_container")
	if not is_instance_valid(items) or not container.is_visible_in_tree() or not items.is_visible_in_tree():
		state.signature = ""
		state.done = false
		state.blocked = ""
		return
	for property in ["_item_data", "_consumable_data", "_button_pressed", "_take_button", "_discard_button", "player_index"]:
		if not Snapshot.has_property(container, property):
			return
	if container.get("player_index") != 0:
		return
	var data = container.get("_item_data")
	if not is_instance_valid(data) or not data.has_method("get_category") or not Snapshot.has_property(data, "my_id"):
		return
	var signature = _signature(container)
	var now = OS.get_ticks_msec()
	if state.signature != signature:
		state.signature = signature
		state.done = state.blocked == signature
		state.due = now + int(max(ACTION_DELAY, host.config.get("confirm_delay", ACTION_DELAY)) * 1000)
		state.busy_until = state.due + int(MAX_BUSY_WAIT * 1000)
	if state.done or now < state.due:
		return
	if host.panel_open() or get_tree().paused:
		return
	if container.get("_button_pressed"):
		if now > state.busy_until:
			state.done = true
			host.log_line("REWARD_STOP busy")
		return
	var action = Policy.decide(str(data.get("my_id")), data.get_category(), host.config)
	if action.action == "stop":
		state.done = true
		host.log_line("REWARD_STOP " + action.reason)
		return
	var method = "_on_TakeButton_pressed" if action.action == "take" else "_on_DiscardButton_pressed"
	var button = container.get("_take_button" if action.action == "take" else "_discard_button")
	if not container.has_method(method) or not is_instance_valid(button) or not button.is_visible_in_tree() or button.get("disabled") != false:
		state.done = true
		host.log_line("REWARD_STOP missing_or_disabled_button")
		return
	# 标记必须放在调用前；原生信号可能同步展示下一件奖励并重新调用 offer。
	state.done = true
	host.log_line("REWARD_ACTION " + JSON.print(action), host.config.get("dry_run", false))
	if host.config.get("dry_run", false):
		return
	# 依据：原生 Take/Discard 入口设置冷却、更新奖励队列并发信号，main.gd 完成入包或回收加钱。
	# 不自行添加道具、加金币或弹出队列，也不直接发领取信号。
	container.call(method)
