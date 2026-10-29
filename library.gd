class_name Library
extends RefCounted
## Common base of the avatar, background and accessory libraries.
##
## Each item is a folder <folder>/<id>/ with a JSON data file (name and settings)
## and its images. The id is internal, so renaming moves no files. Exporting
## creates a ZIP with those same files and the type's own extension.
##
## <folder>/order.json keeps the gallery order. <folder>/collections.json keeps
## the collections and which item is in each one; they are personal organisation,
## so they are never exported along with the items.
##
## Subclasses define their content files and how they are validated on import
## (see "For subclasses").

const MAX_NAME_LENGTH := 60
## Collection names are read in tabs and menus, so they are shorter.
const MAX_COLLECTION_NAME_LENGTH := 30
const COLLECTION_EXTENSION := "nidocol"
const COLLECTION_DATA_FILE := "collection.json"
const ORDER_FILE := "order.json"
const COLLECTIONS_FILE := "collections.json"
## Folders inside exported files.
const ITEMS_ZIP_FOLDER := "items"
const ACCESSORIES_ZIP_FOLDER := "accessories"
## Images are stored as they come, with the extension of their real format
## ("jpeg" is saved as "jpg").
const IMAGE_FORMATS := ["png", "jpg", "webp"]
const IMAGE_FILTER := "*.png, *.jpg, *.jpeg, *.webp"

var folder: String
var data_file: String
var extension: String
## English; translated when shown.
var default_name: String
var type_name: String
var type_plural: String
## Version of the data format. Raise it if its structure changes.
var format_version: int = 1

## Reason of the last import failure, already translated, to show to the user.
var last_error: String = ""
## Library of the accessories that can be placed on the items (avatars and
## backgrounds). When set, exports include the placed accessories and imports
## add them to it.
var accessory_library: Library
## Collection that new items go into (the one being viewed in the gallery; ""
## for none). Items that come inside another file ignore it.
var collection_for_new: String = ""
## ZIP folder being imported from ("" for the root). Set by import_embedded().
var _zip_prefix: String = ""


func _init(p_folder: String, p_data_file: String, p_extension: String,
		p_default_name: String, p_type_name: String, p_type_plural: String) -> void:
	folder = p_folder
	data_file = p_data_file
	extension = p_extension
	default_name = p_default_name
	type_name = p_type_name
	type_plural = p_type_plural
	DirAccess.make_dir_recursive_absolute(folder)


# --- Queries ------------------------------------------------------------------

## Ids in gallery order. Folders missing from the order file (copied by hand,
## for example) go last by creation date; ids that no longer exist are dropped.
func list_ids() -> PackedStringArray:
	var existing: Array[String] = []
	for subfolder in DirAccess.get_directories_at(folder):
		if FileAccess.file_exists(_data_path(subfolder)):
			existing.append(subfolder)
	var ordered: Array[String] = []
	for id in _read_order():
		if id in existing and not id in ordered:
			ordered.append(id)
	# Ids start with the creation time, so sorting them sorts by age.
	existing.sort()
	for id in existing:
		if not id in ordered:
			ordered.append(id)
	return PackedStringArray(ordered)


## Moves an item to the position of another one.
func move(id: String, target: String) -> void:
	var order := Array(list_ids())
	if id == target or not id in order or not target in order:
		return
	var target_index := order.find(target)
	order.erase(id)
	order.insert(target_index, id)
	_write_order(PackedStringArray(order))


func exists(id: String) -> bool:
	return id != "" and FileAccess.file_exists(_data_path(id))


func item_name(id: String) -> String:
	return str(_read_data(id).get("name", tr(default_name)))


## Reduced image for the galleries.
func thumbnail(id: String, size: int) -> Texture2D:
	var texture := _thumbnail_texture(id)
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	var factor := float(size) / maxf(image.get_width(), image.get_height())
	if factor < 1.0:
		image.resize(maxi(1, roundi(image.get_width() * factor)),
				maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


func absolute_folder() -> String:
	return ProjectSettings.globalize_path(folder)


# --- Placed accessories (avatars and backgrounds) -----------------------------
# Stored in the item data as "accessories":
# [{"accessory": accessory library id, "settings": {...}, "visible": bool}].
# The first is drawn on top. "visible" belongs to the placement, not to its
# settings, so saving to the accessory or resetting does not change it.

## Entries with a wrong format are dropped.
func placements(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var data: Variant = _read_data(id).get("accessories", [])
	if data is Array:
		for entry in data:
			if entry is Dictionary and entry.get("accessory") is String:
				result.append(_placement_entry(entry.accessory, entry))
	return result


func save_placements(id: String, list: Array[Dictionary]) -> void:
	if not exists(id):
		return
	var data := _read_data(id)
	if data.get("accessories", []) == list:
		return
	data["accessories"] = list
	_write_data(id, data)


# --- Changes ------------------------------------------------------------------

## Copies an item with its files and settings, right after the original and in
## its collection. Returns the copy's id.
func duplicate_item(id: String) -> String:
	var copy := _create(tr("%s (copy)") % item_name(id), _own_data(_read_data(id)), id)
	assign_collection(copy, collection_of(id))
	for file in _content_files(id):
		DirAccess.copy_absolute(_item_folder(id).path_join(file), _item_folder(copy).path_join(file))
	return copy


func rename(id: String, new_name: String) -> void:
	var data := _read_data(id)
	var clean := new_name.strip_edges()
	if clean == "" or clean == data.get("name"):
		return
	data["name"] = unique_name(clean, id)
	_write_data(id, data)


## Moves the item to the system trash (or deletes it if there is none).
func delete(id: String) -> bool:
	if not exists(id):
		return false
	if OS.move_to_trash(ProjectSettings.globalize_path(_item_folder(id))) == OK:
		_remove_from_order(id)
		assign_collection(id, "")
		return true
	return _erase(id)


## The desired name, or with a number if it is taken: "My avatar (2)".
## except_id keeps an item's own name available to itself.
func unique_name(desired: String, except_id: String = "") -> String:
	var base := desired.strip_edges().left(MAX_NAME_LENGTH)
	if base == "":
		base = tr(default_name)
	var used := {}
	for id in list_ids():
		if id != except_id:
			used[item_name(id).to_lower()] = true
	return _numbered(base, used)


# --- Collections --------------------------------------------------------------

## [{"id": ..., "name": ...}] in their order.
func collections() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(_read_collections().collections)
	return result


func has_collection(collection: String) -> bool:
	return collections().any(func(c: Dictionary) -> bool: return c.id == collection)


func collection_name(collection: String) -> String:
	for c in collections():
		if c.id == collection:
			return c.name
	return ""


## Adds a collection at the end and returns its id. Names cannot repeat.
func create_collection(desired_name: String) -> String:
	var data := _read_collections()
	var id := ""
	while id == "" or data.collections.any(func(c: Dictionary) -> bool: return c.id == id):
		id = "c%d_%04x" % [int(Time.get_unix_time_from_system()), randi() % 0x10000]
	data.collections.append({"id": id, "name": _unique_collection_name(desired_name, "")})
	_write_collections(data)
	return id


func rename_collection(collection: String, new_name: String) -> void:
	var data := _read_collections()
	for c in data.collections:
		if c.id == collection and new_name.strip_edges() != "":
			c.name = _unique_collection_name(new_name, collection)
	_write_collections(data)


## Its items are not deleted: they end up in no collection.
func delete_collection(collection: String) -> void:
	var data := _read_collections()
	data.collections = data.collections.filter(func(c: Dictionary) -> bool: return c.id != collection)
	for item in data.assignment.keys():
		if data.assignment[item] == collection:
			data.assignment.erase(item)
	if collection_for_new == collection:
		collection_for_new = ""
	_write_collections(data)


## Moves a collection one place to the left (-1) or to the right (1).
func move_collection(collection: String, step: int) -> void:
	var data := _read_collections()
	var list: Array = data.collections
	var index := -1
	for i in list.size():
		if list[i].id == collection:
			index = i
	var new_index := index + step
	if index == -1 or new_index < 0 or new_index >= list.size():
		return
	var moved: Variant = list[index]
	list.remove_at(index)
	list.insert(new_index, moved)
	_write_collections(data)


## "" if it is in none.
func collection_of(id: String) -> String:
	return str(_read_collections().assignment.get(id, ""))


## id -> collection, for the items that are in one.
func assignments() -> Dictionary:
	return _read_collections().assignment


## "" takes the item out of every collection.
func assign_collection(id: String, collection: String) -> void:
	var data := _read_collections()
	if collection == "" or not data.collections.any(func(c: Dictionary) -> bool: return c.id == collection):
		if not data.assignment.has(id):
			return
		data.assignment.erase(id)
	else:
		data.assignment[id] = collection
	_write_collections(data)


func _unique_collection_name(desired: String, except_id: String) -> String:
	var base := desired.strip_edges().left(MAX_COLLECTION_NAME_LENGTH)
	if base == "":
		base = tr("Collection")
	var used := {}
	for c in collections():
		if c.id != except_id:
			used[str(c.name).to_lower()] = true
	return _numbered(base, used)


## Drops anything with an unexpected format and assignments to missing collections.
func _read_collections() -> Dictionary:
	var result := {"collections": [], "assignment": {}}
	var path := folder.path_join(COLLECTIONS_FILE)
	if not FileAccess.file_exists(path):
		return result
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return result
	var ids := {}
	var list: Variant = data.get("collections", [])
	if list is Array:
		for c in list:
			if c is Dictionary and c.get("id") is String and c.get("name") is String \
					and not ids.has(c.id):
				ids[c.id] = true
				result.collections.append({"id": c.id, "name": c.name})
	var assignment: Variant = data.get("assignment", {})
	if assignment is Dictionary:
		for item in assignment:
			if item is String and ids.has(assignment[item]):
				result.assignment[item] = assignment[item]
	return result


func _write_collections(data: Dictionary) -> void:
	var file := FileAccess.open(folder.path_join(COLLECTIONS_FILE), FileAccess.WRITE)
	if file == null:
		push_error("Could not save the %s collections." % type_name)
		return
	file.store_string(JSON.stringify(data, "\t"))


# --- Export and import --------------------------------------------------------

## Placed accessories go in the same file, in accessories/<id>/, once each.
func export_item(id: String, path: String) -> Error:
	var files := exported_files(id)
	_add_accessories(files, id)
	return _write_zip(path, files)


## Exports every item of a collection, in gallery order: collection.json (type,
## name and order), items/<id>/ with each item's files and accessories/<id>/
## with their placed accessories (once each).
func export_collection(collection: String, path: String) -> Error:
	var assignment := assignments()
	var items := Array(list_ids()).filter(func(id: String) -> bool: return assignment.get(id) == collection)
	var files := {COLLECTION_DATA_FILE: JSON.stringify({
		"format": format_version, "type": type_name, "name": collection_name(collection),
		"items": items,
	}, "\t").to_utf8_buffer()}
	for id: String in items:
		var item_files := exported_files(id)
		for file_name in item_files:
			files[ITEMS_ZIP_FOLDER.path_join(id).path_join(file_name)] = item_files[file_name]
		_add_accessories(files, id)
	return _write_zip(path, files)


## An item's files as they go in an exported file: name -> content.
func exported_files(id: String) -> Dictionary:
	var data := _read_data(id)
	data["format"] = format_version
	var files := {data_file: JSON.stringify(data, "\t").to_utf8_buffer()}
	for file in _content_files(id):
		files[file] = FileAccess.get_file_as_bytes(_item_folder(id).path_join(file))
	return files


func _add_accessories(files: Dictionary, id: String) -> void:
	if accessory_library == null:
		return
	for entry in placements(id):
		var accessory: String = entry.accessory
		var zip_folder := ACCESSORIES_ZIP_FOLDER.path_join(accessory)
		if accessory_library.exists(accessory) and not files.has(
				zip_folder.path_join(accessory_library.data_file)):
			var accessory_files := accessory_library.exported_files(accessory)
			for file_name in accessory_files:
				files[zip_folder.path_join(file_name)] = accessory_files[file_name]


func _write_zip(path: String, files: Dictionary) -> Error:
	var zip := ZIPPacker.new()
	var error := zip.open(path)
	if error != OK:
		return error
	for file_name in files:
		zip.start_file(file_name)
		zip.write_file(files[file_name])
		zip.close_file()
	return zip.close()


## Imports an exported file as a new item and returns its id, or "" with the
## reason in last_error.
func import_item(path: String) -> String:
	last_error = ""
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return _fail(tr("The file is not a valid NidoTuber %s.") % tr(type_name))
	# Only the expected files are read, by their exact name.
	var files := zip.get_files()
	if not data_file in files:
		zip.close()
		return _fail(tr("The file is not a valid NidoTuber %s.") % tr(type_name))
	var data: Variant = JSON.parse_string(zip.read_file(data_file).get_string_from_utf8())
	if not data is Dictionary:
		zip.close()
		return _fail(tr("The %s data is damaged.") % tr(type_name))
	if _is_newer(data):
		zip.close()
		return _fail(tr("This %s was made with a newer version of NidoTuber.") % tr(type_name))

	var id := _create(str(data.get("name", tr(default_name))), _imported_data(data))
	var error := _import_content(zip, files, id)
	if error != "":
		zip.close()
		_erase(id)
		return _fail(error)
	if accessory_library:
		_import_placements(zip, files, id, data.get("accessories", []))
	zip.close()
	return id


## Adds the accessories that come in the file to the accessory library and saves
## the placements linked to them. An accessory with the same image is reused.
## Placements whose accessory is missing or invalid are dropped.
func _import_placements(zip: ZIPReader, files: PackedStringArray, id: String,
		entries: Variant) -> void:
	if not entries is Array:
		return
	var matches := {}  # id in the file -> id in the library ("" if it failed)
	var list: Array[Dictionary] = []
	for entry in entries:
		if not (entry is Dictionary and entry.get("accessory") is String):
			continue
		var original: String = entry.accessory
		if not matches.has(original):
			matches[original] = accessory_library.import_embedded(
					zip, files, ACCESSORIES_ZIP_FOLDER.path_join(original))
		if matches[original] != "":
			list.append(_placement_entry(matches[original], entry))
	save_placements(id, list)


## A validated placement entry for the given accessory id.
static func _placement_entry(accessory: String, entry: Dictionary) -> Dictionary:
	var settings: Variant = entry.get("settings", {})
	var shown: Variant = entry.get("visible", true)
	return {"accessory": accessory, "settings": settings if settings is Dictionary else {},
			"visible": shown if shown is bool else true}


## Imports an item that comes inside another file, from the given ZIP folder.
## With "reuse", an existing item with the same content is returned instead of
## creating a new one. Returns "" if it is not valid.
func import_embedded(zip: ZIPReader, files: PackedStringArray, zip_folder: String,
		reuse: bool = true) -> String:
	var data_path := zip_folder.path_join(data_file)
	if not data_path in files:
		return ""
	var data: Variant = JSON.parse_string(zip.read_file(data_path).get_string_from_utf8())
	if not data is Dictionary:
		return ""
	_zip_prefix = zip_folder + "/"
	var id := _find_same(zip, files) if reuse else ""
	if id == "":
		id = _create(str(data.get("name", tr(default_name))), _imported_data(data))
		if _import_content(zip, files, id) != "":
			_erase(id)
			id = ""
	_zip_prefix = ""
	if id != "" and not reuse and accessory_library:
		_import_placements(zip, files, id, data.get("accessories", []))
	return id


## Creates the collection (renamed if the name is taken) with all its items as
## new ones. Returns the collection id, or "" with the reason in last_error.
## If only some items fail, last_error explains it but the id is returned.
func import_collection(path: String) -> String:
	last_error = ""
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return _fail(tr("The file is not a valid NidoTuber collection."))
	var files := zip.get_files()
	if not COLLECTION_DATA_FILE in files:
		zip.close()
		return _fail(tr("The file is not a valid NidoTuber collection."))
	var data: Variant = JSON.parse_string(zip.read_file(COLLECTION_DATA_FILE).get_string_from_utf8())
	if not data is Dictionary:
		zip.close()
		return _fail(tr("The collection data is damaged."))
	if _is_newer(data):
		zip.close()
		return _fail(tr("This collection was made with a newer version of NidoTuber."))
	if data.get("type") != type_name:
		zip.close()
		return _fail(tr("This collection does not contain %s.") % tr(type_plural))

	var collection := create_collection(str(data.get("name", tr("Imported collection"))))
	var items: Variant = data.get("items", [])
	var failed := 0
	if items is Array:
		for item in items:
			if not item is String:
				continue
			var id := import_embedded(zip, files, ITEMS_ZIP_FOLDER.path_join(item), false)
			if id == "":
				failed += 1
			else:
				assign_collection(id, collection)
	zip.close()
	if failed > 0:
		last_error = tr_n("%d item of the collection could not be imported.",
				"%d items of the collection could not be imported.", failed) % failed
	return collection


func _is_newer(data: Dictionary) -> bool:
	var version: Variant = data.get("format", 0)
	return (version is float or version is int) and version > format_version


# --- Images -------------------------------------------------------------------
# Each image is saved as <base_name>.<format>, such as "idle.jpg" or
# "image.webp". There is only one file per base name.

## Real format from the first bytes, or "" if not supported. The extension is not
## trusted: a PNG saved as ".jpg" is still recognised as PNG.
static func detect_format(content: PackedByteArray) -> String:
	if content.size() >= 8 and content.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
		return "png"
	if content.size() >= 3 and content.slice(0, 3) == PackedByteArray([0xFF, 0xD8, 0xFF]):
		return "jpg"
	if content.size() >= 12 and content.slice(0, 4).get_string_from_ascii() == "RIFF" \
			and content.slice(8, 12).get_string_from_ascii() == "WEBP":
		return "webp"
	return ""


## "" if there is none.
func _saved_image_path(id: String, base_name: String) -> String:
	for format in IMAGE_FORMATS:
		var path := _item_folder(id).path_join("%s.%s" % [base_name, format])
		if FileAccess.file_exists(path):
			return path
	return ""


func _load_texture(id: String, base_name: String) -> Texture2D:
	var path := _saved_image_path(id, base_name)
	if path == "":
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


## Returns false if it is not a valid image.
func _save_image_from_file(id: String, base_name: String, source: String) -> bool:
	if not FileAccess.file_exists(source):
		return false
	return _save_validated_image(id, base_name, FileAccess.get_file_as_bytes(source))


## Saves the content only if it is a readable PNG, JPG or WebP. The original file
## is kept (not a conversion), so there is no quality loss and no size increase.
func _save_validated_image(id: String, base_name: String, content: PackedByteArray) -> bool:
	var format := detect_format(content)
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	match format:
		"png":
			error = image.load_png_from_buffer(content)
		"jpg":
			error = image.load_jpg_from_buffer(content)
		"webp":
			error = image.load_webp_from_buffer(content)
	if error != OK or image.is_empty():
		return false
	# The previous image goes away even if it has another format.
	_remove_image(id, base_name)
	var file := FileAccess.open(_item_folder(id).path_join("%s.%s" % [base_name, format]),
			FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(content)
	return true


func _remove_image(id: String, base_name: String) -> void:
	for format in IMAGE_FORMATS:
		var path := _item_folder(id).path_join("%s.%s" % [base_name, format])
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Imports the first valid image with that base name (any supported extension).
func _import_image(zip: ZIPReader, files: PackedStringArray, id: String, base_name: String) -> bool:
	for file_extension in IMAGE_FORMATS + ["jpeg"]:
		var inner: String = _zip_prefix + "%s.%s" % [base_name, file_extension]
		if inner in files and _save_validated_image(id, base_name, zip.read_file(inner)):
			return true
	return false


# --- For subclasses -----------------------------------------------------------

## Content file names of an item (without the data file).
func _content_files(_id: String) -> PackedStringArray:
	return PackedStringArray()


## Data copied when duplicating, without name and format.
func _own_data(data: Dictionary) -> Dictionary:
	var own := data.duplicate(true)
	own.erase("name")
	own.erase("format")
	return own


## Accepted (and validated) data of an imported file.
func _imported_data(_data: Dictionary) -> Dictionary:
	return {}


## Copies and validates the content of an imported file. Returns "" if all went
## well, or the translated reason (the new item is then erased).
func _import_content(_zip: ZIPReader, _files: PackedStringArray, _id: String) -> String:
	return ""


## Id of a library item with the same content as the one in the ZIP (in the
## _zip_prefix folder), or "".
func _find_same(_zip: ZIPReader, _files: PackedStringArray) -> String:
	return ""


func _thumbnail_texture(_id: String) -> Texture2D:
	return null


# --- Internals ----------------------------------------------------------------

## Creates an item with the given data and returns its id. It goes last in the
## gallery, or right after "after" if given.
func _create(desired_name: String, initial_data: Dictionary = {}, after: String = "") -> String:
	var data := initial_data.duplicate(true)
	data["name"] = unique_name(desired_name)
	var order := Array(list_ids())
	var id := _new_id()
	DirAccess.make_dir_recursive_absolute(_item_folder(id))
	_write_data(id, data)
	var index := order.find(after)
	if index == -1:
		order.append(id)
	else:
		order.insert(index + 1, id)
	_write_order(PackedStringArray(order))
	if collection_for_new != "" and _zip_prefix == "":
		assign_collection(id, collection_for_new)
	return id


func _item_folder(id: String) -> String:
	return folder.path_join(id)


func _data_path(id: String) -> String:
	return _item_folder(id).path_join(data_file)


func _read_data(id: String) -> Dictionary:
	if not FileAccess.file_exists(_data_path(id)):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_data_path(id)))
	return data if data is Dictionary else {}


func _write_data(id: String, data: Dictionary) -> void:
	data["format"] = format_version
	var file := FileAccess.open(_data_path(id), FileAccess.WRITE)
	if file == null:
		push_error("Could not save %s %s." % [type_name, id])
		return
	file.store_string(JSON.stringify(data, "\t"))


## Deletes for good, without the trash.
func _erase(id: String) -> bool:
	for file in DirAccess.get_files_at(_item_folder(id)):
		DirAccess.remove_absolute(_item_folder(id).path_join(file))
	_remove_from_order(id)
	assign_collection(id, "")
	return DirAccess.remove_absolute(_item_folder(id)) == OK


func _read_order() -> PackedStringArray:
	var path := folder.path_join(ORDER_FILE)
	if not FileAccess.file_exists(path):
		return PackedStringArray()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var ids := PackedStringArray()
	if data is Array:
		for id in data:
			if id is String:
				ids.append(id)
	return ids


func _write_order(ids: PackedStringArray) -> void:
	var file := FileAccess.open(folder.path_join(ORDER_FILE), FileAccess.WRITE)
	if file == null:
		push_error("Could not save the %s order." % type_name)
		return
	file.store_string(JSON.stringify(Array(ids), "\t"))


func _remove_from_order(id: String) -> void:
	var order := Array(_read_order())
	if id in order:
		order.erase(id)
		_write_order(PackedStringArray(order))


func _new_id() -> String:
	var id := ""
	while id == "" or DirAccess.dir_exists_absolute(_item_folder(id)):
		id = "%d_%06x" % [int(Time.get_unix_time_from_system()), randi() % 0x1000000]
	return id


static func _numbered(base: String, used: Dictionary) -> String:
	if not used.has(base.to_lower()):
		return base
	var number := 2
	while used.has(("%s (%d)" % [base, number]).to_lower()):
		number += 1
	return "%s (%d)" % [base, number]


func _fail(reason: String) -> String:
	last_error = reason
	return ""
