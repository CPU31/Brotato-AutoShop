extends Node

const MOD_ID = "tang-AutoShop"
const VERSION = "1.2.0"
const Logger = preload("res://mods-unpacked/tang-AutoShop/core/logger.gd")
const Config = preload("res://mods-unpacked/tang-AutoShop/core/config.gd")
const Catalog = preload("res://mods-unpacked/tang-AutoShop/core/catalog.gd")
const Snapshot = preload("res://mods-unpacked/tang-AutoShop/core/shop_snapshot.gd")
const Runner = preload("res://mods-unpacked/tang-AutoShop/core/runner.gd")
const Rewards = preload("res://mods-unpacked/tang-AutoShop/core/rewards.gd")
const SettingsPanel = preload("res://mods-unpacked/tang-AutoShop/ui/whitelist_panel.gd")

var config = {}
var config_loaded = false
var catalog = []
var valid_ids = {}
var active_config
var runner
var panel
var shop_ref
var rewards


func _init():
	# 依据：本机 ModLoaderMod.install_script_extension。
	ModLoaderMod.install_script_extension("res://mods-unpacked/tang-AutoShop/extensions/shop_ext.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/tang-AutoShop/extensions/rewards_ext.gd")


func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS
	call_deferred("_load_config")


func _load_config():
	var store = get_node_or_null("/root/ModLoaderStore")
	if not is_instance_valid(store) or not store.get("mod_data").has(MOD_ID):
		Logger.error("加载器未登记本 Mod，停止初始化")
		return
	# 依据：本机 api/config.gd；default 是只读模板，使用命名配置保存用户选择。
	active_config = ModLoaderConfig.get_current_config(MOD_ID)
	if not is_instance_valid(active_config):
		Logger.error("未取得当前配置，停止初始化")
		return
	var checked = Config.sanitize(active_config.data)
	config = checked.config
	for warning in checked.warnings:
		Logger.warning(warning)
	refresh_catalog()
	if not config.preset_initialized:
		var preset = Catalog.resolve_presets(catalog)
		config.whitelist = preset.ids
		config.preset_initialized = true
		for name in preset.missing:
			Logger.warning("预设物品未加载或无法唯一识别：" + name)
	if active_config.name == ModLoaderConfig.DEFAULT_CONFIG_NAME:
		var configs = ModLoaderConfig.get_configs(MOD_ID)
		if configs.has("autoshop"):
			active_config = configs.autoshop
			config = Config.sanitize(active_config.data).config
		else:
			active_config = ModLoaderConfig.create_config(MOD_ID, "autoshop", config)
		if is_instance_valid(active_config):
			ModLoaderConfig.set_current_config(active_config)
	if not is_instance_valid(active_config):
		Logger.error("创建可编辑配置失败，未启用自动操作")
		return
	config_loaded = true
	runner = Runner.new()
	runner.host = self
	add_child(runner)
	rewards = Rewards.new()
	rewards.host = self
	add_child(rewards)
	panel = SettingsPanel.new()
	panel.host = self
	add_child(panel)
	# 续局可能使用其他 Mod 预加载的商店场景；观察原生节点创建，补齐扩展未触发的路径。
	get_tree().connect("node_added", self, "_observe_shop")
	Logger.info("loaded v" + VERSION)
	Logger.info("config " + JSON.print(config))
	Logger.info("CATALOG items=" + str(catalog.size()) + " whitelist=" + str(config.whitelist))


func refresh_catalog():
	catalog = Catalog.read(get_node_or_null("/root/ItemService"))
	valid_ids.clear()
	for item in catalog:
		valid_ids[item.id] = true


func save_config(data):
	var checked = Config.sanitize(data)
	if not checked.warnings.empty():
		return "设置无效：" + str(checked.warnings)
	if not is_instance_valid(active_config):
		return "当前配置不可用"
	var previous = active_config.data.duplicate(true)
	active_config.data = checked.config
	# 依据：本机 api/config.gd:update_config，保存失败返回 null。
	if not is_instance_valid(ModLoaderConfig.update_config(active_config)):
		active_config.data = previous
		return "保存失败，请查看日志；原设置已保留"
	config = checked.config
	log_line("CONFIG_SAVED " + JSON.print(config))
	return ""


func attach_shop(shop):
	if not config_loaded:
		return
	if current_shop() == shop:
		return
	if is_instance_valid(runner):
		runner.stop("new_shop")
	shop_ref = weakref(shop)
	var state = snapshot(shop, 0)
	log_line("SHOP_OPEN " + JSON.print(state))
	if not panel_open():
		runner.start(shop)


func _observe_shop(node):
	# 作为预缓存场景的只读接入后备，只有原生奖励容器才拥有这组三个方法。
	if node is Control and node.has_method("show_item") and node.has_method("_on_TakeButton_pressed") and node.has_method("_on_DiscardButton_pressed"):
		rewards.watch(node)
	if node is Control and node.has_method("_get_shop_items_container") and node.has_method("_on_RerollButton_pressed"):
		call_deferred("_attach_observed", weakref(node))


func _attach_observed(reference):
	yield(get_tree().create_timer(max(0.2, config.confirm_delay)), "timeout")
	var shop = reference.get_ref()
	if is_instance_valid(shop) and shop.is_inside_tree():
		attach_shop(shop)


func snapshot(shop, count):
	return Snapshot.read_shop(shop, get_node_or_null("/root/RunData"), valid_ids, count)


func current_shop():
	return shop_ref.get_ref() if shop_ref != null else null


func reward_single_player():
	var run_data = get_node_or_null("/root/RunData")
	return is_instance_valid(run_data) and run_data.has_method("get_player_count") and run_data.get_player_count() == 1


func panel_open():
	return is_instance_valid(panel) and panel.opened


func settings_available():
	var shop = current_shop()
	if is_instance_valid(shop) and shop.is_inside_tree() and shop.is_visible_in_tree():
		var leaving = shop.get("_player_pressed_go_button")
		if leaving is Array and not leaving.empty() and not leaving[0]:
			return true
	var scene = get_tree().current_scene
	if not is_instance_valid(scene):
		return false
	var script = scene.get_script()
	while script is Script:
		if script.resource_path == "res://ui/menus/pages/main_menu.gd":
			return true
		script = script.get_base_script()
	return false


func status_changed():
	if is_instance_valid(panel):
		panel.update_status()


func log_line(message, dry = false):
	Logger.info(("[DRY] " if dry else "") + message)


func _input(event):
	if not config_loaded:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.scancode == KEY_F8:
			if panel_open() or settings_available():
				panel.toggle()
				get_tree().set_input_as_handled()
			return
		if event.scancode == KEY_ESCAPE and panel_open():
			panel.close()
			get_tree().set_input_as_handled()
			return
		if event.scancode == KEY_F7 and not panel_open():
			runner.start(current_shop())
			get_tree().set_input_as_handled()
			return
		if event.scancode == KEY_F6:
			runner.stop("manual_stop")
			rewards.cancel_all()
			return
	if panel_open():
		return
	# 人工输入在原生 UI 处理前终止自动流程，不吞掉原操作。
	var manual = event is InputEventMouseButton and event.pressed
	manual = manual or (event is InputEventKey and event.pressed and not event.echo)
	manual = manual or (event is InputEventJoypadButton and event.pressed)
	manual = manual or (event is InputEventJoypadMotion and abs(event.axis_value) > 0.4)
	if manual and runner.running:
		runner.stop("manual_interrupt")
	if manual:
		rewards.cancel_all()
