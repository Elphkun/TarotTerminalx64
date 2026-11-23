class_name LlmConfig
extends RefCounted
## Where and how to reach the model. Saved as user://llm.json so the backend
## can be swapped (local server, Claude, OpenAI) without code changes.

const DEFAULT_PATH := "user://llm.json"

## Base URL of an OpenAI-compatible API, up to and including /v1.
var endpoint: String = "http://localhost:11434/v1"
## Model name as the server knows it. Empty means the first one the server lists.
var model: String = ""
var api_key: String = ""
var temperature: float = 0.8
## Thinking models spend part of this on hidden reasoning before the visible answer.
var max_tokens: int = 8192
## The context window: prompt, thinking and reply must all fit in it. With Ollama's
## native API the app asks for this window on every call (see OllamaApi). Over the
## OpenAI-style API it cannot be set, so the server must match (OLLAMA_CONTEXT_LENGTH)
## and the window the server reports wins. Also used to warn before a reading that
## will not fit.
var context_tokens: int = 16384
var critique: bool = false
## Give up when the server sends nothing for this long. Loading a model can be slow.
var timeout_s: float = 300.0
## Which API to speak: "auto" (Ollama's native API when the server is Ollama, else the
## OpenAI-style one), "ollama" or "openai".
var backend: String = "auto"
## Let a thinking model reason before it writes. Off is faster.
var thinking: bool = true
## Ollama only: how long the server keeps the model loaded after a call ("30m", "-1" for
## ever, "" for the server's default).
var keep_alive: String = "30m"

const BACKENDS: PackedStringArray = ["auto", "ollama", "openai"]
const FIELDS: PackedStringArray = [
	"endpoint", "model", "api_key", "temperature", "max_tokens", "context_tokens", "critique",
	"timeout_s", "backend", "thinking", "keep_alive",
]


## Loads `path` if it exists; missing fields keep their defaults.
static func load_from(path: String = DEFAULT_PATH) -> LlmConfig:
	var config: LlmConfig = LlmConfig.new()
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			config.apply(data)
		else:
			push_warning("Ignoring unreadable %s" % path)
	return config


## Overrides fields from a dictionary (a settings file or command-line options).
func apply(values: Dictionary) -> void:
	for field: String in FIELDS:
		if not values.has(field):
			continue
		var value: Variant = values[field]
		match typeof(get(field)):
			TYPE_FLOAT:
				set(field, float(value))
			TYPE_INT:
				set(field, int(value))
			TYPE_BOOL:
				set(field, value if value is bool else str(value).to_lower() in ["1", "true", "yes"])
			_:
				set(field, str(value))


func to_dict() -> Dictionary:
	var data: Dictionary = {}
	for field: String in FIELDS:
		data[field] = get(field)
	return data


func save(path: String = DEFAULT_PATH) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	return OK
