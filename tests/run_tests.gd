extends SceneTree
## Dependency-free test runner.
##
## Usage: godot --headless --script tests/run_tests.gd
##
## Finds every res://tests/test_*.gd, runs each test_* method on a fresh instance,
## and quits with 0 (all passed), 1 (failures) or 2 (class cache is stale).
##
## This file must not name any project class_name directly: if the global class
## cache is stale it would fail to parse instead of reporting that clearly.

const TESTS_DIR := "res://tests"
const SOURCE_DIRS: Array[String] = ["res://core", "res://llm", "res://ui", "res://tools", "res://tests"]
const ErrorCapture := preload("res://tests/error_capture.gd")

var _passed: int = 0
var _failures: Array[String] = []


func _init() -> void:
	var missing: Array[String] = _classes_missing_from_cache()
	if not missing.is_empty():
		print("Class cache is stale, missing: %s" % ", ".join(missing))
		print("Run this once, then try again: godot --headless --import")
		quit(2)
		return

	var capture: ErrorCapture = ErrorCapture.new()
	OS.add_logger(capture)
	var started: int = Time.get_ticks_msec()
	for path: String in _test_files():
		_run_file(path, capture)
	OS.remove_logger(capture)

	print("")
	for failure: String in _failures:
		print("FAIL  %s" % failure)
	print("%d passed, %d failed (%d ms)" % [
		_passed, _failures.size(), Time.get_ticks_msec() - started,
	])
	quit(0 if _failures.is_empty() else 1)


func _run_file(path: String, capture: ErrorCapture) -> void:
	var file_name: String = path.get_file()
	capture.take()
	var script: GDScript = load(path) as GDScript
	if script == null or not script.can_instantiate():
		_failures.append("%s: could not load\n      %s" % [
			file_name, "\n      ".join(capture.take()),
		])
		return

	var names: Array[String] = _test_methods(script)
	if names.is_empty():
		_failures.append("%s: no test_* methods" % file_name)
	for method_name: String in names:
		_run_test(script, file_name, method_name, capture)
	print("%s: %d tests" % [file_name, names.size()])


func _run_test(
		script: GDScript, file_name: String, method_name: String, capture: ErrorCapture
) -> void:
	capture.take()
	var test: Variant = script.new()
	test.call(method_name)

	# A runtime error ends the test method without any assertion failing, so
	# errors reported to the logger count as failures too.
	var problems: Array[String] = []
	problems.assign(test.get("failures"))
	problems.append_array(capture.take())
	if problems.is_empty() and test.get("assertions") == 0:
		problems.append("ran no assertions")

	if problems.is_empty():
		_passed += 1
	else:
		_failures.append("%s::%s\n      %s" % [
			file_name, method_name, "\n      ".join(problems),
		])


func _test_files() -> Array[String]:
	var paths: Array[String] = []
	for file_name: String in DirAccess.get_files_at(TESTS_DIR):
		if file_name.begins_with("test_") and file_name.ends_with(".gd") \
				and file_name != "test_case.gd":
			paths.append("%s/%s" % [TESTS_DIR, file_name])
	paths.sort()
	return paths


func _test_methods(script: GDScript) -> Array[String]:
	var names: Array[String] = []
	for method: Dictionary in script.get_script_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)
	return names


func _classes_missing_from_cache() -> Array[String]:
	var known: Dictionary = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		known[entry["class"]] = true

	var missing: Array[String] = []
	for dir_path: String in SOURCE_DIRS:
		if not DirAccess.dir_exists_absolute(dir_path):
			continue
		for file_name: String in DirAccess.get_files_at(dir_path):
			if not file_name.ends_with(".gd"):
				continue
			var class_id: String = _declared_class("%s/%s" % [dir_path, file_name])
			if class_id != "" and not known.has(class_id):
				missing.append(class_id)
	return missing


func _declared_class(path: String) -> String:
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("class_name "):
			return line.trim_prefix("class_name ").strip_edges()
	return ""
