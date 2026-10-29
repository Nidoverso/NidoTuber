class_name Gallery
extends VBoxContainer
## Thumbnail gallery with collections, search and buttons to manage a Library.
## Used for avatars, backgrounds and accessories.
##
## It changes nothing by itself: it calls the owner's "actions" and then emits
## "changed" so the panel refreshes.

## After any change (selection, new, delete, import...).
signal changed

const THUMBNAIL_SIZE := 96
const DRAG_PREVIEW_SIZE := 64
## Tint of the cell or tab a drag is over.
const DROP_TARGET_COLOR := Color(0.6, 0.85, 1.0)
## Tabs that are not a collection.
const ALL := "*all*"
const NO_COLLECTION := ""

var library: Library
## Owner functions:
##   current() -> String               selected id
##   select(id)
##   create()                          the owner decides (ask a name, pick an image...)
##   duplicate(id) -> String
##   rename(id, name)
##   delete(id) -> bool
##   import(path) -> String            "" on failure (reason in library.last_error)
##   export(id, path) -> Error
##   open_folder()
##   export_collection(collection, path) -> Error
##   import_collection(path) -> String "" on failure
##   delete_details(id) -> String      (optional) added to the delete confirmation
var actions: Dictionary
## Items cannot be deleted below this number.
var minimum: int = 0
## Tab being viewed: ALL, a collection id or NO_COLLECTION.
var tab: String = ALL

var _tabs: HFlowContainer
var _tab_group := ButtonGroup.new()
var _search: LineEdit
var _empty_notice: Label
var _cells: HFlowContainer
var _cell_group := ButtonGroup.new()
var _thumbnails: Dictionary = {}  # id -> Texture2D
var _buttons: Dictionary = {}  # action -> Button
var _move_button: MenuButton
var _move_ids: PackedStringArray = []
## Cell or tab highlighted while dragging over it.
var _drop_target: Button
var _tab_menu: PopupMenu
var _menu_collection: String = ""

var _import_dialog: FileDialog
var _export_dialog: FileDialog
var _export_collection_dialog: FileDialog
var _name_dialog: ConfirmationDialog
var _name_field: LineEdit
var _delete_dialog: ConfirmationDialog
var _delete_collection_dialog: ConfirmationDialog
var _notice_dialog: AcceptDialog
var _on_name_accepted: Callable


## create_text is the text of the first button; folder_text the folder button's.
func setup(p_library: Library, p_actions: Dictionary, create_text: String,
		folder_text: String) -> void:
	library = p_library
	actions = p_actions
	add_theme_constant_override("separation", 6)

	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", 4)
	_tabs.add_theme_constant_override("v_separation", 4)
	add_child(_tabs)

	_search = LineEdit.new()
	_search.placeholder_text = "Search…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void: refresh())
	add_child(_search)

	_cells = HFlowContainer.new()
	_cells.add_theme_constant_override("h_separation", 6)
	_cells.add_theme_constant_override("v_separation", 6)
	add_child(_cells)

	_empty_notice = Label.new()
	_empty_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_notice.modulate.a = 0.6
	add_child(_empty_notice)

	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)
	_button(grid, "create", create_text, func() -> void: actions["create"].call())
	_button(grid, "duplicate", "Duplicate", _on_duplicate)
	_button(grid, "rename", "Rename", _on_rename)
	# Moves the selected item to another collection (dragging to a tab also works).
	_move_button = MenuButton.new()
	_move_button.text = "Move to…"
	_move_button.flat = false
	_move_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_move_button.about_to_popup.connect(_fill_move_menu)
	_move_button.get_popup().auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_move_button.get_popup().id_pressed.connect(_on_move_chosen)
	grid.add_child(_move_button)
	_button(grid, "import", "Import", func() -> void: _open_file_dialog(_import_dialog))
	_button(grid, "export", "Export", _on_export)
	# These two span the whole width.
	_button(self, "delete", "Delete", _on_delete)
	_button(self, "folder", folder_text, func() -> void: actions["open_folder"].call())

	_create_dialogs()


## Rebuilds tabs and cells and updates which buttons can be used.
func refresh() -> void:
	if tab != ALL and tab != NO_COLLECTION and not library.has_collection(tab):
		tab = ALL
	# What is created or imported from here goes into the collection being viewed.
	library.collection_for_new = tab if tab != ALL else ""
	_create_tabs()

	for child in _cells.get_children():
		child.queue_free()
	var current: String = actions["current"].call()
	var ids := library.list_ids()
	var assignment := library.assignments()
	var query := _normalize(_search.text.strip_edges())
	var shown := 0
	for id in ids:
		if tab != ALL and str(assignment.get(id, NO_COLLECTION)) != tab:
			continue
		var name_text := library.item_name(id)
		if query != "" and not _normalize(name_text).contains(query):
			continue
		_create_cell(id, name_text, thumbnail(id), id == current)
		shown += 1

	_empty_notice.visible = shown == 0
	if query != "":
		_empty_notice.text = tr("No results.")
	elif tab != ALL:
		_empty_notice.text = tr("This collection is empty.\nDrag items onto its tab.")
	else:
		_empty_notice.text = tr("There are none yet.")

	# With nothing selected (an empty library) you can only create or import.
	var nothing_selected := not current in ids
	for action in ["duplicate", "rename", "export"]:
		_buttons[action].disabled = nothing_selected
	_move_button.disabled = nothing_selected or library.collections().is_empty()
	_buttons["delete"].disabled = nothing_selected or ids.size() <= minimum


## Cached; generated the first time.
func thumbnail(id: String) -> Texture2D:
	if not _thumbnails.has(id):
		_thumbnails[id] = library.thumbnail(id, THUMBNAIL_SIZE)
	return _thumbnails[id]


## Regenerates an item's thumbnail next time (for example, after changing its image).
func invalidate_thumbnail(id: String) -> void:
	_thumbnails.erase(id)


## title is English and translated here; initial is the field's text.
func ask_name(title: String, initial: String, on_accepted: Callable,
		max_length: int = Library.MAX_NAME_LENGTH) -> void:
	_on_name_accepted = on_accepted
	_name_field.max_length = max_length
	_name_dialog.title = tr(title)
	_name_field.text = initial
	_name_dialog.popup_centered()
	_name_field.grab_focus()
	_name_field.select_all()


## text must already be translated.
func notify(text: String) -> void:
	_notice_dialog.dialog_text = text
	_notice_dialog.popup_centered()


# --- Cells and buttons --------------------------------------------------------

func _create_cell(id: String, name_text: String, icon: Texture2D, selected: bool) -> void:
	var cell := Button.new()
	# User names are never translated.
	cell.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	cell.toggle_mode = true
	cell.button_group = _cell_group
	cell.button_pressed = selected
	cell.custom_minimum_size = Vector2(THUMBNAIL_SIZE, THUMBNAIL_SIZE + 28)
	cell.icon = icon
	cell.expand_icon = true
	cell.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	cell.text = name_text
	cell.clip_text = true
	cell.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cell.tooltip_text = name_text
	cell.pressed.connect(_on_cell_pressed.bind(id))
	# Dropping a cell on another moves it there; a click without dragging selects.
	cell.set_drag_forwarding(
			_make_drag_data.bind(cell, id),
			_can_drop_on_cell.bind(cell, id),
			_drop_on_cell.bind(id))
	cell.mouse_exited.connect(_remove_highlight.bind(cell))
	_cells.add_child(cell)


func _button(container: Container, action: String, text: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(on_pressed)
	container.add_child(button)
	_buttons[action] = button


func _on_cell_pressed(id: String) -> void:
	actions["select"].call(id)
	changed.emit()


func _on_duplicate() -> void:
	actions["duplicate"].call(actions["current"].call())
	changed.emit()


func _on_rename() -> void:
	var id: String = actions["current"].call()
	ask_name(_typed("Rename %s"), library.item_name(id),
			func(new_name: String) -> void: actions["rename"].call(id, new_name))


func _on_delete() -> void:
	var id: String = actions["current"].call()
	_delete_dialog.title = tr("Delete %s") % tr(library.type_name)
	_delete_dialog.dialog_text = tr("Delete “%s”?\nIt will be moved to the system trash.") \
			% library.item_name(id)
	if actions.has("delete_details"):
		var details: String = actions["delete_details"].call(id)
		if details != "":
			_delete_dialog.dialog_text += "\n\n" + details
	_delete_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	var id: String = actions["current"].call()
	if actions["delete"].call(id):
		_thumbnails.erase(id)
	else:
		notify(tr("Could not delete the %s.") % tr(library.type_name))
	changed.emit()


func _on_file_imported(path: String) -> void:
	if path.get_extension().to_lower() == Library.COLLECTION_EXTENSION:
		var collection: String = actions["import_collection"].call(path)
		if collection == "":
			notify(tr("Could not import the collection.") + "\n" + library.last_error)
		else:
			tab = collection
			if library.last_error != "":
				notify(library.last_error)
	elif actions["import"].call(path) == "":
		notify(tr("Could not import the %s.") % tr(library.type_name) + "\n" + library.last_error)
	changed.emit()


func _on_export() -> void:
	_export_dialog.current_file = "%s.%s" % [
			library.item_name(actions["current"].call()).validate_filename(), library.extension]
	_open_file_dialog(_export_dialog)


func _on_file_exported(path: String) -> void:
	if path.get_extension().to_lower() != library.extension:
		path += "." + library.extension
	if actions["export"].call(actions["current"].call(), path) != OK:
		notify(tr("Could not export the %s to:") % tr(library.type_name) + "\n" + path)


func _on_collection_exported(path: String) -> void:
	if path.get_extension().to_lower() != Library.COLLECTION_EXTENSION:
		path += "." + Library.COLLECTION_EXTENSION
	if actions["export_collection"].call(_menu_collection, path) != OK:
		notify(tr("Could not export the collection to:") + "\n" + path)


func _on_name_confirmed() -> void:
	var new_name := _name_field.text.strip_edges()
	if new_name != "" and _on_name_accepted.is_valid():
		_on_name_accepted.call(new_name)
		changed.emit()


# --- Collections --------------------------------------------------------------

func _create_tabs() -> void:
	for child in _tabs.get_children():
		child.queue_free()
	_create_tab(ALL, "All")
	for collection in library.collections():
		_create_tab(collection.id, collection.name)
	_create_tab(NO_COLLECTION, "No collection")
	var add := Button.new()
	add.text = "＋"
	add.tooltip_text = "New collection"
	add.pressed.connect(_on_new_collection)
	_tabs.add_child(add)


func _create_tab(collection: String, text: String) -> void:
	var button := Button.new()
	button.toggle_mode = true
	button.button_group = _tab_group
	button.button_pressed = collection == tab
	button.text = text
	button.pressed.connect(func() -> void:
		tab = collection
		refresh())
	if collection != ALL:
		# Dropping a cell on a tab moves it to that collection.
		button.set_drag_forwarding(Callable(),
				_can_drop_on_tab.bind(button, collection),
				_drop_on_tab.bind(collection))
		button.mouse_exited.connect(_remove_highlight.bind(button))
	if collection != ALL and collection != NO_COLLECTION:
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.tooltip_text = tr("Right-click to rename, reorder, export or delete the collection.")
		button.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_RIGHT:
				# Keep the right click from reaching the window (it would hide the panel).
				button.accept_event()
				_open_tab_menu(collection))
	_tabs.add_child(button)


func _on_new_collection() -> void:
	ask_name("New collection", tr("New collection"), func(collection_name: String) -> void:
		tab = library.create_collection(collection_name), Library.MAX_COLLECTION_NAME_LENGTH)


func _open_tab_menu(collection: String) -> void:
	_menu_collection = collection
	var list := library.collections()
	var index := list.map(func(c: Dictionary) -> String: return c.id).find(collection)
	_tab_menu.set_item_disabled(_tab_menu.get_item_index(1), index <= 0)
	_tab_menu.set_item_disabled(_tab_menu.get_item_index(2), index >= list.size() - 1)
	# Embedded popups use window coordinates; native ones, screen coordinates.
	var menu_position := Vector2i(get_global_mouse_position())
	if not get_viewport().gui_embed_subwindows:
		menu_position += get_window().position
	_tab_menu.popup(Rect2i(menu_position, Vector2i.ZERO))


func _on_tab_menu(option: int) -> void:
	var collection := _menu_collection
	match option:
		0:
			ask_name("Rename collection", library.collection_name(collection),
					func(new_name: String) -> void: library.rename_collection(collection, new_name),
					Library.MAX_COLLECTION_NAME_LENGTH)
		1, 2:
			library.move_collection(collection, -1 if option == 1 else 1)
			refresh()
		3:
			_export_collection_dialog.current_file = "%s.%s" % [
					library.collection_name(collection).validate_filename(),
					Library.COLLECTION_EXTENSION]
			_open_file_dialog(_export_collection_dialog)
		4:
			_delete_collection_dialog.dialog_text = tr("Delete the collection “%s”?\nIts content is not deleted: it moves to “No collection”.") \
					% library.collection_name(collection)
			_delete_collection_dialog.popup_centered()


func _on_delete_collection_confirmed() -> void:
	library.delete_collection(_menu_collection)
	if tab == _menu_collection:
		tab = ALL
	changed.emit()


func _fill_move_menu() -> void:
	var menu := _move_button.get_popup()
	menu.clear()
	var current := library.collection_of(actions["current"].call())
	_move_ids = PackedStringArray([NO_COLLECTION])
	menu.add_item(tr("No collection"), 0)
	for collection in library.collections():
		_move_ids.append(collection.id)
		menu.add_item(collection.name, _move_ids.size() - 1)
	menu.set_item_disabled(_move_ids.find(current), true)


func _on_move_chosen(index: int) -> void:
	library.assign_collection(actions["current"].call(), _move_ids[index])
	changed.emit()


func _can_drop_on_tab(_position: Vector2, data: Variant, button: Button, collection: String) -> bool:
	var valid: bool = data is Dictionary and data.get("gallery") == self \
			and library.collection_of(data.get("id")) != collection
	if valid and _drop_target != button:
		_remove_highlight(_drop_target)
		_drop_target = button
		button.modulate = DROP_TARGET_COLOR
	return valid


func _drop_on_tab(_position: Vector2, data: Variant, collection: String) -> void:
	_remove_highlight(_drop_target)
	library.assign_collection(data.id, collection)
	refresh()


## Search ignores case and accents: "Crème" matches "creme".
static func _normalize(text: String) -> String:
	var result := text.to_lower()
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"],
			["à", "a"], ["è", "e"], ["ì", "i"], ["ò", "o"], ["ù", "u"], ["ñ", "n"], ["ç", "c"]]:
		result = result.replace(pair[0], pair[1])
	return result


# --- Reordering by dragging ---------------------------------------------------
# Godot's arguments (position and data) come first, then those added with bind().

func _make_drag_data(_position: Vector2, cell: Button, id: String) -> Variant:
	var preview := TextureRect.new()
	preview.texture = cell.icon
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size = Vector2(DRAG_PREVIEW_SIZE, DRAG_PREVIEW_SIZE)
	preview.position = -preview.size / 2.0
	preview.modulate.a = 0.8
	# A container lets the preview be centred on the cursor.
	var container := Control.new()
	container.add_child(preview)
	cell.set_drag_preview(container)
	return {"gallery": self, "id": id}


func _can_drop_on_cell(_position: Vector2, data: Variant, cell: Button, id: String) -> bool:
	# Only cells of this same gallery.
	var valid: bool = data is Dictionary and data.get("gallery") == self and data.get("id") != id
	if valid and _drop_target != cell:
		_remove_highlight(_drop_target)
		_drop_target = cell
		cell.modulate = DROP_TARGET_COLOR
	return valid


func _drop_on_cell(_position: Vector2, data: Variant, id: String) -> void:
	_remove_highlight(_drop_target)
	library.move(data.id, id)
	refresh()


func _remove_highlight(button: Button) -> void:
	if is_instance_valid(button):
		button.modulate = Color.WHITE
	if button == _drop_target:
		_drop_target = null


func _notification(what: int) -> void:
	# The drag may end outside any cell.
	if what == NOTIFICATION_DRAG_END:
		_remove_highlight(_drop_target)


# --- Dialogs ------------------------------------------------------------------

## "Rename %s" -> "Rename avatar", translated.
func _typed(text: String) -> String:
	return tr(text) % tr(library.type_name)


## Titles and filters are set when opening, so they follow the current language.
func _open_file_dialog(dialog: FileDialog) -> void:
	var item_filter := "*.%s ; %s" % [library.extension, tr("NidoTuber %s") % tr(library.type_name)]
	var collection_filter := "*.%s ; %s" % [Library.COLLECTION_EXTENSION, tr("NidoTuber collection")]
	match dialog:
		_import_dialog:
			dialog.title = _typed("Import %s")
			# Accepts a single item or a whole collection.
			dialog.filters = PackedStringArray([
				"*.%s, *.%s ; %s" % [library.extension, Library.COLLECTION_EXTENSION,
						tr("NidoTuber files")],
				item_filter, collection_filter,
			])
		_export_dialog:
			dialog.title = _typed("Export %s")
			dialog.filters = PackedStringArray([item_filter])
		_export_collection_dialog:
			dialog.title = tr("Export collection")
			dialog.filters = PackedStringArray([collection_filter])
	dialog.popup_centered_ratio(0.7)


func _create_dialogs() -> void:
	_import_dialog = _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, _on_file_imported)
	_export_dialog = _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, _on_file_exported)
	_export_collection_dialog = _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, _on_collection_exported)

	_name_dialog = ConfirmationDialog.new()
	_name_dialog.ok_button_text = "OK"
	_name_dialog.cancel_button_text = "Cancel"
	_name_dialog.min_size = Vector2i(320, 0)
	_name_field = LineEdit.new()
	_name_dialog.add_child(_name_field)
	_name_dialog.register_text_enter(_name_field)
	_name_dialog.confirmed.connect(_on_name_confirmed)
	add_child(_name_dialog)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.ok_button_text = "Delete"
	_delete_dialog.cancel_button_text = "Cancel"
	_delete_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(_delete_dialog)

	_delete_collection_dialog = ConfirmationDialog.new()
	_delete_collection_dialog.title = "Delete collection"
	_delete_collection_dialog.ok_button_text = "Delete"
	_delete_collection_dialog.cancel_button_text = "Cancel"
	_delete_collection_dialog.confirmed.connect(_on_delete_collection_confirmed)
	add_child(_delete_collection_dialog)

	_tab_menu = PopupMenu.new()
	_tab_menu.add_item("Rename", 0)
	_tab_menu.add_item("Move left", 1)
	_tab_menu.add_item("Move right", 2)
	_tab_menu.add_item("Export collection…", 3)
	_tab_menu.add_separator()
	_tab_menu.add_item("Delete collection", 4)
	_tab_menu.id_pressed.connect(_on_tab_menu)
	add_child(_tab_menu)

	_notice_dialog = AcceptDialog.new()
	_notice_dialog.title = "NidoTuber"
	_notice_dialog.ok_button_text = "OK"
	add_child(_notice_dialog)


func _file_dialog(mode: FileDialog.FileMode, on_selected: Callable) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.file_selected.connect(on_selected)
	add_child(dialog)
	return dialog
