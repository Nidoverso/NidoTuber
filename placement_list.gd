class_name PlacementList
extends VBoxContainer
## Accessories placed on the current avatar or background, with buttons to add,
## remove, reset and save to the accessory, and a checkbox per row to hide one
## without removing it. Rows are reordered by dragging; the
## top one is drawn on top.
##
## Like the gallery, it emits "changed" and the panel refreshes it.

signal changed

const ICON_SIZE := 40
const MENU_ICON_SIZE := 32
const DRAG_PREVIEW_SIZE := 48
const DROP_TARGET_COLOR := Color(0.6, 0.85, 1.0)

var main: Main
## "avatar" or "background".
var target: String
## Selected row (-1 if none).
var selection: int = -1
## Returns an accessory thumbnail (the gallery's cache).
var thumbnail: Callable

var _rows: VBoxContainer
var _row_group := ButtonGroup.new()
var _add_button: MenuButton
var _buttons: Dictionary = {}
var _drop_target: Button
var _confirm_dialog: ConfirmationDialog
var _on_confirmed: Callable
var _menu_ids: PackedStringArray = []


func setup(p_main: Main, p_target: String, p_thumbnail: Callable) -> void:
	main = p_main
	target = p_target
	thumbnail = p_thumbnail
	add_theme_constant_override("separation", 6)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	add_child(_rows)

	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)
	# Shows the accessory library to pick one.
	_add_button = MenuButton.new()
	_add_button.text = "Add"
	_add_button.flat = false
	_add_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_button.about_to_popup.connect(_fill_add_menu)
	_add_button.get_popup().auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_add_button.get_popup().id_pressed.connect(_on_accessory_chosen)
	grid.add_child(_add_button)
	_button(grid, "remove", "Remove", _on_remove)
	# These two span the whole width: their texts are longer.
	_button(self, "reset", "Reset", _on_reset)
	_button(self, "save", "Save to accessory", _on_save)
	_buttons["reset"].tooltip_text = "Use the library accessory's settings again."
	_buttons["save"].tooltip_text = "Save these settings to the accessory: new placements will use them."

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "NidoTuber"
	_confirm_dialog.ok_button_text = "OK"
	_confirm_dialog.cancel_button_text = "Cancel"
	_confirm_dialog.confirmed.connect(func() -> void:
		_on_confirmed.call()
		changed.emit())
	add_child(_confirm_dialog)


## Accessory of the selected row, or null.
func selected_placement() -> Accessory:
	var list := main.placements(target)
	return list[selection] if selection >= 0 and selection < list.size() else null


## Rebuilds the rows. If the selection no longer exists, the first one is selected.
func refresh() -> void:
	for row in _rows.get_children():
		row.queue_free()
	var list := main.placements(target)
	if selection >= list.size() or (selection < 0 and not list.is_empty()):
		selection = 0 if not list.is_empty() else -1

	# An accessory placed several times gets a number: "Bird", "Bird (2)"...
	var count := {}
	for i in list.size():
		var id: String = list[i].accessory_id
		count[id] = count.get(id, 0) + 1
		var row_name := main.accessories.item_name(id)
		if count[id] > 1:
			row_name += " (%d)" % count[id]
		_create_row(i, row_name, thumbnail.call(id), list[i].visible)

	var nothing_selected := selection < 0
	for action in _buttons:
		_buttons[action].disabled = nothing_selected
	_add_button.disabled = main.accessories.list_ids().is_empty()
	_add_button.tooltip_text = tr("Create or import an accessory in the Accessories category first.") \
			if _add_button.disabled else ""


## A visibility checkbox and the row itself, which selects and is dragged.
func _create_row(index: int, row_name: String, icon: Texture2D, shown: bool) -> void:
	var line := HBoxContainer.new()
	var visibility := CheckBox.new()
	visibility.button_pressed = shown
	visibility.tooltip_text = "Show or hide this accessory without removing it"
	line.add_child(visibility)

	var row := Button.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	row.toggle_mode = true
	row.button_group = _row_group
	row.button_pressed = index == selection
	row.text = row_name
	row.icon = icon
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_theme_constant_override("icon_max_width", ICON_SIZE)
	row.clip_text = true
	row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.custom_minimum_size.y = ICON_SIZE + 8
	row.pressed.connect(func() -> void:
		selection = index
		changed.emit())
	row.set_drag_forwarding(
			_make_drag_data.bind(row, index),
			_can_drop.bind(row, index),
			_drop.bind(index))
	row.mouse_exited.connect(_remove_highlight.bind(row))
	line.add_child(row)
	# Hidden ones look dimmed (self_modulate, so the drop highlight still works).
	var dim := func(visible_now: bool) -> void: row.self_modulate.a = 1.0 if visible_now else 0.45
	dim.call(shown)
	visibility.toggled.connect(func(visible_now: bool) -> void:
		main.set_placement_visible(target, index, visible_now)
		dim.call(visible_now))
	_rows.add_child(line)


func _button(container: Container, action: String, text: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.pressed.connect(on_pressed)
	container.add_child(button)
	_buttons[action] = button


# --- Actions ------------------------------------------------------------------

## Filled when opened, to show the library as it is. With collections, one
## section per collection.
func _fill_add_menu() -> void:
	var menu := _add_button.get_popup()
	menu.clear()
	var library := main.accessories
	var all := library.list_ids()
	var collections := library.collections()
	var assignment := library.assignments()
	var groups: Array = []  # [section title, ids]
	for collection in collections:
		groups.append([collection.name,
				Array(all).filter(func(id: String) -> bool: return assignment.get(id) == collection.id)])
	groups.append([tr("No collection") if not collections.is_empty() else "",
			Array(all).filter(func(id: String) -> bool: return not assignment.has(id))])
	_menu_ids = PackedStringArray()
	for group in groups:
		if group[1].is_empty():
			continue
		if group[0] != "":
			menu.add_separator(group[0])
		for id: String in group[1]:
			_menu_ids.append(id)
			menu.add_icon_item(thumbnail.call(id), library.item_name(id), _menu_ids.size() - 1)
			menu.set_item_icon_max_width(menu.item_count - 1, MENU_ICON_SIZE)


func _on_accessory_chosen(index: int) -> void:
	if index < 0 or index >= _menu_ids.size():
		return
	main.add_placement(target, _menu_ids[index])
	# The new one goes on top and is selected, ready to adjust.
	selection = 0
	changed.emit()


func _on_remove() -> void:
	main.remove_placement(target, selection)
	selection = mini(selection, main.placements(target).size() - 1)
	changed.emit()


func _on_reset() -> void:
	_confirm(tr("Go back to the library accessory's settings?\nThe changes to this placement will be lost."),
			func() -> void: main.reset_placement(target, selection))


func _on_save() -> void:
	_confirm(tr("Save these settings to the library accessory?\nNew placements will use them; existing ones do not change."),
			func() -> void: main.save_placement_to_accessory(target, selection))


func _confirm(text: String, on_confirmed: Callable) -> void:
	_on_confirmed = on_confirmed
	_confirm_dialog.dialog_text = text
	_confirm_dialog.popup_centered()


# --- Reordering by dragging ---------------------------------------------------

func _make_drag_data(_position: Vector2, row: Button, index: int) -> Variant:
	var preview := TextureRect.new()
	preview.texture = row.icon
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size = Vector2(DRAG_PREVIEW_SIZE, DRAG_PREVIEW_SIZE)
	preview.position = -preview.size / 2.0
	preview.modulate.a = 0.8
	var container := Control.new()
	container.add_child(preview)
	row.set_drag_preview(container)
	return {"list": self, "index": index}


func _can_drop(_position: Vector2, data: Variant, row: Button, index: int) -> bool:
	var valid: bool = data is Dictionary and data.get("list") == self and data.get("index") != index
	if valid and _drop_target != row:
		_remove_highlight(_drop_target)
		_drop_target = row
		row.modulate = DROP_TARGET_COLOR
	return valid


func _drop(_position: Vector2, data: Variant, index: int) -> void:
	_remove_highlight(_drop_target)
	var selected := selected_placement()
	main.move_placement(target, data.index, index)
	# The selection follows the same accessory to its new position.
	selection = main.placements(target).find(selected)
	changed.emit()


func _remove_highlight(row: Button) -> void:
	if is_instance_valid(row):
		row.modulate = Color.WHITE
	if row == _drop_target:
		_drop_target = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_remove_highlight(_drop_target)
