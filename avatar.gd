class_name Avatar
extends Node2D
## The avatar on screen: which image is shown and how it moves.
## Idle motion comes from its Motion node (shared with accessories); the talking
## jump and blinking are handled here.

## One "tex_<state>" variable per state.
const STATES := ["idle", "talking", "idle_blink", "talking_blink"]

## Pause between the two blinks of a double blink.
const DOUBLE_BLINK_PAUSE: float = 0.12

## Saved together with Motion.SETTINGS in the same dictionary.
## The values below are those of a new avatar.
const SETTINGS := [
	"base_size", "multiplier", "smoothing", "integer_scaling", "window_position",
	"talk_jump_enabled", "talk_jump_height", "talk_jump_duration",
	"blink_enabled", "blink_interval_min", "blink_interval_max",
	"blink_duration", "double_blink_chance",
]
const OPTIONS := {
	"base_size": ["window_height", "original"],
}
const MULTIPLIER_MIN := 0.01
const MULTIPLIER_MAX := 5.0

# --- Scale ---
## Reference size the multiplier applies to:
##   window_height: the idle image fills the window height.
##   original:      the image's size in pixels.
var base_size: String = "window_height"
var multiplier: float = 1.0
## Off: pixels are enlarged as they are (nearest filter), best for pixel art.
var smoothing: bool = true:
	set(value):
		smoothing = value
		if is_node_ready():
			_apply_filter()
## Only without smoothing: rounds the final scale to a whole number (or an exact
## fraction below 1) so every pixel has the same size on screen. Breathing is
## ignored while it has effect.
var integer_scaling: bool = false

# --- Position ---
## Offset of the avatar's centre from the window's centre, in window sizes:
## 0.5 reaches the right/bottom edge. Starts slightly low to leave room above.
var window_position: Vector2 = Vector2(0.0, 0.1)

# --- Talking ---
var talk_jump_enabled: bool = true
var talk_jump_height: float = 6.0
var talk_jump_duration: float = 0.25

# --- Blink ---
var blink_enabled: bool = true
var blink_interval_min: float = 2.0
var blink_interval_max: float = 6.0
## Seconds the eyes stay closed.
var blink_duration: float = 0.15
## 0–1.
var double_blink_chance: float = 0.15

## Set by Main from the avatar library.
var tex_idle: Texture2D
var tex_talking: Texture2D
var tex_idle_blink: Texture2D
var tex_talking_blink: Texture2D

var mouth_open: bool = false
var eyes_closed: bool = false

## Created here so it exists before settings are applied.
var motion := Motion.new()

## Vertical talking jump offset (negative = up).
var _talk_jump: float = 0.0
var _talk_jump_tween: Tween
var _blink_timer: Timer
var _double_pending: bool = false
var _second_of_double: bool = false
var _defaults: Dictionary = {}

@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	_defaults = Settings.capture(self, SETTINGS)
	motion.name = "Motion"
	add_child(motion)
	_blink_timer = Timer.new()
	_blink_timer.one_shot = true
	_blink_timer.timeout.connect(_on_blink_timer)
	add_child(_blink_timer)
	_schedule_next_blink()
	_apply_filter()
	_update_texture()


func _apply_filter() -> void:
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if smoothing \
			else CanvasItem.TEXTURE_FILTER_NEAREST


func _process(_delta: float) -> void:
	position = base_position() + motion.path_offset() + jump_offset()
	rotation_degrees = motion.tilt()
	# The sprite is centred on this node, so scaling shrinks it from its centre.
	sprite.scale = Vector2.ONE * scale_factor() * breathing_scale()


## Both jumps (talking and idle).
func jump_offset() -> Vector2:
	return Vector2(0.0, _talk_jump + motion.jump)


func scale_factor() -> float:
	var factor := _base_factor() * multiplier
	if integer_scaling_effective() and factor > 0.0:
		factor = floorf(factor) if factor >= 1.0 else 1.0 / ceilf(1.0 / factor)
	return factor


## Size of the idle image on screen, without breathing. Accessories are
## positioned relative to it.
func size_on_screen() -> Vector2:
	var reference: Texture2D = tex_idle if tex_idle else sprite.texture
	if reference == null:
		return Vector2.ZERO
	return reference.get_size() * scale_factor()


func integer_scaling_effective() -> bool:
	return integer_scaling and not smoothing


## Breathing would change the size in steps with integer scaling.
func breathing_effective() -> bool:
	return motion.breathing_enabled and not integer_scaling_effective()


func breathing_scale() -> Vector2:
	return motion.breathing_scale() if breathing_effective() else Vector2.ONE


## Changes the base size adjusting the multiplier so the avatar keeps its size
## on screen (within the multiplier limits).
func change_base_size(new_size: String) -> void:
	if new_size == base_size or not new_size in OPTIONS["base_size"]:
		return
	var current := _base_factor() * multiplier
	base_size = new_size
	multiplier = clampf(current / _base_factor(), MULTIPLIER_MIN, MULTIPLIER_MAX)


## The idle image is the reference for every state, so the avatar does not
## change size if an image has different dimensions.
func _base_factor() -> float:
	if base_size != "window_height":
		return 1.0
	var reference: Texture2D = tex_idle if tex_idle else sprite.texture
	if reference == null or reference.get_height() <= 0:
		return 1.0
	return get_viewport_rect().size.y / reference.get_height()


## Centre of the avatar without motion, in window pixels.
func base_position() -> Vector2:
	var window := get_viewport_rect().size
	return window / 2.0 + window_position * window


func current_state() -> String:
	if eyes_closed:
		return "talking_blink" if mouth_open else "idle_blink"
	return "talking" if mouth_open else "idle"


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
	motion.apply_settings(data)


# --- Images -------------------------------------------------------------------

func set_texture(state: String, texture: Texture2D) -> void:
	set("tex_" + state, texture)
	_update_texture()


func get_texture(state: String) -> Texture2D:
	return get("tex_" + state) as Texture2D


func _update_texture() -> void:
	sprite.texture = get_texture(current_state())


# --- Talking ------------------------------------------------------------------

func set_mouth_open(value: bool) -> void:
	if value and not mouth_open and talk_jump_enabled and talk_jump_height > 0.0:
		_talk_jump_tween = Motion.animate_jump(self, "_talk_jump", talk_jump_height,
				talk_jump_duration, _talk_jump_tween)
	mouth_open = value
	_update_texture()


# --- Blink --------------------------------------------------------------------

func set_eyes_closed(value: bool) -> void:
	eyes_closed = value
	_update_texture()


func _schedule_next_blink() -> void:
	var low := minf(blink_interval_min, blink_interval_max)
	var high := maxf(blink_interval_min, blink_interval_max)
	_blink_timer.start(randf_range(low, high))


func _on_blink_timer() -> void:
	if eyes_closed:
		set_eyes_closed(false)
		if _double_pending:
			_double_pending = false
			_second_of_double = true
			_blink_timer.start(DOUBLE_BLINK_PAUSE)
		else:
			_schedule_next_blink()
	elif blink_enabled:
		# Only the first blink can turn into a double one.
		if _second_of_double:
			_second_of_double = false
		else:
			_double_pending = randf() < double_blink_chance
		set_eyes_closed(true)
		_blink_timer.start(blink_duration)
	else:
		# Disabled: keep checking in case it is enabled again.
		_second_of_double = false
		_schedule_next_blink()
