class_name OllamaApi
extends RefCounted
## Ollama's native chat API (/api/chat), which OpenAiClient uses when the server is
## Ollama. Unlike the OpenAI-style /v1 API, it takes the context window (num_ctx) with
## each request, so the app sets the window itself and the server needs no
## OLLAMA_CONTEXT_LENGTH. Ollama reloads the model whenever num_ctx changes, so every
## call sends the same window: Settings -> Context window.
## Kept as plain functions on dictionaries so they can be tested without a server.

## Sent as `think` only to turn thinking off: asking a model that cannot think to think
## is an error (HTTP 400 "... does not support thinking"), so "on" means the model's own
## default.
const NO_THINKING_ERROR := "does not support thinking"


## The body for POST /api/chat.
static func chat_body(config: LlmConfig, model: String, messages: Array, stream: bool,
		options: Dictionary, send_think: bool = true) -> Dictionary:
	var body: Dictionary = {
		"model": model,
		"messages": messages,
		"stream": stream,
		"options": {
			"num_ctx": config.context_tokens,
			"num_predict": int(options.get("max_tokens", config.max_tokens)),
			"temperature": float(options.get("temperature", config.temperature)),
		},
	}
	if config.keep_alive != "":
		body["keep_alive"] = config.keep_alive
	if not config.thinking and send_think:
		body["think"] = false
	if options.has("response_format"):
		body["format"] = "json"
	return body


## One reply object, streamed or whole: {content, thinking, done, finish_reason, usage,
## error}. Missing parts are "" / {} / false.
static func read_reply(data: Variant) -> Dictionary:
	var reply: Dictionary = {"content": "", "thinking": "", "done": false, "finish_reason": "",
			"usage": {}, "error": ""}
	if not data is Dictionary:
		reply["error"] = "unexpected reply: %s" % str(data).left(200)
		return reply
	if data.has("error"):
		reply["error"] = str(data["error"])
		return reply
	var message: Variant = data.get("message")
	if message is Dictionary:
		reply["content"] = str(message.get("content", "")) if message.get("content") is String else ""
		reply["thinking"] = str(message.get("thinking", "")) if message.get("thinking") is String else ""
	if data.get("done") == true:
		reply["done"] = true
		reply["finish_reason"] = str(data.get("done_reason", ""))
		if data.has("prompt_eval_count") or data.has("eval_count"):
			reply["usage"] = {
				"prompt_tokens": int(data.get("prompt_eval_count", 0)),
				"completion_tokens": int(data.get("eval_count", 0)),
			}
	return reply


## Model names from GET /api/tags.
static func model_names(data: Variant) -> PackedStringArray:
	var names: PackedStringArray = []
	if data is Dictionary and data.get("models") is Array:
		for entry: Variant in data["models"]:
			if entry is Dictionary and entry.get("name") is String:
				names.append(entry["name"])
	return names


## The JSON value of `text`, or null, without logging an error for text that isn't JSON
## (an HTML error page, a stray line).
static func parse(text: String) -> Variant:
	var json: JSON = JSON.new()
	return json.data if json.parse(text) == OK else null


## True when GET /api/version answered like Ollama.
static func is_version_reply(body: String) -> bool:
	var data: Variant = parse(body)
	return data is Dictionary and data.get("version") is String
