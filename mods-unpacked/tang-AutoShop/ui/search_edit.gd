extends LineEdit


func _input(event):
	if not has_focus() or not editable or not event is InputEventKey:
		return
	if not event.pressed or event.unicode < 32 or event.control or event.alt or event.meta:
		return
	# 游戏把 WASD 绑定到 UI 导航。先接收可打印字符，避免原生导航分支夺走文本输入。
	# 仅作用于获得焦点的搜索框，不修改全局 InputMap，也不拦截方向键和组合快捷键。
	var begin = get_selection_from_column() if has_selection() else get_cursor_position()
	var end = get_selection_to_column() if has_selection() else begin
	var value = char(event.unicode)
	text = text.substr(0, begin) + value + text.substr(end)
	set_cursor_position(begin + value.length())
	emit_signal("text_changed", text)
	get_tree().set_input_as_handled()
