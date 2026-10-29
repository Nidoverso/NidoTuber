class_name Accessory
extends Node2D
## An accessory on screen: one image with its placement settings. The same class
## is used for the library preview and for accessories placed on an avatar or a
## background.
##
## Anchor (where it is):
##   avatar: moves with the avatar. The offset is measured in avatar sizes from
##           its centre, and "follow_*" decide which avatar movements it inherits.
##   window: fixed in the scene. The offset is measured in window sizes.
## Base size (what its size is relative to), before the multiplier:
##   avatar:        the avatar's scale, so it grows and shrinks with it.
##   window_height: the image fills the window height.
##   original:      the image's size in pixels.
##
## Depth: its own path is seen as a route around the avatar. Depending on which
## way it moves along one axis it is closer (in front) or further (behind), and
## it switches side at the ends of that axis. Used by the "alternate" layer, the
## perspective and "flip_on_side_change".

const ANCHORS := ["avatar", "window"]
const LAYERS := ["front", "back", "alternate"]
const DEPTH_AXES := ["horizontal", "vertical"]
const BASE_SIZES := ["avatar", "window_height", "original"]
## Drawing order relative to the avatar (at 0). Multiplied by "tier".
const Z_LAYERS := {"front": 1, "back": -1}
## 0.5 = up to 50 % bigger in front and smaller behind.
const PERSPECTIVE_MAX := 0.5
const MULTIPLIER_MIN := 0.01
const MULTIPLIER_MAX := 5.0

## Saved together with Motion.SETTINGS in the same dictionary.
const SETTINGS := [
	"smoothing", "integer_scaling", "base_size", "multiplier", "angle", "flip",
	"anchor", "anchor_offset", "layer",
	"depth_axis", "invert_depth", "flip_on_side_change", "perspective",
	"visible_idle", "visible_talking", "visible_idle_blink", "visible_talking_blink",
	"follow_path", "follow_tilt", "follow_breathing", "follow_jump",
]
const OPTIONS := {
	"anchor": ANCHORS, "layer": LAYERS, "base_size": BASE_SIZES, "depth_axis": DEPTH_AXES,
}

# --- Image ---
var smoothing: bool = true:
	set(value):
		smoothing = value
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if value \
				else CanvasItem.TEXTURE_FILTER_NEAREST
## Same as the avatar's. While it has effect, breathing (its own and the avatar's)
## and perspective do not change the size.
var integer_scaling: bool = false
var base_size: String = "avatar"
var multiplier: float = 1.0
## Fixed rotation, in degrees.
var angle: float = 0.0
## Horizontal mirror.
var flip: bool = false

# --- Position ---
var anchor: String = "avatar"
## Y grows downwards, as in the avatar.
var anchor_offset: Vector2 = Vector2.ZERO
var layer: String = "front":
	set(value):
		layer = value
		_update_z(1.0)

# --- Depth ---
var depth_axis: String = "horizontal"
## Changes which half of the route is in front, keeping the direction of motion.
var invert_depth: bool = false
## Mirrored while behind: on a circle with "horizontal", it turns around at each
## end, so a bird always faces where it flies. Combined with "flip".
var flip_on_side_change: bool = false
## 0 = none, 0.5 = 50 %. Gradual: normal size where it switches side.
var perspective: float = 0.0

# --- Avatar states in which it is visible ---
var visible_idle: bool = true
var visible_talking: bool = true
var visible_idle_blink: bool = true
var visible_talking_blink: bool = true

# --- Avatar movements it inherits (avatar anchor only) ---
var follow_path: bool = true
var follow_tilt: bool = true
var follow_breathing: bool = true
var follow_jump: bool = true

## Followed avatar; its state also decides visibility.
var avatar: Avatar
## 1 for avatar accessories and the preview, 2 for background ones: what a
## background puts behind stays behind everything of the avatar, and what it puts
## in front stays in front of everything (the scene's foreground).
var tier: int = 1:
	set(value):
		tier = value
		_update_z(1.0)
## Library id it comes from (empty for the preview).
var accessory_id: String = ""
## Its own idle motion. A new accessory starts still.
var motion := Motion.new()

var _sprite := Sprite2D.new()
var _defaults: Dictionary = {}


func _init() -> void:
	_update_z(1.0)
	add_child(_sprite)
	motion.name = "Motion"
	add_child(motion)
	motion.set_defaults({
		"path_enabled": false, "tilt_enabled": false,
		"breathing_enabled": false, "jump_enabled": false,
	})
	_defaults = Settings.capture(self, SETTINGS)
	# Processed after the avatar, to use its position of the same frame.
	process_priority = 10


func _process(_delta: float) -> void:
	_sprite.visible = avatar == null or bool(get("visible_" + avatar.current_state()))
	if layer == "alternate":
		_update_z(depth())
	if anchor == "avatar" and avatar:
		_follow_avatar()
	else:
		_fix_to_window()


func _follow_avatar() -> void:
	var offset := Vector2.ZERO
	if follow_path:
		offset += avatar.motion.path_offset()
	if follow_jump:
		offset += avatar.jump_offset()
	var breathing := avatar.breathing_scale() if follow_breathing else Vector2.ONE
	var turn := avatar.rotation if follow_tilt else 0.0

	# Measured in the avatar's space: if it shrinks or tilts, the accessory stays
	# on the same point of the image.
	var point := (anchor_offset * avatar.size_on_screen() * breathing).rotated(turn)
	position = avatar.base_position() + offset + point + motion.offset()
	rotation = turn + deg_to_rad(angle + motion.tilt())
	_apply_scale(breathing)


func _fix_to_window() -> void:
	var window := get_viewport_rect().size
	position = window / 2.0 + anchor_offset * window + motion.offset()
	rotation = deg_to_rad(angle + motion.tilt())
	_apply_scale(Vector2.ONE)


func _update_z(current_depth: float) -> void:
	var side := layer
	if layer == "alternate":
		side = "front" if current_depth >= 0.0 else "back"
	z_index = Z_LAYERS[side] * tier


## From -1 (furthest, behind) to 1 (closest, in front).
func depth() -> float:
	var value := motion.depth(depth_axis)
	return -value if invert_depth else value


## avatar_breathing: the inherited avatar breathing (1 if not followed).
func _apply_scale(avatar_breathing: Vector2) -> void:
	var result := Vector2.ONE * scale_factor()
	if not integer_scaling_effective():
		result *= avatar_breathing * motion.breathing_scale() * (1.0 + perspective * depth())
	if flip != (flip_on_side_change and depth() < 0.0):
		result.x = -result.x
	scale = result


func scale_factor() -> float:
	var factor := _base_factor() * multiplier
	if integer_scaling_effective() and factor > 0.0:
		factor = floorf(factor) if factor >= 1.0 else 1.0 / ceilf(1.0 / factor)
	return factor


func integer_scaling_effective() -> bool:
	return integer_scaling and not smoothing


func breathing_effective() -> bool:
	return motion.breathing_enabled and not integer_scaling_effective()


## Changes the base size adjusting the multiplier so the accessory keeps its
## size on screen (within the multiplier limits).
func change_base_size(new_size: String) -> void:
	if new_size == base_size or not new_size in BASE_SIZES:
		return
	var current := scale_factor()
	base_size = new_size
	var base := _base_factor()
	if base > 0.0:
		multiplier = clampf(current / base, MULTIPLIER_MIN, MULTIPLIER_MAX)


func _base_factor() -> float:
	match base_size:
		"avatar":
			return avatar.scale_factor() if avatar else 1.0
		"window_height":
			var texture := _sprite.texture
			if texture and texture.get_height() > 0:
				return get_viewport_rect().size.y / texture.get_height()
	return 1.0


func set_texture(texture: Texture2D) -> void:
	_sprite.texture = texture


func get_texture() -> Texture2D:
	return _sprite.texture


# --- Settings -----------------------------------------------------------------

func get_settings() -> Dictionary:
	var data := Settings.read(self, SETTINGS)
	data.merge(motion.get_settings())
	return data


func default_settings() -> Dictionary:
	var data := Settings.to_json_all(_defaults)
	data.merge(motion.default_settings())
	return data


func apply_settings(data: Dictionary) -> void:
	Settings.apply(self, data, _defaults, OPTIONS)
	multiplier = clampf(multiplier, MULTIPLIER_MIN, MULTIPLIER_MAX)
	perspective = clampf(perspective, 0.0, PERSPECTIVE_MAX)
	motion.apply_settings(data)
