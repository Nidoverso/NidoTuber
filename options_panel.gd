class_name OptionsPanel
extends PanelContainer
## Options panel. Builds all its controls in code when setup() is called.
##
## Fixed texts are written in English and Godot translates them automatically.
## Texts that include a value are composed with tr() and rewritten by refresh(),
## which also runs when the language changes.

const STATE_NAMES := {
	"idle": "Idle", "talking": "Talking",
	"idle_blink": "Idle · Blink", "talking_blink": "Talking · Blink",
}
const BASE_SIZE_NAMES := {
	"avatar": "Avatar", "window_height": "Window height", "original": "Original",
}
## Preset figures for the path. Choosing one fills the parameters, which can then
## be tweaked. "phases" are both directions of the figure (the first is applied).
## "amplitudes" says what it needs:
##   no_x:  horizontal amplitude 0.
##   both:  both amplitudes above 0.
##   equal: both amplitudes equal.
const FIGURES := [
	{"name": "Up and down", "x": 1, "y": 2, "phases": [180, 0], "amplitudes": "no_x"},
	{"name": "Horizontal eight", "x": 1, "y": 2, "phases": [180, 0], "amplitudes": "both"},
	{"name": "Vertical eight", "x": 2, "y": 1, "phases": [90, 0], "amplitudes": "both"},
	{"name": "Circle", "x": 1, "y": 1, "phases": [270, 90], "amplitudes": "equal"},
	{"name": "Swing", "x": 1, "y": 2, "phases": [90, 270], "amplitudes": "both"},
]
## Amplitude set when a figure needs one that is 0.
const FIGURE_AMPLITUDE := 8.0
const FIT_NAMES := {"cover": "Cover", "contain": "Contain", "stretch": "Stretch"}
const FPS_LIMIT_NAMES := {30: "30 FPS", 60: "60 FPS", 0: "Unlimited"}
const ANCHOR_NAMES := {"avatar": "Avatar", "window": "Window"}
const LAYER_NAMES := {"front": "In front of the avatar", "back": "Behind the avatar",
		"alternate": "Alternate"}
const DEPTH_AXIS_NAMES := {"horizontal": "Left and right ends", "vertical": "Top and bottom ends"}
## Shown in their own language, never translated.
const LANGUAGE_NAMES := {"en": "English", "es": "Español"}
## Proportion of the window width. The panel grows further if its content needs it.
const MIN_WIDTH_RATIO := 0.3
const MAX_WIDTH_RATIO := 0.9
## Width of the resize handle on the right edge.
const HANDLE_WIDTH := 8.0
const IMAGE_ICON_SIZE := 48
## With nothing saved (first run) everything starts folded except each gallery.
const DEFAULT_UNFOLDED := ["avatars", "backgrounds", "accessory_library"]
## Microphone bar: track, level below the threshold and above it.
const LEVEL_TRACK_COLOR := Color(1.0, 1.0, 1.0, 0.1)
const LEVEL_COLOR := Color(0.45, 0.55, 0.7)
const LEVEL_TALKING_COLOR := Color(0.4, 0.75, 0.4)

var main: Main
var avatar: Avatar
var microphone: Microphone

var _content: VBoxContainer
## Where the _section_* methods add their controls.
var _target: Container
## Foldable sections: key -> FoldableContainer.
var _sections: Dictionary = {}
## Returns the object the controls being created edit (the avatar, its motion,
## an accessory...) or null if there is none. Each control keeps its own.
var _object: Callable
## Prefix of the section keys being created, so repeated blocks (such as the
## idle motion) get different keys.
var _prefix: String = ""
## Every slider with the functions that read and apply its value.
var _sliders: Array[Dictionary] = []
var _selectors: Array[Dictionary] = []  # {selector, property, options, object}
var _figure_selectors: Array[Dictionary] = []  # {selector, object}
var _checkboxes: Array[Dictionary] = []  # {checkbox, property, object}
## "Follow avatar" checkboxes, only meaningful with the avatar anchor.
var _follow_checkboxes: Array[Dictionary] = []  # {checkbox, object}
## Smoothing, integer scaling and breathing checkboxes of each accessory block,
## for the same exclusions as the avatar's.
var _accessory_exclusions: Array[Dictionary] = []  # {smoothing, integer, breathing, object}
## Placement lists and the container of their settings ("avatar" / "background").
var _placement_lists: Dictionary = {}
var _placement_settings: Dictionary = {}

var _avatar_gallery: Gallery
var _background_gallery: Gallery
var _accessory_gallery: Gallery
var _image_buttons: Dictionary = {}  # state -> Button
var _base_size_selector: OptionButton
var _smoothing_check: CheckBox
var _integer_check: CheckBox
var _breathing_check: CheckBox
var _background_color_picker: ColorPickerButton
var _background_image_button: Button
var _remove_background_image_button: Button
var _fit_selector: OptionButton
var _accessory_image_button: Button
var _device_selector: OptionButton
var _level_bar: ProgressBar
var _level_fill: StyleBoxFlat
var _resolution_selector: OptionButton

var _image_dialog: FileDialog
var _background_image_dialog: FileDialog
var _new_accessory_dialog: FileDialog
var _accessory_image_dialog: FileDialog
var _choosing_state: String = ""


func setup(p_main: Main, p_avatar: Avatar, p_microphone: Microphone) -> void:
	main = p_main
	avatar = p_avatar
	microphone = p_microphone

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)
	_target = _content
	_object = func() -> Object: return avatar

	_create_dialogs()

	var hide_button := Button.new()
	hide_button.text = "Hide options"
	hide_button.pressed.connect(main.show_panel.bind(false))
	_target.add_child(hide_button)

	# --- Avatar ---
	var avatar_category := _category("Avatar", "avatar")
	_target = _subsection(avatar_category, "Avatars", "avatars")
	_section_avatars()
	var avatar_settings := _subsection(avatar_category, "Avatar settings", "avatar_settings")
	_target = _subsection(avatar_settings, "Images", "images")
	_section_images()
	_target = _subsection(avatar_settings, "Scale", "scale")
	_section_scale()
	_target = _subsection(avatar_settings, "Position", "position")
	_section_position()
	_object = func() -> Object: return avatar.motion
	_breathing_check = _idle_sections(_subsection(avatar_settings, "Idle", "idle"))
	# Incompatible with integer scaling: enabling it unchecks that.
	_breathing_check.toggled.connect(func(enabled: bool) -> void:
		if enabled and avatar.integer_scaling:
			avatar.integer_scaling = false
			_integer_check.set_pressed_no_signal(false)
		_update_exclusions())
	_object = func() -> Object: return avatar
	var talking := _subsection(avatar_settings, "Talking", "talking")
	_target = _subsection(talking, "Jump", "talk_jump")
	_section_talk_jump()
	_target = _subsection(avatar_settings, "Blink", "blink")
	_section_blink()
	_section_placements(_subsection(avatar_category, "Avatar accessories", "avatar_accessories"),
			"avatar")

	# --- Background ---
	var background_category := _category("Background", "background")
	_target = _subsection(background_category, "Backgrounds", "backgrounds")
	_section_backgrounds()
	var background_settings := _subsection(background_category, "Background settings",
			"background_settings")
	_target = _subsection(background_settings, "Color", "background_color")
	_section_background_color()
	_target = _subsection(background_settings, "Image", "background_image")
	_section_background_image()
	_section_placements(_subsection(background_category, "Background accessories",
			"background_accessories"), "background")

	# --- Accessories ---
	var accessory_category := _category("Accessories", "accessories")
	_target = _subsection(accessory_category, "Accessories", "accessory_library")
	_section_accessories()
	var accessory_settings := _subsection(accessory_category, "Accessory settings",
			"accessory_settings")
	_target = accessory_settings
	_section_accessory_image()
	# The settings edited here are the preview's.
	_build_accessory_settings(accessory_settings, "accessory_",
			func() -> Object: return main.preview if main.current_accessory != "" else null)
	# Always starts folded, so opening the panel for something else does not show
	# the preview. It unfolds when an accessory is clicked.
	_sections["accessory_settings"].folded = true
	# The preview is visible while its settings are in view.
	for key in ["accessories", "accessory_settings"]:
		_sections[key].folding_changed.connect(func(_folded: bool) -> void: _update_preview())
	visibility_changed.connect(_update_preview)

	# --- General ---
	var general := _category("General", "general")
	_target = _subsection(general, "Microphone", "microphone")
	_section_microphone()
	_target = _subsection(general, "Window", "window")
	_section_window()
	_target = _subsection(general, "Performance", "performance")
	_section_performance()
	_target = _subsection(general, "Language", "language")
	_section_language()

	_create_resize_handle()
	get_viewport().size_changed.connect(_fit_to_window)
	_fit_to_window()
	refresh()


## Reads every value again: after changing avatar or background, editing a
## library or changing the language.
func refresh() -> void:
	# Placement lists first: they decide which placement is edited.
	for target in _placement_lists:
		var list: PlacementList = _placement_lists[target]
		list.refresh()
		_placement_settings[target].visible = list.selected_placement() != null
	# Controls of an object that does not exist (no accessory selected) are skipped.
	for slider_link in _sliders:
		if slider_link.object.call() == null:
			continue
		var slider: HSlider = slider_link.slider
		# Clamped to the slider's range in case a file had a value outside it, but
		# not rounded to its step, so no precision is lost.
		var value := clampf(slider_link.getter.call(), slider.min_value, slider.max_value)
		slider.set_value_no_signal(value)
		_on_slider_changed(value, slider_link)
	_smoothing_check.set_pressed_no_signal(avatar.smoothing)
	_integer_check.set_pressed_no_signal(avatar.integer_scaling)
	for link in _selectors:
		var object: Object = link.object.call()
		if object:
			link.selector.select(link.options.find(object.get(link.property)))
	for link in _checkboxes:
		var object: Object = link.object.call()
		if object:
			link.checkbox.set_pressed_no_signal(object.get(link.property))
	_update_exclusions()
	_update_follow_checkboxes()
	_update_figures()
	_base_size_selector.select(Avatar.OPTIONS["base_size"].find(avatar.base_size))
	for state in Avatar.STATES:
		_image_buttons[state].icon = avatar.get_texture(state)
	_avatar_gallery.refresh()

	var backgrounds := main.backgrounds
	var has_image := backgrounds.has_image(main.current_background)
	_background_color_picker.color = main.background_color
	_background_gallery.refresh()
	_background_image_button.icon = _background_gallery.thumbnail(main.current_background)
	_remove_background_image_button.disabled = not has_image
	_fit_selector.disabled = not has_image
	_fit_selector.select(BackgroundLibrary.FITS.find(backgrounds.fit(main.current_background)))

	_accessory_gallery.refresh()
	var has_accessory := main.current_accessory != ""
	# Without accessories there are no settings to show.
	_sections["accessory_settings"].visible = has_accessory
	if has_accessory:
		_accessory_image_button.icon = _accessory_gallery.thumbnail(main.current_accessory)
	_update_preview()

	_fill_device_selector()
	_sync_resolution()


## Folded state of every section, to save it in the configuration.
func get_folded() -> Dictionary:
	var state := {}
	for key in _sections:
		state[key] = _sections[key].folded
	return state


# --- Size ---------------------------------------------------------------------

## Full window height. Width: the one chosen by dragging its edge (at least
## MIN_WIDTH_RATIO), or what the content needs, whichever is bigger. Kept as a
## proportion so it survives resolution changes.
func _fit_to_window() -> void:
	var window := get_viewport_rect().size
	# This script controls the size, so anchors must not stretch the panel.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size.x = window.x * clampf(main.panel_width, MIN_WIDTH_RATIO, MAX_WIDTH_RATIO)
	position = Vector2.ZERO
	# A width of 0 snaps to the minimum, so the panel can also shrink.
	size = Vector2(0.0, window.y)


## A strip on the panel's right edge. It lives outside the panel (in the same
## layer) so the scroll bar does not cover it.
func _create_resize_handle() -> void:
	var handle := Control.new()
	handle.name = "PanelHandle"
	handle.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	handle.tooltip_text = "Drag to change the panel width"
	var highlighted := [false]
	handle.draw.connect(func() -> void:
		handle.draw_rect(Rect2(0, 0, 3, handle.size.y),
				Color(1, 1, 1, 0.35 if highlighted[0] else 0.08)))
	handle.mouse_entered.connect(func() -> void:
		highlighted[0] = true
		handle.queue_redraw())
	handle.mouse_exited.connect(func() -> void:
		# Stays lit while dragging.
		highlighted[0] = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and highlighted[0]
		handle.queue_redraw())
	handle.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			main.panel_width = clampf(event.global_position.x / get_viewport_rect().size.x,
					MIN_WIDTH_RATIO, MAX_WIDTH_RATIO)
			_fit_to_window()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
				and not event.pressed:
			highlighted[0] = Rect2(Vector2.ZERO, handle.size).has_point(handle.get_local_mouse_position())
			handle.queue_redraw())
	get_parent().add_child.call_deferred(handle)
	# Follows the panel's edge and is only visible with it.
	var place := func() -> void:
		handle.position = Vector2(position.x + size.x, 0.0)
		handle.size = Vector2(HANDLE_WIDTH, size.y)
		handle.visible = visible
	resized.connect(place)
	visibility_changed.connect(place)
	handle.ready.connect(place)


func _process(_delta: float) -> void:
	if visible and microphone:
		_level_bar.value = microphone.level_db
		# Green above the threshold, to calibrate at a glance.
		_level_fill.bg_color = LEVEL_TALKING_COLOR if microphone.talking else LEVEL_COLOR


## Unfolds a section and the ones containing it, without scrolling the panel.
func _show_section(key: String) -> void:
	var node: Node = _sections[key]
	while node != _content:
		if node is FoldableContainer:
			node.folded = false
		node = node.get_parent()


# --- Avatar -------------------------------------------------------------------

func _section_avatars() -> void:
	_avatar_gallery = Gallery.new()
	_avatar_gallery.minimum = 1
	_avatar_gallery.setup(main.avatars, {
		"current": func() -> String: return main.current_avatar,
		"select": main.select_avatar,
		"create": _new_avatar,
		"duplicate": main.duplicate_avatar,
		"rename": main.rename_avatar,
		"delete": main.delete_avatar,
		"import": main.import_avatar,
		"export": main.export_avatar,
		"open_folder": main.open_avatars_folder,
		"export_collection": main.export_collection.bind(main.avatars),
		"import_collection": main.import_collection.bind(main.avatars),
	}, "New", "Open avatars folder")
	_avatar_gallery.changed.connect(refresh)
	_target.add_child(_avatar_gallery)


func _new_avatar() -> void:
	_avatar_gallery.ask_name("New avatar", main.avatars.unique_name(tr(main.avatars.default_name)),
			func(avatar_name: String) -> void:
				main.create_avatar(avatar_name)
				# It starts with the placeholders: show where to change them.
				_show_section("images"))


func _section_images() -> void:
	for state in Avatar.STATES:
		var button := Button.new()
		button.text = STATE_NAMES[state]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_constant_override("icon_max_width", IMAGE_ICON_SIZE)
		# Long texts are trimmed instead of widening the panel.
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(_open_image_dialog.bind(state))
		_target.add_child(button)
		_image_buttons[state] = button


func _section_scale() -> void:
	_label("Base size")
	_base_size_selector = OptionButton.new()
	for option in Avatar.OPTIONS["base_size"]:
		_base_size_selector.add_item(BASE_SIZE_NAMES[option])
	_base_size_selector.item_selected.connect(func(i: int) -> void:
		# The multiplier is adjusted so the avatar keeps its size on screen.
		avatar.change_base_size(Avatar.OPTIONS["base_size"][i])
		refresh())
	_target.add_child(_base_size_selector)
	# Fine step, so the converted multiplier is not rounded.
	_property_slider("Multiplier", Avatar.MULTIPLIER_MIN, Avatar.MULTIPLIER_MAX, 0.01, "%.2f×",
			"multiplier")

	# Off: pixels are enlarged crisp, best for pixel art.
	_smoothing_check = CheckBox.new()
	_smoothing_check.text = "Smoothing"
	_smoothing_check.toggled.connect(func(enabled: bool) -> void:
		avatar.smoothing = enabled
		_update_exclusions())
	_target.add_child(_smoothing_check)
	# Only works without smoothing, and is incompatible with breathing.
	_integer_check = CheckBox.new()
	_integer_check.text = "Integer scaling"
	_integer_check.toggled.connect(func(enabled: bool) -> void:
		avatar.integer_scaling = enabled
		_update_exclusions())
	_target.add_child(_integer_check)


func _section_position() -> void:
	# Percentage of the window: 0 % is the centre, ±50 % the edges. Positive values
	# go right and up; vertical is inverted because Godot's Y axis grows downwards.
	var slider_x := _slider("Horizontal", -100.0, 100.0, 0.01, "%.2f %%",
			func() -> float: return avatar.window_position.x * 100.0,
			func(v: float) -> void: avatar.window_position.x = v / 100.0)
	var slider_y := _slider("Vertical", -100.0, 100.0, 0.01, "%.2f %%",
			# "0.0 -" so the centre is not shown as "-0.00 %".
			func() -> float: return 0.0 - avatar.window_position.y * 100.0,
			func(v: float) -> void: avatar.window_position.y = -v / 100.0)
	_center_button(slider_x, slider_y)


func _section_talk_jump() -> void:
	_checkbox("Enabled", "talk_jump_enabled")
	_property_slider("Height", 0.0, 500.0, 1.0, "%d px", "talk_jump_height")
	_property_slider("Duration", 0.05, 3.0, 0.01, "%.2f s", "talk_jump_duration")


func _section_blink() -> void:
	_checkbox("Enabled", "blink_enabled")
	_property_slider("Double blink", 0.0, 100.0, 1.0, "%d %%", "double_blink_chance", 100.0)
	_linked_sliders("Minimum interval", "Maximum interval", 0.5, 30.0, 30.0, 0.05, "%.2f s",
			"blink_interval_min", "blink_interval_max")
	_property_slider("Duration", 0.05, 3.0, 0.01, "%.2f s", "blink_duration")


## Integer scaling only works without smoothing and is incompatible with
## breathing: each checkbox is disabled when it cannot be used. The other
## option's actual effect is checked (not just whether it is ticked), so a file
## with both enabled can still be fixed.
func _update_exclusions() -> void:
	_integer_check.disabled = avatar.smoothing or avatar.breathing_effective()
	_breathing_check.disabled = avatar.integer_scaling_effective()
	for exclusion in _accessory_exclusions:
		var accessory: Accessory = exclusion.object.call()
		if accessory:
			exclusion.integer.disabled = accessory.smoothing or accessory.breathing_effective()
			exclusion.breathing.disabled = accessory.integer_scaling_effective()


func _open_image_dialog(state: String) -> void:
	_choosing_state = state
	_image_dialog.title = tr("Choose image: %s") % tr(STATE_NAMES[state])
	_open_file_dialog(_image_dialog)


func _on_image_chosen(path: String) -> void:
	if main.set_avatar_image(_choosing_state, path):
		if _choosing_state == "idle":
			_avatar_gallery.invalidate_thumbnail(main.current_avatar)
		refresh()
	else:
		_avatar_gallery.notify(tr("Could not load the image:") + "\n" + path)


# --- Idle motion (avatar and accessories) -------------------------------------
# Order is always: enabled, intensity, intervals (if any) and duration last.
# These work on the Motion returned by _object.

## Returns the breathing "Enabled" checkbox.
func _idle_sections(parent: VBoxContainer) -> CheckBox:
	_target = _subsection(parent, "Motion", "path")
	_section_path()
	_target = _subsection(parent, "Tilt", "tilt")
	_checkbox("Enabled", "tilt_enabled")
	_property_slider("Angle", 0.0, 90.0, 0.1, "%.1f°", "tilt_angle")
	_property_slider("Duration", 0.5, 30.0, 0.05, "%.2f s", "tilt_duration")
	_target = _subsection(parent, "Breathing", "breathing")
	var breathing := _checkbox("Enabled", "breathing_enabled")
	# Shown in %, stored as a proportion.
	_property_slider("Horizontal reduction", 0.0, 25.0, 0.5, "%.1f %%", "breathing_x", 100.0)
	_property_slider("Vertical reduction", 0.0, 25.0, 0.5, "%.1f %%", "breathing_y", 100.0)
	_property_slider("Duration", 0.5, 30.0, 0.05, "%.2f s", "breathing_duration")
	_target = _subsection(parent, "Jump", "jump")
	_checkbox("Enabled", "jump_enabled")
	_property_slider("Height", 0.0, 500.0, 1.0, "%d px", "jump_height")
	_linked_sliders("Minimum interval", "Maximum interval", 0.5, 30.0, 30.0, 0.05, "%.2f s",
			"jump_interval_min", "jump_interval_max")
	_property_slider("Duration", 0.05, 3.0, 0.01, "%.2f s", "jump_duration")
	return breathing


## Enabled, the Shape subsection, then amplitudes and duration.
func _section_path() -> void:
	var path_section := _target
	_checkbox("Enabled", "path_enabled")
	_target = _subsection(path_section, "Shape", "shape")
	_section_shape()
	_target = path_section
	_property_slider("Horizontal amplitude", 0.0, 500.0, 1.0, "%d px", "amplitude_x")
	_property_slider("Vertical amplitude", 0.0, 500.0, 1.0, "%d px", "amplitude_y")
	_property_slider("Duration", 0.5, 30.0, 0.05, "%.2f s", "cycle_duration")


## The parameters the figure selector changes.
func _section_shape() -> void:
	var object := _object
	_label("Figure")
	# The first item means the parameters match no figure.
	var selector := OptionButton.new()
	selector.add_item("Custom")
	selector.set_item_disabled(0, true)
	for figure in FIGURES:
		selector.add_item(figure.name)
	selector.item_selected.connect(func(i: int) -> void: _apply_figure(object.call(), FIGURES[i - 1]))
	_target.add_child(selector)
	_figure_selectors.append({"selector": selector, "object": object})

	_property_slider("Horizontal oscillations", 1.0, 4.0, 1.0, "%d", "oscillations_x")
	_property_slider("Vertical oscillations", 1.0, 4.0, 1.0, "%d", "oscillations_y")
	# Besides the shape, it decides the direction.
	_property_slider("Phase", 0.0, 360.0, 1.0, "%d°", "phase_y")
	var reverse := Button.new()
	reverse.text = "Reverse direction"
	reverse.pressed.connect(func() -> void:
		object.call().reverse_direction()
		refresh())
	_target.add_child(reverse)


func _apply_figure(motion: Motion, figure: Dictionary) -> void:
	motion.oscillations_x = figure.x
	motion.oscillations_y = figure.y
	motion.phase_y = figure.phases[0]
	match figure.amplitudes:
		"no_x":
			motion.amplitude_x = 0.0
			if motion.amplitude_y <= 0.0:
				motion.amplitude_y = FIGURE_AMPLITUDE
		"both":
			if motion.amplitude_x <= 0.0:
				motion.amplitude_x = motion.amplitude_y if motion.amplitude_y > 0.0 else FIGURE_AMPLITUDE
			if motion.amplitude_y <= 0.0:
				motion.amplitude_y = motion.amplitude_x
		"equal":
			var biggest := maxf(motion.amplitude_y, motion.amplitude_x)
			if biggest <= 0.0:
				biggest = FIGURE_AMPLITUDE
			motion.amplitude_y = biggest
			motion.amplitude_x = biggest
	refresh()


## Shows the figure the current parameters make (in either direction), or "Custom".
func _update_figures() -> void:
	for link in _figure_selectors:
		var motion: Motion = link.object.call()
		if motion:
			link.selector.select(_figure_index(motion))


func _figure_index(motion: Motion) -> int:
	var x := roundi(motion.oscillations_x)
	var y := roundi(motion.oscillations_y)
	var phase := posmod(roundi(motion.phase_y), 360)
	var amplitude_x := motion.amplitude_x
	var amplitude_y := motion.amplitude_y
	for i in FIGURES.size():
		var figure: Dictionary = FIGURES[i]
		if figure.x != x or figure.y != y or not phase in figure.phases:
			continue
		var amplitudes_match := false
		match figure.amplitudes:
			"no_x":
				amplitudes_match = amplitude_x <= 0.0 and amplitude_y > 0.0
			"both":
				amplitudes_match = amplitude_x > 0.0 and amplitude_y > 0.0
			"equal":
				amplitudes_match = amplitude_x > 0.0 and is_equal_approx(amplitude_x, amplitude_y)
		if amplitudes_match:
			return i + 1
	return 0


# --- Background ---------------------------------------------------------------

func _section_backgrounds() -> void:
	_background_gallery = Gallery.new()
	_background_gallery.minimum = 1
	_background_gallery.setup(main.backgrounds, {
		"current": func() -> String: return main.current_background,
		"select": main.select_background,
		"create": _new_background,
		"duplicate": main.duplicate_background,
		"rename": main.rename_background,
		"delete": main.delete_background,
		"import": main.import_background,
		"export": main.export_background,
		"open_folder": main.open_backgrounds_folder,
		"export_collection": main.export_collection.bind(main.backgrounds),
		"import_collection": main.import_collection.bind(main.backgrounds),
	}, "New", "Open backgrounds folder")
	_background_gallery.changed.connect(refresh)
	_target.add_child(_background_gallery)


func _new_background() -> void:
	_background_gallery.ask_name("New background",
			main.backgrounds.unique_name(tr(main.backgrounds.default_name)),
			func(background_name: String) -> void:
				main.create_background(background_name)
				# Show its settings, to pick a colour or an image.
				_sections["background_color"].folded = false
				_sections["background_image"].folded = false
				_show_section("background_settings"))


func _section_background_color() -> void:
	_background_color_picker = ColorPickerButton.new()
	_background_color_picker.edit_alpha = false
	_background_color_picker.custom_minimum_size = Vector2(80, 28)
	# Only on screen while adjusting; saved when the picker closes.
	_background_color_picker.color_changed.connect(main.change_background_color)
	_background_color_picker.popup_closed.connect(func() -> void:
		main.save_current_background()
		_background_gallery.invalidate_thumbnail(main.current_background)
		refresh())
	_target.add_child(_background_color_picker)


func _section_background_image() -> void:
	# Same style as the avatar's image buttons: thumbnail and name.
	_background_image_button = Button.new()
	_background_image_button.text = "Background"
	_background_image_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_background_image_button.add_theme_constant_override("icon_max_width", IMAGE_ICON_SIZE)
	_background_image_button.pressed.connect(func() -> void:
		_background_image_dialog.title = tr("Background image")
		_open_file_dialog(_background_image_dialog))
	_target.add_child(_background_image_button)

	_remove_background_image_button = Button.new()
	_remove_background_image_button.text = "Remove image"
	_remove_background_image_button.pressed.connect(func() -> void:
		main.remove_background_image()
		_background_gallery.invalidate_thumbnail(main.current_background)
		refresh())
	_target.add_child(_remove_background_image_button)

	_label("Fit")
	_fit_selector = OptionButton.new()
	for mode in BackgroundLibrary.FITS:
		_fit_selector.add_item(FIT_NAMES[mode])
	_fit_selector.item_selected.connect(
			func(i: int) -> void: main.change_background_fit(BackgroundLibrary.FITS[i]))
	_target.add_child(_fit_selector)


func _on_background_image_chosen(path: String) -> void:
	if main.change_background_image(path):
		_background_gallery.invalidate_thumbnail(main.current_background)
		refresh()
	else:
		_background_gallery.notify(tr("Could not load the image:") + "\n" + path)


# --- Accessories --------------------------------------------------------------

func _section_accessories() -> void:
	_accessory_gallery = Gallery.new()
	_accessory_gallery.setup(main.accessories, {
		"current": func() -> String: return main.current_accessory,
		# Clicking an accessory unfolds its settings (with the preview).
		"select": func(id: String) -> void:
			main.select_accessory(id)
			_show_section("accessory_settings"),
		# An accessory is its image: the first step is choosing it.
		"create": func() -> void:
			_new_accessory_dialog.title = tr("New accessory image")
			_open_file_dialog(_new_accessory_dialog),
		"duplicate": main.duplicate_accessory,
		"rename": main.rename_accessory,
		"delete": main.delete_accessory,
		"import": main.import_accessory,
		"export": main.export_accessory,
		"open_folder": main.open_accessories_folder,
		"export_collection": main.export_collection.bind(main.accessories),
		"import_collection": main.import_collection.bind(main.accessories),
		"delete_details": _accessory_delete_details,
	}, "New", "Open accessories folder")
	_accessory_gallery.changed.connect(refresh)
	_target.add_child(_accessory_gallery)


func _section_accessory_image() -> void:
	_accessory_image_button = Button.new()
	_accessory_image_button.text = "Change image"
	_accessory_image_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_accessory_image_button.add_theme_constant_override("icon_max_width", IMAGE_ICON_SIZE)
	_accessory_image_button.pressed.connect(func() -> void:
		_accessory_image_dialog.title = tr("Accessory image")
		_open_file_dialog(_accessory_image_dialog))
	_target.add_child(_accessory_image_button)


## Every placement setting of an accessory, in subsections inside "parent". Used
## for the library and for each placement: "object" returns the Accessory being
## edited (or null) and "prefix" keeps the section keys apart.
func _build_accessory_settings(parent: VBoxContainer, prefix: String, object: Callable) -> void:
	var previous_prefix := _prefix
	var previous_object := _object
	_prefix = prefix
	_object = object

	_target = _subsection(parent, "Image", "image")
	# The multiplier is adjusted to keep the size on screen.
	_selector("Base size", "base_size", Accessory.BASE_SIZES, BASE_SIZE_NAMES,
			func(accessory: Accessory, value: String) -> void: accessory.change_base_size(value))
	_property_slider("Multiplier", Accessory.MULTIPLIER_MIN, Accessory.MULTIPLIER_MAX, 0.01,
			"%.2f×", "multiplier")
	_property_slider("Rotation", -180.0, 180.0, 1.0, "%d°", "angle")
	_checkbox("Flip", "flip")
	# Same rules as the avatar (the breathing checkbox is created further down).
	var exclusion := {"object": object}
	exclusion.smoothing = _checkbox("Smoothing", "smoothing")
	exclusion.integer = _checkbox("Integer scaling", "integer_scaling")
	exclusion.smoothing.toggled.connect(func(_enabled: bool) -> void: _update_exclusions())
	exclusion.integer.toggled.connect(func(_enabled: bool) -> void: _update_exclusions())

	_target = _subsection(parent, "Position", "position")
	var anchor_selector := _selector("Anchor", "anchor", Accessory.ANCHORS, ANCHOR_NAMES)
	anchor_selector.item_selected.connect(func(_i: int) -> void: _update_follow_checkboxes())
	# As the avatar: % from the centre, positive right and up. Measured in avatar
	# sizes with the avatar anchor, and in window sizes with the window anchor.
	var slider_x := _slider("Horizontal", -100.0, 100.0, 0.01, "%.2f %%",
			func() -> float: return object.call().anchor_offset.x * 100.0,
			func(v: float) -> void:
				var accessory: Accessory = object.call()
				accessory.anchor_offset.x = v / 100.0)
	var slider_y := _slider("Vertical", -100.0, 100.0, 0.01, "%.2f %%",
			func() -> float: return 0.0 - object.call().anchor_offset.y * 100.0,
			func(v: float) -> void:
				var accessory: Accessory = object.call()
				accessory.anchor_offset.y = -v / 100.0)
	_center_button(slider_x, slider_y)
	_selector("Layer", "layer", Accessory.LAYERS, LAYER_NAMES)

	# How its own path is seen as a route around the avatar.
	_target = _subsection(parent, "Depth", "depth")
	_selector("Side switch", "depth_axis", Accessory.DEPTH_AXES, DEPTH_AXIS_NAMES)
	_checkbox("Invert side", "invert_depth")
	_checkbox("Flip on side switch", "flip_on_side_change")
	_property_slider("Perspective", 0.0, Accessory.PERSPECTIVE_MAX * 100.0, 1.0, "%d %%",
			"perspective", 100.0)

	_target = _subsection(parent, "States", "states")
	for state in Avatar.STATES:
		_checkbox(STATE_NAMES[state], "visible_" + state)

	# Only with the avatar anchor.
	_target = _subsection(parent, "Follow avatar", "follow")
	for option in [["Motion", "follow_path"], ["Tilt", "follow_tilt"],
			["Breathing", "follow_breathing"], ["Jump", "follow_jump"]]:
		_follow_checkboxes.append({"checkbox": _checkbox(option[0], option[1]), "object": object})

	var idle := _subsection(parent, "Idle", "idle")
	_object = func() -> Object:
		var accessory: Accessory = object.call()
		return accessory.motion if accessory else null
	exclusion.breathing = _idle_sections(idle)
	exclusion.breathing.toggled.connect(func(enabled: bool) -> void:
		var accessory: Accessory = object.call()
		if enabled and accessory.integer_scaling:
			accessory.integer_scaling = false
			exclusion.integer.set_pressed_no_signal(false)
		_update_exclusions())
	_accessory_exclusions.append(exclusion)

	_prefix = previous_prefix
	_object = previous_object


## Placed accessories of the avatar or background and, below, the settings of the
## selected one: the same as in the library.
func _section_placements(parent: VBoxContainer, target: String) -> void:
	var list := PlacementList.new()
	# The accessory gallery is created later: the thumbnail is fetched on use.
	list.setup(main, target, func(id: String) -> Texture2D: return _accessory_gallery.thumbnail(id))
	list.changed.connect(refresh)
	parent.add_child(list)
	_placement_lists[target] = list

	var settings := VBoxContainer.new()
	settings.add_theme_constant_override("separation", 6)
	parent.add_child(settings)
	_placement_settings[target] = settings
	_build_accessory_settings(settings, "%s_placement_" % target,
			func() -> Object: return list.selected_placement())


func _update_follow_checkboxes() -> void:
	for link in _follow_checkboxes:
		var accessory: Accessory = link.object.call()
		if accessory:
			link.checkbox.disabled = accessory.anchor != "avatar"


func _update_preview() -> void:
	main.show_preview(visible and not _sections["accessories"].folded \
			and not _sections["accessory_settings"].folded)


## Warning when deleting a library accessory that is placed somewhere.
func _accessory_delete_details(id: String) -> String:
	var uses := main.accessory_uses(id)
	if uses == 0:
		return ""
	return tr_n("It is placed %d time in avatars or backgrounds: it will be removed everywhere.",
			"It is placed %d times in avatars or backgrounds: it will be removed everywhere.",
			uses) % uses


func _on_new_accessory_chosen(path: String) -> void:
	if main.create_accessory(path) == "":
		_accessory_gallery.notify(tr("Could not load the image:") + "\n" + path)
		return
	# Show its settings, with the preview, to place it.
	_show_section("accessory_settings")
	refresh()


func _on_accessory_image_chosen(path: String) -> void:
	if main.change_accessory_image(path):
		_accessory_gallery.invalidate_thumbnail(main.current_accessory)
		refresh()
	else:
		_accessory_gallery.notify(tr("Could not load the image:") + "\n" + path)


# --- General ------------------------------------------------------------------

func _section_microphone() -> void:
	_label("Device")
	_device_selector = OptionButton.new()
	# Device names are not translated, and long ones are trimmed.
	_device_selector.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_device_selector.fit_to_longest_item = false
	_device_selector.clip_text = true
	_device_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_device_selector.item_selected.connect(func(i: int) -> void:
		microphone.change_device(_device_selector.get_item_metadata(i)))
	_target.add_child(_device_selector)

	var threshold := _slider("Threshold", Microphone.LEVEL_MIN_DB, 0.0, 1.0, "%d dB",
			func() -> float: return microphone.threshold_db,
			func(v: float) -> void: microphone.threshold_db = v)
	_join_level_bar(threshold)
	_slider("Hold time", 0.0, 0.5, 0.01, "%.2f s",
			func() -> float: return microphone.hold_time,
			func(v: float) -> void: microphone.hold_time = v)


## Readable names are shown; the real identifier (the one Godot needs) goes in
## the metadata.
func _fill_device_selector() -> void:
	var devices := AudioServer.get_input_device_list()
	var names := Microphone.readable_names(devices)
	_device_selector.clear()
	for i in devices.size():
		_device_selector.add_item(names[i])
		_device_selector.set_item_metadata(i, devices[i])
		if devices[i] == AudioServer.input_device:
			_device_selector.select(i)


## Puts the level bar behind the threshold slider, on the same scale, so the
## threshold can be placed right where the voice reaches.
func _join_level_bar(threshold: HSlider) -> void:
	threshold.custom_minimum_size.y = 20
	# Without the slider's own line and fill: the bar is the track.
	threshold.add_theme_stylebox_override("slider", StyleBoxEmpty.new())
	threshold.add_theme_stylebox_override("grabber_area", StyleBoxEmpty.new())
	threshold.add_theme_stylebox_override("grabber_area_highlight", StyleBoxEmpty.new())
	_level_bar = ProgressBar.new()
	_level_bar.min_value = Microphone.LEVEL_MIN_DB
	_level_bar.max_value = 0.0
	_level_bar.show_percentage = false
	var track := StyleBoxFlat.new()
	track.bg_color = LEVEL_TRACK_COLOR
	track.set_corner_radius_all(4)
	_level_bar.add_theme_stylebox_override("background", track)
	_level_fill = StyleBoxFlat.new()
	_level_fill.bg_color = LEVEL_COLOR
	_level_fill.set_corner_radius_all(4)
	_level_bar.add_theme_stylebox_override("fill", _level_fill)
	_level_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Drawn under the slider, which still gets the clicks.
	_level_bar.show_behind_parent = true
	_level_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The grabber's centre leaves half a grabber free at each end: the bar is
	# narrowed the same so both scales match.
	var margin := threshold.get_theme_icon("grabber").get_width() / 2.0
	_level_bar.offset_left = margin
	_level_bar.offset_right = -margin
	threshold.add_child(_level_bar)


func _section_window() -> void:
	_label("Resolution")
	# The first item stands for a size not in the list (a hand-resized window).
	_resolution_selector = OptionButton.new()
	_resolution_selector.add_item("Custom")
	for size_option in Main.RESOLUTIONS:
		_resolution_selector.add_item("%d × %d" % [size_option.x, size_option.y])
		_resolution_selector.set_item_metadata(_resolution_selector.item_count - 1, size_option)
	_resolution_selector.item_selected.connect(func(i: int) -> void:
		var size_option: Variant = _resolution_selector.get_item_metadata(i)
		if size_option is Vector2i:
			main.apply_resolution(size_option))
	_target.add_child(_resolution_selector)
	get_window().size_changed.connect(_sync_resolution)


func _sync_resolution() -> void:
	var current := get_window().size
	for i in _resolution_selector.item_count:
		var size_option: Variant = _resolution_selector.get_item_metadata(i)
		if size_option is Vector2i and size_option == current:
			_resolution_selector.set_item_text(0, "Custom")
			_resolution_selector.select(i)
			return
	_resolution_selector.set_item_text(0, tr("Custom (%d × %d)") % [current.x, current.y])
	_resolution_selector.select(0)


func _section_performance() -> void:
	_label("Frame rate limit")
	var fps_selector := OptionButton.new()
	for fps in Main.FPS_LIMITS:
		fps_selector.add_item(FPS_LIMIT_NAMES[fps])
		if fps == main.fps_limit:
			fps_selector.select(fps_selector.item_count - 1)
	fps_selector.item_selected.connect(func(i: int) -> void: main.apply_fps_limit(Main.FPS_LIMITS[i]))
	_target.add_child(fps_selector)

	var vsync_check := CheckBox.new()
	vsync_check.text = "Vertical sync (VSync)"
	vsync_check.button_pressed = main.vsync
	vsync_check.toggled.connect(main.apply_vsync)
	_target.add_child(vsync_check)


func _section_language() -> void:
	var selector := OptionButton.new()
	selector.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for code in Main.LANGUAGES:
		selector.add_item(LANGUAGE_NAMES[code])
		if code == main.language:
			selector.select(selector.item_count - 1)
	selector.item_selected.connect(func(i: int) -> void: main.apply_language(Main.LANGUAGES[i]))
	_target.add_child(selector)


# --- Dialogs ------------------------------------------------------------------

func _create_dialogs() -> void:
	_image_dialog = _file_dialog(_on_image_chosen)
	_background_image_dialog = _file_dialog(_on_background_image_chosen)
	_new_accessory_dialog = _file_dialog(_on_new_accessory_chosen)
	_accessory_image_dialog = _file_dialog(_on_accessory_image_chosen)


func _file_dialog(on_selected: Callable) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.file_selected.connect(on_selected)
	add_child(dialog)
	return dialog


## The filter is set when opening, so it follows the current language.
func _open_file_dialog(dialog: FileDialog) -> void:
	dialog.filters = PackedStringArray(["%s ; %s" % [Library.IMAGE_FILTER, tr("Images")]])
	dialog.popup_centered_ratio(0.7)


# --- Builders -----------------------------------------------------------------

## Top level section. Returns the container for its content.
func _category(title: String, key: String) -> VBoxContainer:
	var section := _foldable(_content, title, key)
	section.add_theme_font_size_override("font_size", 18)
	return section.get_child(0)


## Its key gets the current prefix.
func _subsection(parent: VBoxContainer, title: String, key: String) -> VBoxContainer:
	return _foldable(parent, title, _prefix + key).get_child(0)


## Without a saved state, it starts folded unless it is in DEFAULT_UNFOLDED.
func _foldable(parent: Container, title: String, key: String) -> FoldableContainer:
	var section := FoldableContainer.new()
	section.title = title
	var saved: Variant = main.folded.get(key)
	section.folded = saved if saved is bool else not key in DEFAULT_UNFOLDED
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	section.add_child(inner)
	parent.add_child(section)
	_sections[key] = section
	return section


func _label(text: String) -> void:
	var label := Label.new()
	label.text = text
	_target.add_child(label)


func _center_button(slider_x: HSlider, slider_y: HSlider) -> void:
	var button := Button.new()
	button.text = "Center"
	# Moving the sliders also updates the object and the labels.
	button.pressed.connect(func() -> void:
		slider_x.value = 0.0
		slider_y.value = 0.0)
	_target.add_child(button)


## Text property of the current object. "names" maps each option to its label.
## If on_chosen(object, value) is given it is called instead of setting the
## property, and the panel is refreshed.
func _selector(text: String, property: String, options: Array, names: Dictionary,
		on_chosen: Callable = Callable()) -> OptionButton:
	var object := _object
	_label(text)
	var selector := OptionButton.new()
	for option in options:
		selector.add_item(names[option])
	selector.item_selected.connect(func(i: int) -> void:
		if on_chosen.is_valid():
			on_chosen.call(object.call(), options[i])
			refresh()
		else:
			object.call().set(property, options[i]))
	_target.add_child(selector)
	_selectors.append({"selector": selector, "property": property, "options": options, "object": object})
	return selector


## Boolean property of the current object.
func _checkbox(text: String, property: String) -> CheckBox:
	var object := _object
	var checkbox := CheckBox.new()
	checkbox.text = text
	checkbox.toggled.connect(func(enabled: bool) -> void: object.call().set(property, enabled))
	_target.add_child(checkbox)
	_checkboxes.append({"checkbox": checkbox, "property": property, "object": object})
	return checkbox


## Minimum and maximum that cannot cross: if one passes the other, it drags it
## along. The stored values are compared (not the other slider's), because while
## refreshing the other slider may still show the previous object's value.
func _linked_sliders(min_name: String, max_name: String, minimum: float,
		min_top: float, max_top: float, step: float, format: String,
		min_property: String, max_property: String) -> void:
	var object := _object
	# A dictionary so the functions can use sliders created afterwards.
	var pair := {}
	var on_min := func(v: float) -> void:
		object.call().set(min_property, v)
		if object.call().get(max_property) < v:
			pair.max.value = v
	var on_max := func(v: float) -> void:
		object.call().set(max_property, v)
		if object.call().get(min_property) > v:
			pair.min.value = v
	pair.min = _slider(min_name, minimum, min_top, step, format,
			func() -> float: return object.call().get(min_property), on_min)
	pair.max = _slider(max_name, minimum, max_top, step, format,
			func() -> float: return object.call().get(max_property), on_max)


## Numeric property of the current object, shown multiplied by "factor" (100 to
## show a proportion in %).
func _property_slider(text: String, minimum: float, maximum: float, step: float,
		format: String, property: String, factor: float = 1.0) -> HSlider:
	var object := _object
	return _slider(text, minimum, maximum, step, format,
			func() -> float: return object.call().get(property) * factor,
			func(v: float) -> void: object.call().set(property, v / factor))


## A "Name: value" label with a slider below. getter reads the current value
## (to refresh) and setter applies it.
func _slider(text: String, minimum: float, maximum: float, step: float, format: String,
		getter: Callable, setter: Callable) -> HSlider:
	var label := Label.new()
	# Composed with tr(), so it is not translated again.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	# Without the mouse wheel: it scrolls the panel instead of changing values.
	slider.scrollable = false
	var link := {
		"slider": slider, "label": label, "name": text,
		"format": format, "getter": getter, "setter": setter, "object": _object,
	}
	_sliders.append(link)
	slider.value_changed.connect(_on_slider_changed.bind(link))
	_target.add_child(label)
	_target.add_child(slider)
	return slider


func _on_slider_changed(value: float, link: Dictionary) -> void:
	var label: Label = link.label
	label.text = "%s: %s" % [tr(link.name), link.format % value]
	# While refreshing, the object may not exist (no accessory selected).
	if link.object.call() != null:
		link.setter.call(value)
	_update_figures()
