class_name BackgroundLibrary
extends Library
## Backgrounds in user://backgrounds/<id>/: background.json (name, colour, fit
## and placed accessories) and an optional image (image.png/.jpg/.webp), stored
## as it came. The colour fills the window behind the image; without an image the
## background is just the colour, the usual chroma key for OBS.
## Exported as .nidobg files.

## How the image fits the window:
##   cover:   fills the window, cropping what does not fit.
##   contain: shows the whole image; the gaps show the colour.
##   stretch: fills the window, deforming the image if needed.
const FITS := ["cover", "contain", "stretch"]
const DEFAULT_FIT := "cover"
## Chroma green.
const DEFAULT_COLOR := Color(0.0, 1.0, 0.0)
## English; translated when created.
const EXAMPLE_NAME := "Example background"


func _init() -> void:
	super("user://backgrounds", "background.json", "nidobg", "New background", "background",
			"backgrounds")


## Creates a plain colour background, without an image, and returns its id.
func create(desired_name: String, initial_color: Color = DEFAULT_COLOR) -> String:
	return _create(desired_name, {"color": _color_to_text(initial_color), "fit": DEFAULT_FIT})


func color(id: String) -> Color:
	return _text_to_color(_read_data(id).get("color"))


func change_color(id: String, new_color: Color) -> void:
	if not exists(id):
		return
	var data := _read_data(id)
	var text := _color_to_text(new_color)
	if data.get("color") == text:
		return
	data["color"] = text
	_write_data(id, data)


func fit(id: String) -> String:
	var value: Variant = _read_data(id).get("fit")
	return value if value in FITS else DEFAULT_FIT


func change_fit(id: String, mode: String) -> void:
	if not exists(id) or not mode in FITS:
		return
	var data := _read_data(id)
	data["fit"] = mode
	_write_data(id, data)


func has_image(id: String) -> bool:
	return _saved_image_path(id, "image") != ""


func texture(id: String) -> Texture2D:
	return _load_texture(id, "image")


## Returns false if it is not a valid image.
func save_image(id: String, source: String) -> bool:
	return _save_image_from_file(id, "image", source)


func remove_image(id: String) -> void:
	_remove_image(id, "image")


## The image over its colour (so transparent areas show it), or a colour swatch.
func thumbnail(id: String, size: int) -> Texture2D:
	var source := texture(id)
	var image: Image = source.get_image().duplicate() if source else null
	if image == null or image.is_empty():
		var swatch := Image.create(size, roundi(size * 9.0 / 16.0), false, Image.FORMAT_RGBA8)
		swatch.fill(color(id))
		return ImageTexture.create_from_image(swatch)
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var factor := float(size) / maxf(image.get_width(), image.get_height())
	if factor < 1.0:
		image.resize(maxi(1, roundi(image.get_width() * factor)),
				maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	var canvas := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	canvas.fill(color(id))
	canvas.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	return ImageTexture.create_from_image(canvas)


## Stored as "#rrggbb" so the JSON is readable.
static func _color_to_text(value: Color) -> String:
	return "#" + value.to_html(false)


static func _text_to_color(value: Variant) -> Color:
	if value is String and Color.html_is_valid(value):
		var result := Color.html(value)
		result.a = 1.0
		return result
	return DEFAULT_COLOR


# --- Library ------------------------------------------------------------------

func _content_files(id: String) -> PackedStringArray:
	var path := _saved_image_path(id, "image")
	return PackedStringArray([path.get_file()]) if path != "" else PackedStringArray()


func _imported_data(data: Dictionary) -> Dictionary:
	var mode: Variant = data.get("fit")
	return {
		"color": _color_to_text(_text_to_color(data.get("color"))),
		"fit": mode if mode in FITS else DEFAULT_FIT,
	}


func _import_content(zip: ZIPReader, files: PackedStringArray, id: String) -> String:
	# The image is optional: without it the background is just its colour.
	_import_image(zip, files, id, "image")
	return ""
