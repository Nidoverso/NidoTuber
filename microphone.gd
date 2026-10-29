class_name Microphone
extends AudioStreamPlayer
## Reads the microphone volume and reports when you start or stop talking.
## Needs an audio bus called "Mic" whose first effect is an AudioEffectCapture.

## Emitted only when the state changes.
signal talking_changed(talking: bool)

## Bottom of the scale, in dB. Anything below counts as silence.
const LEVEL_MIN_DB: float = -60.0

## Volume from which the mouth opens.
var threshold_db: float = -35.0
## Seconds the mouth stays open after dropping below the threshold (avoids
## flickering between syllables).
var hold_time: float = 0.15

## Current level, shown in the panel.
var level_db: float = LEVEL_MIN_DB
var talking: bool = false

var _capture: AudioEffectCapture
var _time_below: float = 0.0


func _ready() -> void:
	var bus_index := AudioServer.get_bus_index("Mic")
	if bus_index == -1:
		push_error("The 'Mic' audio bus does not exist.")
		set_process(false)
		return
	_capture = AudioServer.get_bus_effect(bus_index, 0) as AudioEffectCapture
	if _capture == null:
		push_error("The first effect of the 'Mic' bus must be an AudioEffectCapture.")
		set_process(false)
		return
	stream = AudioStreamMicrophone.new()
	bus = "Mic"
	play()


## Playback is not restarted: the audio driver switches devices on its own, and
## stop() + play() breaks the capture (the deferred stop closes the new device).
func change_device(device: String) -> void:
	if device == AudioServer.input_device:
		return
	AudioServer.input_device = device
	if _capture:
		_capture.clear_buffer()
	if not playing:
		play()


func _process(delta: float) -> void:
	var frames := _capture.get_frames_available()
	if frames > 0:
		level_db = _to_db(_capture.get_buffer(frames))
	if level_db >= threshold_db:
		_time_below = 0.0
		_set_talking(true)
	else:
		_time_below += delta
		if _time_below >= hold_time:
			_set_talking(false)


## RMS of both channels.
func _to_db(buffer: PackedVector2Array) -> float:
	var total := 0.0
	for sample in buffer:
		total += (sample.x * sample.x + sample.y * sample.y) * 0.5
	var rms := sqrt(total / buffer.size())
	return maxf(linear_to_db(rms), LEVEL_MIN_DB)


func _set_talking(value: bool) -> void:
	if value == talking:
		return
	talking = value
	talking_changed.emit(talking)


# --- Readable device names ----------------------------------------------------
# Only what the panel shows changes; Godot keeps using the full identifier.

const _ALSA_PREFIXES := ["alsa_input.", "alsa_output."]
const _BLUETOOTH_PREFIXES := ["bluez_input.", "bluez_source.", "bluez_output.", "bluez_sink."]


## Same order as the identifiers. Repeated names get a number.
static func readable_names(ids: PackedStringArray) -> PackedStringArray:
	var names := PackedStringArray()
	var uses := {}
	for id in ids:
		var device_name := readable_name(id)
		uses[device_name] = uses.get(device_name, 0) + 1
		if uses[device_name] > 1:
			device_name += " (%d)" % uses[device_name]
		names.append(device_name)
	return names


## Simplifies Linux (ALSA, PulseAudio, PipeWire) identifiers. Names that follow
## no known pattern (Windows, macOS) are already readable and stay as they are.
static func readable_name(id: String) -> String:
	if id == "Default":
		return TranslationServer.translate("System default")

	# Plain ALSA, such as "hw:CARD=PCH,DEV=0".
	var card := RegEx.create_from_string("CARD=([^,]+)").search(id)
	if card:
		return _clean(card.get_string(1))

	var device_name := id
	# A "monitor" is a speaker output seen as an input.
	var monitor := device_name.ends_with(".monitor")
	device_name = device_name.trim_suffix(".monitor")

	var bluetooth := false
	var known := false
	for prefix in _ALSA_PREFIXES:
		if device_name.begins_with(prefix):
			device_name = device_name.trim_prefix(prefix)
			known = true
	for prefix in _BLUETOOTH_PREFIXES:
		if device_name.begins_with(prefix):
			device_name = device_name.trim_prefix(prefix)
			known = true
			bluetooth = true

	if not known:
		return _clean(device_name) if not " " in device_name else device_name

	device_name = _bluetooth_name(device_name) if bluetooth else _alsa_name(device_name)
	return TranslationServer.translate("Monitor of %s") % device_name if monitor else device_name


## "usb-Brand_Model_SERIAL-00.analog-stereo" -> "Brand Model"
static func _alsa_name(device_name: String) -> String:
	var profile := RegEx.create_from_string("\\.[a-z0-9]+(-[a-z0-9]+)*$").search(device_name)
	if profile:
		device_name = device_name.substr(0, profile.get_start())
	if device_name.begins_with("pci-"):
		return TranslationServer.translate("Internal audio")
	if device_name.begins_with("platform-"):
		return TranslationServer.translate("Built-in audio")
	device_name = device_name.trim_prefix("usb-")
	device_name = RegEx.create_from_string("-\\d{2}$").sub(device_name, "")
	return _clean(device_name)


## Godot only gives the address, so its end is shown: "Bluetooth EE:FF".
static func _bluetooth_name(device_name: String) -> String:
	var address := RegEx.create_from_string("([0-9A-Fa-f]{2}[_:]){5}[0-9A-Fa-f]{2}").search(device_name)
	if address:
		var octets := address.get_string().replace(":", "_").split("_")
		return "Bluetooth %s:%s" % [octets[4], octets[5]]
	return "Bluetooth"


## Separators become spaces and serial numbers (long words of capitals and
## digits) are removed.
static func _clean(text: String) -> String:
	var words := PackedStringArray()
	for word in text.replace("_", " ").replace("-", " ").split(" ", false):
		var is_serial := word.length() >= 8 \
				and RegEx.create_from_string("^[A-Z0-9]+$").search(word) != null \
				and RegEx.create_from_string("\\d").search(word) != null
		if not is_serial:
			words.append(word)
	var result := " ".join(words)
	return result if result != "" else text
