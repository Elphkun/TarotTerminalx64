extends "res://tests/test_case.gd"
## Spreads added from a spreads/ folder: found, checked, added after the built-in ones,
## and dropped again when their file goes.

const FOLDER := "user://test_spreads_folder"


func _write(file: String, data: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var handle: FileAccess = FileAccess.open(FOLDER.path_join(file), FileAccess.WRITE)
	handle.store_string(data if data is String else JSON.stringify(data))
	handle.close()


func _clear() -> void:
	var path: String = ProjectSettings.globalize_path(FOLDER)
	if DirAccess.dir_exists_absolute(path):
		for file: String in DirAccess.get_files_at(path):
			DirAccess.remove_absolute(path.path_join(file))
		DirAccess.remove_absolute(path)


func _two_cards() -> Dictionary:
	return {"name": "Two cards", "positions": [
		{"id": "a", "meaning": "One", "x": 0.3, "y": 0.5},
		{"id": "b", "name": "the other", "meaning": "Two", "x": 0.7, "y": 0.5}],
		"dignity_adjacency": [["a", "b"]]}


func test_built_in_spreads_pass_the_same_checks() -> void:
	for spread_id: String in db().spreads:
		assert_eq(SpreadLibrary.validate(db().spreads[spread_id]), PackedStringArray(), spread_id)


func test_added_spreads_follow_the_built_in_ones() -> void:
	_clear()
	_write("mine.json", {"two": _two_cards()})
	var fresh: CardDb = CardDb.load_from(CardDb.DEFAULT_DIR)
	var found: Array[Dictionary] = SpreadLibrary.scan(FOLDER, fresh.builtin_spread_ids)
	assert_eq(found.size(), 1)
	assert_eq(found[0]["name"], "Two cards")
	assert_eq(fresh.set_added_spreads(found), 1)
	var ids: PackedStringArray = PackedStringArray(fresh.spreads.keys())
	assert_eq(ids.slice(0, fresh.builtin_spread_ids.size()), fresh.builtin_spread_ids, "built-ins first")
	assert_eq(ids[ids.size() - 1], "two")
	var spread: Spread = Spread.from_db(fresh, "two")
	assert_eq(spread.neighbours("a"), PackedStringArray(["b"]))
	# The file goes: so does the spread.
	_clear()
	assert_eq(fresh.set_added_spreads(SpreadLibrary.scan(FOLDER, fresh.builtin_spread_ids)), 0)
	assert_false(fresh.spreads.has("two"))
	assert_eq(PackedStringArray(fresh.spreads.keys()), fresh.builtin_spread_ids)


func test_problems_are_reported_and_the_spread_left_out() -> void:
	_clear()
	var bad: Dictionary = _two_cards()
	bad["positions"][1]["x"] = 9
	bad["positions"][0].erase("meaning")
	bad["dignity_adjacency"] = [["a", "nowhere"]]
	_write("a_bad.json", {"bad": bad, "celtic_cross": _two_cards(), "fine": _two_cards()})
	_write("b_more.json", {"fine": _two_cards()})
	_write("c_broken.json", "{ not json")
	var fresh: CardDb = CardDb.load_from(CardDb.DEFAULT_DIR)
	var found: Array[Dictionary] = SpreadLibrary.scan(FOLDER, fresh.builtin_spread_ids)
	var by_file: Dictionary = {}
	for entry: Dictionary in found:
		by_file["%s/%s" % [entry["file"], entry["id"]]] = "; ".join(entry["errors"])
	assert_true(by_file["a_bad.json/bad"].contains("\"x\" must be a number from -1 to 2"), by_file["a_bad.json/bad"])
	assert_true(by_file["a_bad.json/bad"].contains("needs a \"meaning\""), by_file["a_bad.json/bad"])
	assert_true(by_file["a_bad.json/bad"].contains("must name two different positions"), by_file["a_bad.json/bad"])
	assert_true(by_file["a_bad.json/celtic_cross"].contains("built-in"), by_file["a_bad.json/celtic_cross"])
	assert_eq(by_file["a_bad.json/fine"], "")
	assert_true(by_file["b_more.json/fine"].contains("already used in a_bad.json"), by_file["b_more.json/fine"])
	assert_true(by_file["c_broken.json/c_broken"].contains("not valid JSON"), by_file["c_broken.json/c_broken"])
	assert_eq(fresh.set_added_spreads(found), 1, "only the good one is added")
	assert_eq(fresh.spread("celtic_cross")["name"], "Celtic Cross (Waite)", "a built-in is never replaced")
	_clear()


func test_a_missing_folder_adds_nothing() -> void:
	assert_eq(SpreadLibrary.scan("user://no_such_spreads_folder", db().builtin_spread_ids).size(), 0)


## The example in docs/custom_spreads.md works as printed.
func test_the_documented_example_is_valid() -> void:
	var text: String = FileAccess.get_file_as_string("res://docs/custom_spreads.md")
	var start: int = text.find("```json")
	var example: String = text.substr(start + 7, text.find("```", start + 7) - start - 7)
	var data: Variant = JSON.parse_string(example)
	assert_true(data is Dictionary, "the example parses")
	for spread_id: String in data:
		assert_eq(SpreadLibrary.validate(data[spread_id]), PackedStringArray(), spread_id)
