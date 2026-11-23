extends Logger
## Collects engine and script errors so the runner can fail the test that caused them.

var _errors: Array[String] = []


func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtrace: Array[ScriptBacktrace]
) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var message: String = rationale if rationale != "" else code
	_errors.append("%s (%s:%d in %s)" % [message, file, line, function])


## Returns everything captured since the last call and clears it.
func take() -> Array[String]:
	var taken: Array[String] = _errors
	_errors = []
	return taken


## Everything captured so far, without clearing it.
func take_all() -> Array[String]:
	return _errors.duplicate()
