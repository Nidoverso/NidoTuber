class_name AvatarLibrary
extends Library
## Avatars in user://avatars/<id>/: avatar.json (name, settings and placed
## accessories) and one image per state (idle.png, talking.jpg...), stored as
## they came. Exported as .nidotuber files.
##
## Every avatar has its 4 images: a new avatar (or an imported one with missing
## images) gets copies of the program's placeholders, which can be replaced.
##
## An exported program does not keep the original PNGs of res://placeholder,
## only their imported version, and re-encoding a big PNG is slow. So PNG copies
## are made once, at startup, in user://placeholders/, and creating an avatar is
## just copying files. Avatars still using a placeholder share its texture.

const PLACEHOLDER_FOLDER := "res://placeholder"
const COPIES_FOLDER := "user://placeholders"
const FINGERPRINTS_FILE := "fingerprints.json"
## English; translated when created.
const EXAMPLE_NAME := "Example avatar"

## state -> md5 of each copy, to recognise images that are still the placeholder.
var _copy_fingerprints: Dictionary = {}
var _placeholder_textures: Dictionary = {}  # state -> Texture2D
var _placeholder_thumbnails: Dictionary = {}  # size -> Texture2D


func _init() -> void:
	super("user://avatars", "avatar.json", "nidotuber", "New avatar", "avatar", "avatars")
	_prepare_placeholder_copies()


## Creates an avatar with copies of the placeholders and returns its id.
func create(desired_name: String, initial_settings: Dictionary = {}) -> String:
	var id := _create(desired_name, {"settings": initial_settings})
	_fill_with_placeholders(id)
	return id


## As stored; Avatar.apply_settings() validates them.
func settings(id: String) -> Dictionary:
	var data: Variant = _read_data(id).get("settings", {})
	return data if data is Dictionary else {}


func save_settings(id: String, new_settings: Dictionary) -> void:
	if not exists(id):
		return
	var data := _read_data(id)
	data["settings"] = new_settings
	_write_data(id, data)


func has_image(id: String, state: String) -> bool:
	return _saved_image_path(id, state) != ""


## null if the state has no image.
func texture(id: String, state: String) -> Texture2D:
	if _is_placeholder(id, state):
		if not _placeholder_textures.has(state):
			var image := Image.load_from_file(COPIES_FOLDER.path_join(state + ".png"))
			_placeholder_textures[state] = ImageTexture.create_from_image(image) \
					if image and not image.is_empty() else null
		if _placeholder_textures[state]:
			return _placeholder_textures[state]
	return _load_texture(id, state)


## Copies an image from disk as it is. Returns false if it is not valid.
func save_image(id: String, state: String, source: String) -> bool:
	return _save_image_from_file(id, state, source)


func thumbnail(id: String, size: int) -> Texture2D:
	if not _is_placeholder(id, "idle"):
		return super(id, size)
	if not _placeholder_thumbnails.has(size):
		_placeholder_thumbnails[size] = super(id, size)
	return _placeholder_thumbnails[size]


# --- Placeholders -------------------------------------------------------------

## Makes the missing or outdated copies. A copy is up to date if the fingerprint
## of the file Godot imported from the original has not changed, so no image
## needs to be loaded at startup.
func _prepare_placeholder_copies() -> void:
	DirAccess.make_dir_recursive_absolute(COPIES_FOLDER)
	var fingerprints_path := COPIES_FOLDER.path_join(FINGERPRINTS_FILE)
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(fingerprints_path)) \
			if FileAccess.file_exists(fingerprints_path) else {}
	if not saved is Dictionary:
		saved = {}
	var source_fingerprints := {}
	var changed := false

	for state in Avatar.STATES:
		var source := "%s/%s.png" % [PLACEHOLDER_FOLDER, state]
		var copy := COPIES_FOLDER.path_join(state + ".png")
		if not ResourceLoader.exists(source):
			if FileAccess.file_exists(copy):
				DirAccess.remove_absolute(copy)
				changed = true
			continue
		var fingerprint := _source_fingerprint(source)
		source_fingerprints[state] = fingerprint
		var outdated: bool = fingerprint != "" and saved.get(state) != fingerprint
		if outdated or not FileAccess.file_exists(copy):
			_make_copy(source, copy)
			changed = true
		if FileAccess.file_exists(copy):
			_copy_fingerprints[state] = FileAccess.get_md5(copy)

	if changed or saved != source_fingerprints:
		var file := FileAccess.open(fingerprints_path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(source_fingerprints, "\t"))


## md5 of the file Godot generates when importing the image (named in its .import).
static func _source_fingerprint(source: String) -> String:
	var import_file := ConfigFile.new()
	if import_file.load(source + ".import") != OK:
		return ""
	var imported := str(import_file.get_value("remap", "path", ""))
	return FileAccess.get_md5(imported) if imported != "" and FileAccess.file_exists(imported) else ""


static func _make_copy(source: String, copy: String) -> void:
	var source_texture: Texture2D = load(source)
	var image := source_texture.get_image() if source_texture else null
	if image == null or image.is_empty():
		return
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.save_png(copy)


## True if the state's image is identical, file for file, to the placeholder.
func _is_placeholder(id: String, state: String) -> bool:
	if not _copy_fingerprints.has(state):
		return false
	var path := _saved_image_path(id, state)
	return path.get_extension() == "png" and FileAccess.get_md5(path) == _copy_fingerprints[state]


## Copies the placeholder into every state without an image.
func _fill_with_placeholders(id: String) -> void:
	for state in Avatar.STATES:
		var copy := COPIES_FOLDER.path_join(state + ".png")
		if not has_image(id, state) and FileAccess.file_exists(copy):
			DirAccess.copy_absolute(copy, _item_folder(id).path_join(state + ".png"))


# --- Library ------------------------------------------------------------------

func _content_files(id: String) -> PackedStringArray:
	var files := PackedStringArray()
	for state in Avatar.STATES:
		var path := _saved_image_path(id, state)
		if path != "":
			files.append(path.get_file())
	return files


func _imported_data(data: Dictionary) -> Dictionary:
	var imported: Variant = data.get("settings", {})
	return {"settings": imported if imported is Dictionary else {}}


func _import_content(zip: ZIPReader, files: PackedStringArray, id: String) -> String:
	for state in Avatar.STATES:
		_import_image(zip, files, id, state)
	# Missing or invalid images are replaced with the placeholders.
	_fill_with_placeholders(id)
	return ""


func _thumbnail_texture(id: String) -> Texture2D:
	return texture(id, "idle")
