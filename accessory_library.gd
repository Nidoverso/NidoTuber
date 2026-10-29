class_name AccessoryLibrary
extends Library
## Accessories in user://accessories/<id>/: accessory.json (name and the settings
## used when it is placed) and its image (image.png/.jpg/.webp), stored as it
## came. A hat, a bird or a plant pot only differ in their settings.
## Exported as .nidoacc files.


func _init() -> void:
	super("user://accessories", "accessory.json", "nidoacc", "New accessory", "accessory",
			"accessories")


## Creates an accessory from an image on disk and returns its id, or "" if the
## image is not valid.
func create(desired_name: String, image_path: String, initial_settings: Dictionary) -> String:
	var id := _create(desired_name, {"settings": initial_settings})
	if not _save_image_from_file(id, "image", image_path):
		_erase(id)
		return ""
	return id


## As stored; Accessory.apply_settings() validates them.
func settings(id: String) -> Dictionary:
	var data: Variant = _read_data(id).get("settings", {})
	return data if data is Dictionary else {}


func save_settings(id: String, new_settings: Dictionary) -> void:
	if not exists(id):
		return
	var data := _read_data(id)
	if data.get("settings") == new_settings:
		return
	data["settings"] = new_settings
	_write_data(id, data)


func texture(id: String) -> Texture2D:
	return _load_texture(id, "image")


## Returns false if it is not a valid image.
func save_image(id: String, source: String) -> bool:
	return _save_image_from_file(id, "image", source)


# --- Library ------------------------------------------------------------------

func _content_files(id: String) -> PackedStringArray:
	var path := _saved_image_path(id, "image")
	return PackedStringArray([path.get_file()]) if path != "" else PackedStringArray()


func _imported_data(data: Dictionary) -> Dictionary:
	var imported: Variant = data.get("settings", {})
	return {"settings": imported if imported is Dictionary else {}}


func _import_content(zip: ZIPReader, files: PackedStringArray, id: String) -> String:
	# An accessory is its image: without it there is nothing to import.
	if not _import_image(zip, files, id, "image"):
		return tr("The accessory has no image, or it is not valid.")
	return ""


## The same accessory means an identical image, byte for byte.
func _find_same(zip: ZIPReader, files: PackedStringArray) -> String:
	var content := PackedByteArray()
	for file_extension in IMAGE_FORMATS + ["jpeg"]:
		var inner: String = _zip_prefix + "image." + file_extension
		if inner in files:
			content = zip.read_file(inner)
			break
	if content.is_empty():
		return ""
	var fingerprint := _md5(content)
	for id in list_ids():
		var path := _saved_image_path(id, "image")
		if path != "" and FileAccess.get_md5(path) == fingerprint:
			return id
	return ""


static func _md5(content: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_MD5)
	context.update(content)
	return context.finish().hex_encode()


func _thumbnail_texture(id: String) -> Texture2D:
	return texture(id)
