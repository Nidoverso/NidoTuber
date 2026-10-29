class_name Settings
## Helpers to save an object's properties as JSON and load them back safely.


## Reads the given properties in a JSON-friendly format.
static func read(object: Object, properties: Array) -> Dictionary:
	var data := {}
	for property in properties:
		data[property] = to_json(object.get(property))
	return data


## Current values of the given properties, to be used as defaults.
static func capture(object: Object, properties: Array) -> Dictionary:
	var values := {}
	for property in properties:
		values[property] = object.get(property)
	return values


## Applies loaded data. Missing values, wrong types and values not listed in
## "options" fall back to the defaults.
static func apply(object: Object, data: Dictionary, defaults: Dictionary,
		options: Dictionary = {}) -> void:
	for property in defaults:
		var value: Variant = convert_to(data.get(property), defaults[property])
		if options.has(property) and not value in options[property]:
			value = defaults[property]
		object.set(property, value)


static func to_json_all(values: Dictionary) -> Dictionary:
	var data := {}
	for property in values:
		data[property] = to_json(values[property])
	return data


## Vector2 is stored as [x, y].
static func to_json(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x, value.y]
	return value


## Converts a value to the type of the default value, or returns the default.
static func convert_to(value: Variant, default_value: Variant) -> Variant:
	match typeof(default_value):
		TYPE_FLOAT:
			if (value is float or value is int) and is_finite(float(value)):
				return float(value)
		TYPE_BOOL:
			if value is bool:
				return value
		TYPE_STRING:
			if value is String:
				return value
		TYPE_VECTOR2:
			if value is Array and value.size() == 2 \
					and (value[0] is float or value[0] is int) \
					and (value[1] is float or value[1] is int) \
					and is_finite(float(value[0])) and is_finite(float(value[1])):
				return Vector2(value[0], value[1])
	return default_value
