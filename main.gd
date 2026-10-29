class_name Main
extends Node2D
## Main scene: background, window, current avatar, accessories, options panel and
## configuration.
##
## config.cfg only keeps general settings (microphone, window, language...) and
## which avatar, background and accessory are in use. Everything else lives in
## the libraries.

const CONFIG_PATH := "user://config.cfg"
## Saved window sizes below this (in pixels) are ignored.
const MIN_WINDOW_SIZE := 200
const MICROPHONE_PROPERTIES := ["threshold_db", "hold_time"]
## 16:9 sizes offered by the panel. Any other size can be set by resizing the window.
const RESOLUTIONS := [
	Vector2i(640, 360), Vector2i(854, 480), Vector2i(1280, 720),
	Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]
## 0 = unlimited.
const FPS_LIMITS := [30, 60, 0]
## The program's own language is English; other languages are loaded from
## translations/<code>.po.
const LANGUAGES := ["en", "es"]
const BACKGROUND_FITS := {
	"cover": TextureRect.STRETCH_KEEP_ASPECT_COVERED,
	"contain": TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
	"stretch": TextureRect.STRETCH_SCALE,
}

var avatars := AvatarLibrary.new()
var backgrounds := BackgroundLibrary.new()
var accessories := AccessoryLibrary.new()
var current_avatar: String = ""
var current_background: String = ""
## As shown; may have unsaved changes while the colour picker is open.
var background_color: Color = BackgroundLibrary.DEFAULT_COLOR
## Selected in the library ("" if there is none).
var current_accessory: String = ""
## Shows the selected library accessory while its settings are being edited.
var preview: Accessory
var fps_limit: int = 60
var vsync: bool = true
var language: String = "en"
## Options panel width as a proportion of the window (the panel clamps it).
var panel_width: float = 0.3
## Which panel sections were folded (key -> bool), read from the configuration.
var folded: Dictionary = {}

## "avatar" / "background" -> Accessory nodes in order (the first is drawn on top).
var _placements: Dictionary = {"avatar": [], "background": []}
## Node holding each target's accessories (child order is drawing order).
var _containers: Dictionary = {}
## Which avatar or background the loaded accessories belong to, so showing the
## same one again does not reload them (and lose unsaved changes).
var _placements_of: Dictionary = {"avatar": "", "background": ""}
## Shared by every placement of the same accessory.
var _accessory_textures: Dictionary = {}
var _background_image: TextureRect

@onready var avatar: Avatar = $Avatar
@onready var microphone: Microphone = $Microphone
@onready var options_panel: OptionsPanel = $UI/OptionsPanel


func _ready() -> void:
	_load_translations()
	TranslationServer.set_locale(language)
	avatars.accessory_library = accessories
	backgrounds.accessory_library = accessories
	_create_background_layer()
	for target in _placements:
		var container := Node2D.new()
		container.name = "Accessories_" + target
		add_child(container)
		_containers[target] = container
	preview = Accessory.new()
	preview.name = "Preview"
	preview.avatar = avatar
	preview.visible = false
	add_child(preview)
	# Configuration first, so the panel is built with the saved values.
	load_config()
	apply_fps_limit(fps_limit)
	apply_vsync(vsync)
	microphone.talking_changed.connect(avatar.set_mouth_open)
	options_panel.setup(self, avatar, microphone)
	# Starts hidden: right click or Esc opens it.
	options_panel.visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_config()


## Under the avatar, filling the window.
func _create_background_layer() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	_background_image = TextureRect.new()
	_background_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# The right click must still reach the window.
	_background_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background_image.visible = false
	layer.add_child(_background_image)


func _load_translations() -> void:
	for code in LANGUAGES:
		var path := "res://translations/%s.po" % code
		if ResourceLoader.exists(path):
			TranslationServer.add_translation(load(path))


# --- Window and general settings ----------------------------------------------

## The avatar is not scaled; it is placed again from its relative position.
func apply_resolution(size: Vector2i) -> void:
	var window := get_window()
	# A maximised or fullscreen window would ignore the new size.
	if window.mode != Window.MODE_WINDOWED:
		window.mode = Window.MODE_WINDOWED
	window.size = size
	_keep_on_screen()


## With VSync on, the monitor's refresh rate is not exceeded either.
func apply_fps_limit(fps: int) -> void:
	fps_limit = fps if fps in FPS_LIMITS else 60
	Engine.max_fps = fps_limit


func apply_vsync(enabled: bool) -> void:
	vsync = enabled
	DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)


## Controls translate themselves; the panel rewrites its composed texts.
func apply_language(code: String) -> void:
	if not code in LANGUAGES:
		return
	language = code
	TranslationServer.set_locale(code)
	options_panel.refresh()


## If the window grew past the screen, it is moved back inside.
func _keep_on_screen() -> void:
	var window := get_window()
	var area := DisplayServer.screen_get_usable_rect(window.current_screen)
	var window_position := window.position
	window_position.x = clampi(window_position.x, area.position.x,
			maxi(area.position.x, area.end.x - window.size.x))
	window_position.y = clampi(window_position.y, area.position.y,
			maxi(area.position.y, area.end.y - window.size.y))
	window.position = window_position


## Used by the right click, Esc and the panel's own button.
func show_panel(visible_panel: bool) -> void:
	options_panel.visible = visible_panel
	# Saved on close, in case the program does not exit cleanly.
	if not visible_panel:
		save_config()


func _unhandled_input(event: InputEvent) -> void:
	var right_click: bool = event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT
	var escape: bool = event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE
	if right_click or escape:
		show_panel(not options_panel.visible)
		get_viewport().set_input_as_handled()


# --- Avatars ------------------------------------------------------------------
# There is always at least one avatar, and one is always in use.

func select_avatar(id: String) -> void:
	if id == current_avatar or not avatars.exists(id):
		return
	save_current_avatar()
	_show_avatar(id)


func create_avatar(avatar_name: String) -> String:
	save_current_avatar()
	var id := avatars.create(avatar_name, avatar.default_settings())
	_show_avatar(id)
	return id


func duplicate_avatar(id: String) -> String:
	if id == current_avatar:
		save_current_avatar()
	var copy := avatars.duplicate_item(id)
	select_avatar(copy)
	return copy


func rename_avatar(id: String, new_name: String) -> void:
	avatars.rename(id, new_name)


## If it is in use, the next one is shown. The last one cannot be deleted.
func delete_avatar(id: String) -> bool:
	var ids := avatars.list_ids()
	if ids.size() <= 1 or not id in ids:
		return false
	var next := ""
	if id == current_avatar:
		var index := ids.find(id)
		next = ids[index + 1] if index + 1 < ids.size() else ids[index - 1]
	if not avatars.delete(id):
		return false
	if next != "":
		_show_avatar(next)
	return true


## Returns false if the image is not valid.
func set_avatar_image(state: String, path: String) -> bool:
	if not avatars.save_image(current_avatar, state, path):
		return false
	_load_avatar_textures()
	return true


func export_avatar(id: String, path: String) -> Error:
	if id == current_avatar:
		save_current_avatar()
	return avatars.export_item(id, path)


## Selects it. "" on failure (reason in avatars.last_error).
func import_avatar(path: String) -> String:
	var id := avatars.import_item(path)
	if id != "":
		select_avatar(id)
	return id


func open_avatars_folder() -> void:
	OS.shell_open(avatars.absolute_folder())


func save_current_avatar() -> void:
	avatars.save_settings(current_avatar, avatar.get_settings())
	avatars.save_placements(current_avatar, _placement_data("avatar"))


func _show_avatar(id: String) -> void:
	current_avatar = id
	avatar.apply_settings(avatars.settings(id))
	_load_avatar_textures()
	if _placements_of.avatar != id:
		_load_placements("avatar", id, avatars.placements(id))


func _load_avatar_textures() -> void:
	for state in Avatar.STATES:
		avatar.set_texture(state, avatars.texture(current_avatar, state))


# --- Backgrounds --------------------------------------------------------------
# Like avatars: always at least one, and one always in use.

func select_background(id: String) -> void:
	if id == current_background or not backgrounds.exists(id):
		return
	save_current_background()
	_show_background(id)


## Chroma green, without an image.
func create_background(background_name: String) -> String:
	save_current_background()
	var id := backgrounds.create(background_name)
	_show_background(id)
	return id


func duplicate_background(id: String) -> String:
	if id == current_background:
		save_current_background()
	var copy := backgrounds.duplicate_item(id)
	select_background(copy)
	return copy


func rename_background(id: String, new_name: String) -> void:
	backgrounds.rename(id, new_name)


func delete_background(id: String) -> bool:
	var ids := backgrounds.list_ids()
	if ids.size() <= 1 or not id in ids:
		return false
	var next := ""
	if id == current_background:
		var index := ids.find(id)
		next = ids[index + 1] if index + 1 < ids.size() else ids[index - 1]
	if not backgrounds.delete(id):
		return false
	if next != "":
		_show_background(next)
	return true


## Only on screen; save_current_background() stores it, so the picker does not
## write to disk on every move.
func change_background_color(color: Color) -> void:
	background_color = color
	RenderingServer.set_default_clear_color(color)


## Returns false if the image is not valid.
func change_background_image(path: String) -> bool:
	if not backgrounds.save_image(current_background, path):
		return false
	_show_background(current_background)
	return true


func remove_background_image() -> void:
	backgrounds.remove_image(current_background)
	_show_background(current_background)


func change_background_fit(mode: String) -> void:
	backgrounds.change_fit(current_background, mode)
	_show_background(current_background)


func save_current_background() -> void:
	backgrounds.change_color(current_background, background_color)
	backgrounds.save_placements(current_background, _placement_data("background"))


func export_background(id: String, path: String) -> Error:
	if id == current_background:
		save_current_background()
	return backgrounds.export_item(id, path)


func import_background(path: String) -> String:
	var id := backgrounds.import_item(path)
	if id != "":
		select_background(id)
	return id


func open_backgrounds_folder() -> void:
	OS.shell_open(backgrounds.absolute_folder())


func _show_background(id: String) -> void:
	current_background = id
	change_background_color(backgrounds.color(id))
	var texture := backgrounds.texture(id)
	_background_image.texture = texture
	_background_image.stretch_mode = BACKGROUND_FITS[backgrounds.fit(id)]
	_background_image.visible = texture != null
	if _placements_of.background != id:
		_load_placements("background", id, backgrounds.placements(id))


# --- Accessory library --------------------------------------------------------
# Unlike avatars and backgrounds, it can be empty: then nothing is selected.

func select_accessory(id: String) -> void:
	if id == current_accessory or not accessories.exists(id):
		return
	save_current_accessory()
	_show_accessory(id)


## Named after the file, with default settings. "" if the image is not valid.
func create_accessory(image_path: String) -> String:
	save_current_accessory()
	var id := accessories.create(image_path.get_file().get_basename(), image_path,
			preview.default_settings())
	if id != "":
		_show_accessory(id)
	return id


func duplicate_accessory(id: String) -> String:
	if id == current_accessory:
		save_current_accessory()
	var copy := accessories.duplicate_item(id)
	select_accessory(copy)
	return copy


func rename_accessory(id: String, new_name: String) -> void:
	accessories.rename(id, new_name)


## Also removed from every avatar and background. If selected, the next one is.
func delete_accessory(id: String) -> bool:
	var ids := accessories.list_ids()
	if not id in ids:
		return false
	var next := current_accessory
	if id == current_accessory:
		var index := ids.find(id)
		next = ""
		if ids.size() > 1:
			next = ids[index + 1] if index + 1 < ids.size() else ids[index - 1]
	# Current placements are saved so it is removed from all of them alike.
	save_current_avatar()
	save_current_background()
	if not accessories.delete(id):
		return false
	_remove_everywhere(id)
	if id == current_accessory:
		current_accessory = ""
		_show_accessory(next)
	return true


## Also changes it wherever it is placed. Returns false if it is not valid.
func change_accessory_image(path: String) -> bool:
	if not accessories.save_image(current_accessory, path):
		return false
	_accessory_textures.erase(current_accessory)
	preview.set_texture(accessory_texture(current_accessory))
	for target in _placements:
		for placement: Accessory in _placements[target]:
			if placement.accessory_id == current_accessory:
				placement.set_texture(accessory_texture(current_accessory))
	return true


func export_accessory(id: String, path: String) -> Error:
	if id == current_accessory:
		save_current_accessory()
	return accessories.export_item(id, path)


func import_accessory(path: String) -> String:
	var id := accessories.import_item(path)
	if id != "":
		select_accessory(id)
	return id


func open_accessories_folder() -> void:
	OS.shell_open(accessories.absolute_folder())


func save_current_accessory() -> void:
	if current_accessory != "":
		accessories.save_settings(current_accessory, preview.get_settings())


## Its settings are saved when it is hidden.
func show_preview(visible_preview: bool) -> void:
	visible_preview = visible_preview and current_accessory != ""
	if preview.visible and not visible_preview:
		save_current_accessory()
	preview.visible = visible_preview


func accessory_texture(id: String) -> Texture2D:
	if not _accessory_textures.has(id):
		_accessory_textures[id] = accessories.texture(id)
	return _accessory_textures[id]


## How many times an accessory is placed across all avatars and backgrounds.
func accessory_uses(id: String) -> int:
	save_current_avatar()
	save_current_background()
	var uses := 0
	for library: Library in [avatars, backgrounds]:
		for item in library.list_ids():
			for entry in library.placements(item):
				if entry.accessory == id:
					uses += 1
	return uses


func _show_accessory(id: String) -> void:
	current_accessory = id
	if id == "":
		preview.visible = false
		preview.set_texture(null)
		return
	preview.apply_settings(accessories.settings(id))
	preview.set_texture(accessory_texture(id))


func _remove_everywhere(id: String) -> void:
	_accessory_textures.erase(id)
	for target in _placements:
		var list: Array = _placements[target]
		for i in range(list.size() - 1, -1, -1):
			if list[i].accessory_id == id:
				list[i].queue_free()
				list.remove_at(i)
	for library: Library in [avatars, backgrounds]:
		for item in library.list_ids():
			var entries := library.placements(item)
			var remaining: Array[Dictionary] = []
			remaining.assign(entries.filter(func(e: Dictionary) -> bool: return e.accessory != id))
			if remaining.size() != entries.size():
				library.save_placements(item, remaining)


# --- Collections --------------------------------------------------------------

## What is on screen is saved first, in case it belongs to the collection.
func export_collection(collection: String, path: String, library: Library) -> Error:
	save_current_avatar()
	save_current_background()
	save_current_accessory()
	return library.export_collection(collection, path)


## "" on failure (reason in library.last_error).
func import_collection(path: String, library: Library) -> String:
	return library.import_collection(path)


# --- Placed accessories -------------------------------------------------------
# "target" is "avatar" or "background": those of the current avatar or background.

## In order; the first is drawn on top.
func placements(target: String) -> Array:
	return _placements[target]


## Placed on top of the others, with the library accessory's settings.
func add_placement(target: String, id: String) -> void:
	if not accessories.exists(id):
		return
	# If it is being edited in the preview, its current settings are used.
	save_current_accessory()
	_placements[target].push_front(_create_placement(target, id, accessories.settings(id)))
	_sort(target)


func remove_placement(target: String, index: int) -> void:
	var list: Array = _placements[target]
	if index < 0 or index >= list.size():
		return
	list[index].queue_free()
	list.remove_at(index)


## Moves a placement to the position of another one.
func move_placement(target: String, from: int, to: int) -> void:
	var list: Array = _placements[target]
	if from == to or from < 0 or from >= list.size() or to < 0 or to >= list.size():
		return
	var placement: Accessory = list[from]
	list.remove_at(from)
	list.insert(to, placement)
	_sort(target)


## Hides a placement without removing it or losing its settings.
func set_placement_visible(target: String, index: int, shown: bool) -> void:
	var list: Array = _placements[target]
	if index >= 0 and index < list.size():
		list[index].visible = shown


## Copies the library accessory's settings again.
func reset_placement(target: String, index: int) -> void:
	var placement: Accessory = _placements[target][index]
	save_current_accessory()
	placement.apply_settings(accessories.settings(placement.accessory_id))


## New placements will use these settings; existing ones do not change.
func save_placement_to_accessory(target: String, index: int) -> void:
	var placement: Accessory = _placements[target][index]
	var settings := placement.get_settings()
	accessories.save_settings(placement.accessory_id, settings)
	if placement.accessory_id == current_accessory:
		preview.apply_settings(settings)


func _create_placement(target: String, id: String, settings: Dictionary) -> Accessory:
	var placement := Accessory.new()
	placement.avatar = avatar
	placement.tier = 2 if target == "background" else 1
	placement.accessory_id = id
	placement.apply_settings(settings)
	placement.set_texture(accessory_texture(id))
	_containers[target].add_child(placement)
	return placement


## Replaces the placed accessories with those saved in an avatar or background.
## Accessories missing from the library are skipped.
func _load_placements(target: String, owner_id: String, list: Array[Dictionary]) -> void:
	for placement: Accessory in _placements[target]:
		placement.queue_free()
	_placements[target] = []
	for entry in list:
		if accessories.exists(entry.accessory):
			var placement := _create_placement(target, entry.accessory, entry.settings)
			placement.visible = entry.visible
			_placements[target].append(placement)
	_sort(target)
	_placements_of[target] = owner_id


func _placement_data(target: String) -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	for placement: Accessory in _placements[target]:
		data.append({"accessory": placement.accessory_id, "settings": placement.get_settings(),
				"visible": placement.visible})
	return data


## Within a layer, nodes are drawn in tree order: the first of the list must be
## the last child.
func _sort(target: String) -> void:
	var list: Array = _placements[target]
	for i in list.size():
		_containers[target].move_child(list[i], list.size() - 1 - i)


# --- Configuration ------------------------------------------------------------

func save_config() -> void:
	save_current_avatar()
	save_current_background()
	save_current_accessory()

	var config := ConfigFile.new()
	config.set_value("library", "avatar", current_avatar)
	config.set_value("library", "background", current_background)
	config.set_value("library", "accessory", current_accessory)

	config.set_value("microphone", "device", AudioServer.input_device)
	for property in MICROPHONE_PROPERTIES:
		config.set_value("microphone", property, microphone.get(property))

	var window := get_window()
	config.set_value("window", "size", window.size)
	config.set_value("window", "position", window.position)
	config.set_value("window", "fps_limit", fps_limit)
	config.set_value("window", "vsync", vsync)
	config.set_value("window", "panel_width", panel_width)
	config.set_value("general", "language", language)

	folded = options_panel.get_folded()
	for key in folded:
		config.set_value("panel", key, folded[key])

	var error := config.save(CONFIG_PATH)
	if error != OK:
		push_error("Could not save the configuration (error %d)." % error)


func load_config() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		# The saved microphone is only used if it is still connected.
		var device: String = config.get_value("microphone", "device", "")
		if device in AudioServer.get_input_device_list() and device != AudioServer.input_device:
			microphone.change_device(device)
		for property in MICROPHONE_PROPERTIES:
			microphone.set(property, config.get_value("microphone", property, microphone.get(property)))

		_restore_window(config)
		var saved_fps: Variant = config.get_value("window", "fps_limit", fps_limit)
		fps_limit = saved_fps if saved_fps is int else fps_limit
		var saved_vsync: Variant = config.get_value("window", "vsync", vsync)
		vsync = saved_vsync if saved_vsync is bool else vsync
		var saved_width: Variant = config.get_value("window", "panel_width", panel_width)
		panel_width = saved_width if saved_width is float else panel_width
		var saved_language: Variant = config.get_value("general", "language", language)
		language = saved_language if saved_language in LANGUAGES else language
		# Before creating the examples, so their names use this language.
		TranslationServer.set_locale(language)

		if config.has_section("panel"):
			for key in config.get_section_keys("panel"):
				folded[key] = config.get_value("panel", key)

	# The saved item if it still exists; otherwise the first one. An empty library
	# (first run) gets an example, created like a new one.
	var background_id: String = str(config.get_value("library", "background", ""))
	var background_ids := backgrounds.list_ids()
	if background_ids.is_empty():
		background_id = backgrounds.create(tr(BackgroundLibrary.EXAMPLE_NAME))
	elif not background_id in background_ids:
		background_id = background_ids[0]
	_show_background(background_id)

	var avatar_id: String = str(config.get_value("library", "avatar", ""))
	var avatar_ids := avatars.list_ids()
	if avatar_ids.is_empty():
		avatar_id = avatars.create(tr(AvatarLibrary.EXAMPLE_NAME), avatar.default_settings())
	elif not avatar_id in avatar_ids:
		avatar_id = avatar_ids[0]
	_show_avatar(avatar_id)

	var accessory_id: String = str(config.get_value("library", "accessory", ""))
	var accessory_ids := accessories.list_ids()
	if not accessory_id in accessory_ids:
		accessory_id = accessory_ids[0] if not accessory_ids.is_empty() else ""
	_show_accessory(accessory_id)


func _restore_window(config: ConfigFile) -> void:
	var window := get_window()
	var size: Vector2i = config.get_value("window", "size", window.size)
	# Very small sizes are ignored (it may have been saved minimised).
	if size.x >= MIN_WINDOW_SIZE and size.y >= MIN_WINDOW_SIZE:
		window.size = size
	# Only restored if it falls inside a current screen (a monitor may be gone).
	var saved_position: Vector2i = config.get_value("window", "position", window.position)
	for screen in DisplayServer.get_screen_count():
		if DisplayServer.screen_get_usable_rect(screen).has_point(saved_position):
			window.position = saved_position
			return
