class_name SpreadLibrary
extends RefCounted
## Spreads added by the user: every .json file in a spreads/ folder next to the
## executable (the project's spreads/ folder when running from source), each in the same
## format as data/spreads.json ({spread_id: {name, positions, dignity_adjacency, ...}}).
## Added alongside the built-in spreads, never replacing them. Rescan whenever the folder
## may have changed; see docs/custom_spreads.md for the format.

## Git-ignored apart from its .gdignore, which stops Godot importing or exporting it.
const PROJECT_FOLDER := "res://spreads"
const OPTIONAL_TEXT: PackedStringArray = ["name", "reading_words", "source", "from"]
## The most positions a spread may have. Every card's correspondences and dignities go
## into the prompt, and the reading covers each position: past a dozen the prompt and the
## reply outgrow what a local model reads well (and its context window).
const MAX_POSITIONS: int = 12
## x and y run from 0 to 1 across the table; a spread may reach this far past it on any
## side (the table then shows the whole spread smaller, SpreadLayout.fit_scale).
const REACH: float = 1.0


static func default_folder() -> String:
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join("spreads")
	return ProjectSettings.globalize_path(PROJECT_FOLDER)


## Every spread found in the folder's .json files, valid or not, in file then listed
## order: {id, name, file, data, errors}. Spreads with errors are not usable.
static func scan(folder: String, builtin_ids: PackedStringArray) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var path: String = ProjectSettings.globalize_path(folder)
	if not DirAccess.dir_exists_absolute(path):
		return found
	var seen: Dictionary = {}
	var files: PackedStringArray = DirAccess.get_files_at(path)
	files.sort()
	for file: String in files:
		if file.get_extension().to_lower() != "json":
			continue
		var json: JSON = JSON.new()
		if json.parse(FileAccess.get_file_as_string(path.path_join(file))) != OK:
			found.append(_entry(file.get_basename(), file, {},
					["not valid JSON: %s (line %d)" % [json.get_error_message(), json.get_error_line()]]))
			continue
		if not json.data is Dictionary:
			found.append(_entry(file.get_basename(), file, {}, ["not a JSON object of spreads"]))
			continue
		for key: Variant in json.data:
			var spread_id: String = str(key)
			var data: Variant = json.data[key]
			var errors: PackedStringArray = validate(data)
			if builtin_ids.has(spread_id):
				errors.insert(0, "the id \"%s\" belongs to a built-in spread; give it another" % spread_id)
			elif seen.has(spread_id):
				errors.insert(0, "the id \"%s\" is already used in %s" % [spread_id, seen[spread_id]])
			seen[spread_id] = file
			found.append(_entry(spread_id, file, data if data is Dictionary else {}, errors))
	return found


## What is wrong with a spread definition; empty when it is usable.
static func validate(data: Variant) -> PackedStringArray:
	var errors: PackedStringArray = []
	if not data is Dictionary:
		return PackedStringArray(["a spread must be a JSON object"])
	for field: String in OPTIONAL_TEXT:
		if data.has(field) and not data[field] is String:
			errors.append("\"%s\" must be text" % field)
	var positions: Variant = data.get("positions")
	if not positions is Array or (positions as Array).is_empty():
		errors.append("\"positions\" must be a list of at least one position")
		positions = []
	elif (positions as Array).size() > MAX_POSITIONS:
		errors.append("at most %d positions (this has %d): more cards than that overload the reader" % [
				MAX_POSITIONS, (positions as Array).size()])
	var ids: PackedStringArray = []
	for i: int in (positions as Array).size():
		var entry: Variant = positions[i]
		var where: String = "position %d" % (i + 1)
		if not entry is Dictionary:
			errors.append("%s must be a JSON object" % where)
			continue
		var position_id: String = str(entry.get("id", "")) if entry.get("id") is String else ""
		if position_id == "":
			errors.append("%s needs an \"id\"" % where)
		elif ids.has(position_id):
			errors.append("%s: the id \"%s\" is used twice" % [where, position_id])
		else:
			where = "position %d (%s)" % [i + 1, position_id]
		ids.append(position_id)
		if not entry.get("meaning") is String or str(entry.get("meaning")).strip_edges() == "":
			errors.append("%s needs a \"meaning\"" % where)
		if entry.has("name") and not entry["name"] is String:
			errors.append("%s: \"name\" must be text" % where)
		for axis: String in ["x", "y"]:
			var value: Variant = entry.get(axis)
			if not (value is float or value is int) or float(value) < -REACH or float(value) > 1.0 + REACH:
				errors.append("%s: \"%s\" must be a number from %d to %d (0 to 1 is the table)" % [
						where, axis, -REACH, 1.0 + REACH])
		if entry.has("rotation") and not (entry["rotation"] is float or entry["rotation"] is int):
			errors.append("%s: \"rotation\" must be a number of degrees" % where)
	for entry: Variant in positions:
		if entry is Dictionary and entry.has("over") and not ids.has(str(entry["over"])):
			errors.append("position \"%s\" lies over \"%s\", which is not a position" % [
					entry.get("id", "?"), entry["over"]])
	var adjacency: Variant = data.get("dignity_adjacency", [])
	if not adjacency is Array:
		errors.append("\"dignity_adjacency\" must be a list of pairs")
		adjacency = []
	for pair: Variant in adjacency:
		if not pair is Array or (pair as Array).size() != 2 or not ids.has(str(pair[0])) \
				or not ids.has(str(pair[1])) or str(pair[0]) == str(pair[1]):
			errors.append("dignity pair %s must name two different positions" % JSON.stringify(pair))
	if data.has("card_height"):
		var height: Variant = data["card_height"]
		if not (height is float or height is int) or float(height) <= 0.0 or float(height) > 1.0:
			errors.append("\"card_height\" must be a share of the table's height, above 0 and up to 1")
	if data.has("columns"):
		var columns: Variant = data["columns"]
		if not (columns is float or columns is int) or float(columns) < 1.0:
			errors.append("\"columns\" must be a number of at least 1")
	if data.has("compact_labels") and not data["compact_labels"] is bool:
		errors.append("\"compact_labels\" must be true or false")
	return errors


static func _entry(spread_id: String, file: String, data: Dictionary, errors: PackedStringArray) -> Dictionary:
	return {"id": spread_id, "name": str(data.get("name", spread_id)), "file": file,
			"data": data, "errors": errors}
