extends CanvasLayer

const SearchEdit = preload("res://mods-unpacked/tang-AutoShop/ui/search_edit.gd")

const REASONS = {
	"insufficient_gold": "金币不足以继续刷新", "empty_whitelist": "白名单为空，零操作",
	"max_rerolls": "达到刷新次数上限", "reroll_cost": "刷新单价超过上限",
	"disabled": "自动商店已关闭", "manual_interrupt": "手动操作已中止自动流程",
	"manual_stop": "已手动停止", "dry_run_decision_only": "演练完成，未执行动作",
	"all_locked": "商品已全部锁定", "shop_closed": "商店已关闭",
	"editing": "正在编辑白名单", "paused": "游戏或面板已暂停",
	"coop_not_supported": "当前版本只接入单人商店",
	"no_loaded_targets": "白名单物品均未加载，未执行操作",
	"auto_depart": "金币不足以刷新，已自动出发"
}

var host
var opened = false
var paused_before = false
var root
var cover
var launcher
var grid
var search
var selected_only
var count_label
var status
var enabled
var dry_run
var selected = {}
var draft = {}
var limits = {}
var item_info
var auto_depart
var filter_version = 0


func _ready():
	layer = 120
	pause_mode = Node.PAUSE_MODE_PROCESS
	root = Control.new()
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font_path = "res://resources/fonts/actual/base/font_22.tres"
	if ResourceLoader.exists(font_path):
		root.theme = Theme.new()
		root.theme.default_font = load(font_path)
	add_child(root)
	launcher = Button.new()
	launcher.text = "自动商店 [F8]"
	launcher.rect_position = Vector2(300, 10)
	launcher.rect_min_size = Vector2(210, 42)
	launcher.connect("pressed", self, "toggle")
	root.add_child(launcher)
	cover = ColorRect.new()
	cover.color = Color(0.025, 0.035, 0.05, 0.98)
	cover.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.add_child(cover)
	var margin = MarginContainer.new()
	margin.anchor_left = 0.04
	margin.anchor_top = 0.04
	margin.anchor_right = 0.96
	margin.anchor_bottom = 0.96
	cover.add_child(margin)
	var column = VBoxContainer.new()
	column.add_constant_override("separation", 12)
	margin.add_child(column)
	var title = Label.new()
	title.text = "自动商店 · 图标白名单"
	column.add_child(title)
	var hint = Label.new()
	hint.text = "点图标加入 / 再点移除。保存后下次进商店生效；F7 手动执行，F6 停止。"
	column.add_child(hint)
	var options = HBoxContainer.new()
	enabled = CheckButton.new()
	enabled.text = "自动商店与奖励"
	dry_run = CheckButton.new()
	dry_run.text = "演练（只记录，不花钱）"
	options.add_child(enabled)
	options.add_child(dry_run)
	auto_depart = CheckButton.new()
	auto_depart.text = "金币不够刷新时自动出发"
	auto_depart.hint_tooltip = "默认关闭。仅因实际金币不足以刷新而停止时出发；预算上限、手动停止、空白名单和演练不会自动进入战斗。"
	options.add_child(auto_depart)
	column.add_child(options)
	var budgets = HBoxContainer.new()
	for pair in [["keep_gold", "留金币"], ["max_item_price", "物品上限"], ["max_rerolls", "刷新次数"], ["max_reroll_cost", "刷新单价"]]:
		var label = Label.new()
		label.text = pair[1]
		budgets.add_child(label)
		var spin = SpinBox.new()
		spin.min_value = 0 if pair[0] == "keep_gold" else -1
		spin.max_value = 999999
		spin.rect_min_size.x = 140
		budgets.add_child(spin)
		limits[pair[0]] = spin
	column.add_child(budgets)
	var note = Label.new()
	note.text = "上限 -1 表示不限；不买武器、消耗品或箱子。HP 商店至少保留 1 最大生命。"
	column.add_child(note)
	var filters = HBoxContainer.new()
	search = SearchEdit.new()
	search.placeholder_text = "搜索名称或物品 ID…"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.connect("text_changed", self, "_filter_changed")
	filters.add_child(search)
	selected_only = CheckButton.new()
	selected_only.text = "只看已选"
	selected_only.connect("toggled", self, "_filter_changed")
	filters.add_child(selected_only)
	var clear = Button.new()
	clear.text = "清空选择"
	clear.connect("pressed", self, "_clear")
	filters.add_child(clear)
	column.add_child(filters)
	count_label = Label.new()
	column.add_child(count_label)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	column.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 8
	grid.add_constant_override("hseparation", 10)
	grid.add_constant_override("vseparation", 10)
	scroll.add_child(grid)
	item_info = RichTextLabel.new()
	item_info.bbcode_enabled = true
	item_info.rect_min_size.y = 105
	item_info.scroll_active = true
	item_info.bbcode_text = "将鼠标悬停在物品图标上查看效果介绍。"
	column.add_child(item_info)
	status = Label.new()
	status.autowrap = true
	status.rect_min_size.y = 34
	column.add_child(status)
	var footer = HBoxContainer.new()
	for pair in [["保存并关闭", "_save"], ["取消 / 关闭 [F8]", "close"]]:
		var button = Button.new()
		button.text = pair[0]
		button.rect_min_size = Vector2(240, 46)
		button.connect("pressed", self, pair[1])
		footer.add_child(button)
	column.add_child(footer)
	cover.hide()


func toggle():
	if opened:
		close()
	else:
		open()


func open():
	if not host.settings_available():
		return
	if host.runner.running:
		host.runner.stop("editing")
	host.refresh_catalog()
	draft = host.config.duplicate(true)
	selected.clear()
	for id in draft.whitelist:
		selected[id] = true
	enabled.pressed = draft.enabled
	dry_run.pressed = draft.dry_run
	auto_depart.pressed = draft.get("auto_depart", false)
	for key in limits:
		limits[key].value = draft[key]
	search.text = ""
	selected_only.pressed = false
	paused_before = get_tree().paused
	get_tree().paused = true
	opened = true
	cover.show()
	launcher.hide()
	_build_grid()
	update_status()
	item_info.bbcode_text = "将鼠标悬停在物品图标上查看效果介绍。"


func close():
	if not opened:
		return
	opened = false
	cover.hide()
	launcher.show()
	get_tree().paused = paused_before
	# 关闭面板只交还控制权，不立即开始消费。
	host.log_line("EDITOR_CLOSED auto_resume=false")


func _save():
	draft.whitelist = selected.keys()
	draft.enabled = enabled.pressed
	draft.dry_run = dry_run.pressed
	draft.auto_depart = auto_depart.pressed
	for key in limits:
		draft[key] = int(limits[key].value)
	var error = host.save_config(draft)
	if error.empty():
		close()
	else:
		status.text = error


func _filter_changed(_value):
	filter_version += 1
	if opened:
		if _value is String:
			_filter_after_delay(filter_version)
		else:
			_build_grid()


func _filter_after_delay(version):
	# 连续输入时合并重建图标列表，避免每个字符都创建数百个控件。
	yield(get_tree().create_timer(0.12), "timeout")
	if opened and version == filter_version:
		_build_grid()


func _clear():
	selected.clear()
	_build_grid()


func _build_grid():
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	grid.columns = max(3, min(10, int(get_viewport().size.x * 0.90 / 155)))
	var shown = 0
	for item in host.catalog:
		if selected_only.pressed and not selected.has(item.id):
			continue
		if not search.text.empty() and (item.name + " " + item.id).to_lower().find(search.text.to_lower()) < 0:
			continue
		var button = Button.new()
		button.toggle_mode = true
		button.pressed = selected.has(item.id)
		button.focus_mode = Control.FOCUS_NONE
		button.rect_min_size = Vector2(145, 128)
		button.hint_tooltip = item.name + "\n" + item.id
		button.connect("mouse_entered", self, "_show_item_info", [item, button])
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.10, 0.36, 0.24)
		style.border_color = Color(0.3, 1.0, 0.6)
		style.set_border_width_all(3)
		button.add_stylebox_override("pressed", style)
		var box = VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.set_anchors_and_margins_preset(Control.PRESET_WIDE, Control.PRESET_MODE_MINSIZE, 6)
		var icon = TextureRect.new()
		icon.texture = item.icon
		icon.expand = true
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTER
		icon.rect_min_size = Vector2(56, 56)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)
		var label = Label.new()
		label.text = ("✓ " if button.pressed else "") + item.name
		label.align = Label.ALIGN_CENTER
		label.autowrap = true
		label.rect_min_size = Vector2(130, 52)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(label)
		button.add_child(box)
		button.connect("toggled", self, "_selected", [item.id, label, item.name])
		grid.add_child(button)
		shown += 1
	var missing = 0
	for id in selected:
		if not host.valid_ids.has(id):
			missing += 1
	count_label.text = "已选 %d 件 · 显示 %d / %d 件 · 未加载 ID %d（自动跳过）" % [selected.size(), shown, host.catalog.size(), missing]


func _selected(pressed, id, label, name):
	if pressed:
		selected[id] = true
	else:
		selected.erase(id)
	label.text = ("✓ " if pressed else "") + name
	count_label.text = "已选 %d 件（点击保存生效）" % selected.size()
	if selected_only.pressed and not pressed:
		call_deferred("_build_grid")


func update_status():
	if not is_instance_valid(status) or not is_instance_valid(host.runner):
		return
	var reason = host.runner.last_reason
	status.text = "状态：" + str(REASONS.get(reason, reason))


func _process(_delta):
	if is_instance_valid(launcher):
		launcher.visible = not opened and host.settings_available()
	if opened and not host.settings_available():
		close()


func _show_item_info(item, button):
	var description = "暂无效果说明"
	var data = item.get("data")
	# 依据：ItemParentData.get_effects_text；菜单使用游戏虚拟玩家索引，避免读取未开局状态。
	if is_instance_valid(data) and data.has_method("get_effects_text"):
		var player_index = 0 if is_instance_valid(host.current_shop()) else RunData.DUMMY_PLAYER_INDEX
		description = data.get_effects_text(player_index)
		if description.empty():
			description = "暂无效果说明"
	item_info.bbcode_text = "[b]" + item.name + "[/b]\n" + description
	# 原生浮动提示使用纯文本，详情区保留游戏的彩色效果文本。
	var tags = RegEx.new()
	tags.compile("\\[[^\\]]*\\]")
	button.hint_tooltip = item.name + "\n" + tags.sub(description, "", true)
