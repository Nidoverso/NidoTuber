class_name Motion
extends Node
## Idle motion of an avatar or an accessory. It only computes values; the owner
## applies them to whatever it draws.
##
## Four independent parts, each with its own rhythm:
##   - Path: follows a figure around its position.
##   - Tilt: rocks from side to side.
##   - Breathing: shrinks slightly and returns to its size.
##   - Jump: periodic jumps with a random interval between them.

const SETTINGS := [
	"path_enabled", "amplitude_x", "amplitude_y", "oscillations_x", "oscillations_y",
	"phase_y", "cycle_duration",
	"tilt_enabled", "tilt_angle", "tilt_duration",
	"jump_enabled", "jump_height", "jump_duration", "jump_interval_min", "jump_interval_max",
	"breathing_enabled", "breathing_x", "breathing_y", "breathing_duration",
]

# --- Path ---
## The path is a Lissajous curve: each axis oscillates on its own and the figure
## comes from how they combine. Per cycle, the horizontal axis does
## "oscillations_x" swings and the vertical one "oscillations_y", with the
## vertical axis "phase_y" degrees ahead. For example:
##   1 and 2, phase 180° or 0°:  horizontal eight (one per direction).
##   2 and 1, phase 90° or 0°:   vertical eight.
##   1 and 1, phase 270° or 90°: circle, clockwise or counterclockwise.
##   1 and 2, phase 90° or 270°: "U" or "∩" arc (a swing).
var path_enabled: bool = true
## Pixels.
var amplitude_x: float = 0.0
var amplitude_y: float = 8.0
## Rounded to integers so the figure closes.
var oscillations_x: float = 1.0
var oscillations_y: float = 2.0
## Degrees (0–360).
var phase_y: float = 180.0
## Seconds to complete the figure.
var cycle_duration: float = 4.0

# --- Tilt ---
var tilt_enabled: bool = true
## Maximum angle to each side, in degrees.
var tilt_angle: float = 1.5
var tilt_duration: float = 4.0

# --- Jump ---
var jump_enabled: bool = false
## Pixels.
var jump_height: float = 10.0
## Seconds of each jump (up and down).
var jump_duration: float = 0.3
## Seconds between jumps, picked at random between both values.
var jump_interval_min: float = 1.0
var jump_interval_max: float = 3.0

# --- Breathing ---
var breathing_enabled: bool = true
## Maximum shrink, as a proportion (0.03 = 3 %).
var breathing_x: float = 0.02
var breathing_y: float = 0.04
var breathing_duration: float = 4.0

## Vertical jump offset (negative = up). Animated by a tween.
var jump: float = 0.0

## Phases are accumulated instead of derived from total time, so changing a
## duration does not make anything skip.
var _phase: float = 0.0
var _breathing_phase: float = 0.0
var _tilt_phase: float = 0.0
var _jump_tween: Tween
var _jump_timer: Timer
var _jumping: bool = false
var _defaults: Dictionary = {}


func _init() -> void:
	_defaults = Settings.capture(self, SETTINGS)


func _ready() -> void:
	_jump_timer = Timer.new()
	_jump_timer.one_shot = true
	_jump_timer.timeout.connect(_on_jump_timer)
	add_child(_jump_timer)
	_schedule_next_jump()


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta / maxf(cycle_duration, 0.05) * TAU, TAU)
	_breathing_phase = fmod(_breathing_phase + delta / maxf(breathing_duration, 0.1) * TAU, TAU)
	_tilt_phase = fmod(_tilt_phase + delta / maxf(tilt_duration, 0.1) * TAU, TAU)


# --- Values for the owner -----------------------------------------------------

func path_offset() -> Vector2:
	if not path_enabled:
		return Vector2.ZERO
	var point := path_point(_phase)
	return Vector2(point.x * amplitude_x, point.y * amplitude_y)


## Path and jump together.
func offset() -> Vector2:
	return path_offset() + Vector2(0.0, jump)


## Degrees.
func tilt() -> float:
	return tilt_angle * sin(_tilt_phase) if tilt_enabled else 0.0


## 1 at rest, smaller while shrinking.
func breathing_scale() -> Vector2:
	if not breathing_enabled:
		return Vector2.ONE
	var shrink := 0.5 - 0.5 * cos(_breathing_phase)
	return Vector2(1.0 - breathing_x * shrink, 1.0 - breathing_y * shrink)


## From -1 to 1 depending on which way it moves along an axis ("horizontal" or
## "vertical"); 0 at the ends of that axis, where it turns around. It is the
## derivative of the position without its amplitude. 0 if it does not move on that axis.
func depth(axis: String) -> float:
	if not path_enabled:
		return 0.0
	if axis == "vertical":
		if amplitude_y <= 0.0:
			return 0.0
		return cos(roundf(oscillations_y) * _phase + deg_to_rad(phase_y))
	if amplitude_x <= 0.0:
		return 0.0
	return cos(roundf(oscillations_x) * _phase)


## Point of the figure without amplitudes (-1 to 1 per axis). Y grows downwards.
func path_point(phase: float) -> Vector2:
	return Vector2(
			sin(roundf(oscillations_x) * phase),
			sin(roundf(oscillations_y) * phase + deg_to_rad(phase_y)))


## Changes the phase so the same figure is followed the other way round. Going
## backwards is equivalent (with a time shift) to the phase
## 180° - phase - 180° × oscillations_y / oscillations_x.
func reverse_direction() -> void:
	var x := maxf(roundf(oscillations_x), 1.0)
	var y := maxf(roundf(oscillations_y), 1.0)
	phase_y = fposmod(180.0 - phase_y - 180.0 * y / x, 360.0)


# --- Settings -----------------------------------------------------------------

## Changes some defaults (an accessory, for example, starts still).
func set_defaults(values: Dictionary) -> void:
	for property in values:
		if property in SETTINGS:
			_defaults[property] = values[property]
			set(property, values[property])


func get_settings() -> Dictionary:
	return Settings.read(self, SETTINGS)


func default_settings() -> Dictionary:
	return Settings.to_json_all(_defaults)


func apply_settings(data: Dictionary) -> void:
	Settings.apply(self, data, _defaults)


# --- Jump ---------------------------------------------------------------------

## Animates a jump on a property and returns its tween. The way up is faster than
## the way down (28 % / 72 %), which feels like a small hop.
static func animate_jump(object: Node, property: String, height: float, duration: float,
		previous: Tween) -> Tween:
	if previous:
		previous.kill()
	var tween := object.create_tween()
	duration = maxf(duration, 0.02)
	tween.tween_property(object, property, -height, duration * 0.28) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(object, property, 0.0, duration * 0.72) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return tween


func _schedule_next_jump() -> void:
	var low := minf(jump_interval_min, jump_interval_max)
	var high := maxf(jump_interval_min, jump_interval_max)
	_jump_timer.start(maxf(randf_range(low, high), 0.05))


## The timer alternates between the jump and the following interval, so the
## interval starts counting once the jump is over.
func _on_jump_timer() -> void:
	if _jumping:
		_jumping = false
		_schedule_next_jump()
	elif jump_enabled and jump_height > 0.0:
		_jumping = true
		_jump_tween = animate_jump(self, "jump", jump_height, jump_duration, _jump_tween)
		_jump_timer.start(maxf(jump_duration, 0.02))
	else:
		_schedule_next_jump()
