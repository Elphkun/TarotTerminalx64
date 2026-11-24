class_name OpenAiClient
extends LlmClient
## Chat completions over any OpenAI-compatible API (LM Studio, llama.cpp server, OpenAI
## itself), or over Ollama's native API when the server is Ollama (see OllamaApi), which
## lets the app set the context window. Uses HTTPClient directly so a streamed answer
## can be read chunk by chunk as it arrives.

const CONNECT_TIMEOUT_S: float = 20.0

var config: LlmConfig

## Resolved once when config.model is empty.
var _model: String = ""
## cancel() bumps this; a request started under an older ticket stops at its next wait.
var _cancel_ticket: int = 0
## host name -> IPv4 address, so a slow lookup is paid once per run.
var _resolved: Dictionary = {}
## "ollama" or "openai" once known (config.backend, or asked of the server).
var _backend: String = ""


func _init(llm_config: LlmConfig = null) -> void:
	config = llm_config if llm_config != null else LlmConfig.new()


func complete(messages: Array, stream: bool = false, options: Dictionary = {}) -> String:
	last_error = ""
	var model: String = options.get("model", "")
	if model == "":
		model = await resolve_model()
		if model == "":
			return ""
	last_model = model
	if await resolve_backend() == "ollama":
		return await _complete_ollama(model, messages, stream, options)
	var body: Dictionary = {
		"model": model,
		"messages": messages,
		"temperature": options.get("temperature", config.temperature),
		"max_tokens": options.get("max_tokens", config.max_tokens),
		"stream": stream,
	}
	last_usage = {}
	last_finish_reason = ""
	if stream:
		body["stream_options"] = {"include_usage": true}
	if options.has("response_format"):
		body["response_format"] = options["response_format"]
	if not options.get("thinking", config.thinking):
		body["reasoning_effort"] = "none"

	var response: Dictionary = await _request(
			HTTPClient.METHOD_POST, "/chat/completions", JSON.stringify(body), stream)
	if body.has("reasoning_effort") and refuses_reasoning(last_error):
		# A server that doesn't know the field: the call is made once more without it.
		last_error = ""
		body.erase("reasoning_effort")
		response = await _request(
				HTTPClient.METHOD_POST, "/chat/completions", JSON.stringify(body), stream)
	if last_error != "":
		return ""
	if stream:
		return response["text"]
	var data: Variant = JSON.parse_string(response["body"])
	if not data is Dictionary or data.get("choices", []).is_empty():
		last_error = "Unexpected response: %s" % response["body"].left(300)
		return ""
	if data.get("usage") is Dictionary:
		last_usage = data["usage"]
	var choice: Dictionary = data["choices"][0]
	if choice.get("finish_reason") is String:
		last_finish_reason = choice["finish_reason"]
	var message: Dictionary = choice.get("message", {})
	return str(message.get("content", ""))


## True when a server turned a call down for its reasoning_effort (HTTP 400 or 422).
static func refuses_reasoning(error: String) -> bool:
	return (error.begins_with("HTTP 400") or error.begins_with("HTTP 422")) \
			and error.to_lower().contains("reasoning")


## Ollama's native /api/chat. A model that cannot think refuses even think=false on some
## servers; then the call is made once more without it.
func _complete_ollama(model: String, messages: Array, stream: bool, options: Dictionary) -> String:
	var response: Dictionary = {}
	for send_think: bool in [true, false]:
		last_error = ""
		last_usage = {}
		last_finish_reason = ""
		var body: Dictionary = OllamaApi.chat_body(config, model, messages, stream, options, send_think)
		response = await _request(HTTPClient.METHOD_POST, "/api/chat", JSON.stringify(body),
				stream, true, true)
		if not (send_think and body.has("think") and last_error.contains(OllamaApi.NO_THINKING_ERROR)):
			break
	if last_error != "":
		return ""
	if stream:
		return response["text"]
	var reply: Dictionary = OllamaApi.read_reply(OllamaApi.parse(response["body"]))
	if reply["error"] != "":
		last_error = "Server error: %s" % reply["error"]
		return ""
	last_usage = reply["usage"]
	last_finish_reason = reply["finish_reason"]
	return reply["content"]


## "ollama" when the server speaks Ollama's native API (config.backend "auto" asks
## GET /api/version once), else "openai". A server that cannot be reached is not
## remembered either way, so it is asked again next time.
func resolve_backend() -> String:
	if config.backend in ["ollama", "openai"]:
		return config.backend
	if _backend != "":
		return _backend
	var saved_error: String = last_error
	var response: Dictionary = await _request(HTTPClient.METHOD_GET, "/api/version", "", false, true)
	var found: String = "openai"
	if last_error == "" and OllamaApi.is_version_reply(response["body"]):
		found = "ollama"
		_backend = found
	elif last_error.begins_with("HTTP "):
		_backend = found  # the server answered, and it is not Ollama
	last_error = saved_error
	return found


func backend_name() -> String:
	return "Ollama" if await resolve_backend() == "ollama" else "OpenAI-compatible"


func sets_context_window() -> bool:
	return config.backend == "ollama" or _backend == "ollama"


## The configured model, or the first one the server lists if none is set.
func resolve_model() -> String:
	if config.model != "":
		return config.model
	if _model != "":
		return _model
	var models: PackedStringArray = await list_chat_models()
	if models.is_empty():
		if last_error == "":
			last_error = "No model set and the server lists none"
		return ""
	_model = models[0]
	return _model


func list_chat_models() -> PackedStringArray:
	last_error = ""
	var models: PackedStringArray = []
	for model_name: String in await list_models():
		if not model_name.contains("embed"):  # embedding models cannot chat
			models.append(model_name)
	return models


func settings_changed() -> void:
	_model = ""
	_backend = ""
	_resolved.clear()


func list_models() -> PackedStringArray:
	var names: PackedStringArray = []
	if await resolve_backend() == "ollama":
		var tags: Dictionary = await _request(HTTPClient.METHOD_GET, "/api/tags", "", false, true)
		return OllamaApi.model_names(OllamaApi.parse(tags["body"])) if last_error == "" else names
	var response: Dictionary = await _request(HTTPClient.METHOD_GET, "/models", "", false)
	if last_error != "":
		return names
	var data: Variant = JSON.parse_string(response["body"])
	if data is Dictionary:
		for entry: Variant in data.get("data", []):
			if entry is Dictionary and entry.has("id"):
				names.append(str(entry["id"]))
	return names


## Ollama only: asks /api/ps, at the server root beside /v1, which context window the
## model is loaded with. The OpenAI-style API cannot change it (Ollama ignores
## num_ctx there), so this is how the app finds out what the server really uses.
## -1 when the server is not Ollama or the model is not loaded right now.
func loaded_context(model_name: String = "") -> int:
	# Ollama's native API loads the model at the window each call asks for.
	if await resolve_backend() == "ollama":
		return config.context_tokens
	var saved_error: String = last_error
	if model_name == "":
		model_name = config.model if config.model != "" else _model
	var response: Dictionary = await _request(HTTPClient.METHOD_GET, "/api/ps", "", false, true)
	var found: int = -1
	var data: Variant = JSON.parse_string(response["body"]) if last_error == "" else null
	if data is Dictionary and data.get("models") is Array:
		for entry: Variant in data["models"]:
			if not entry is Dictionary or not entry.has("context_length"):
				continue
			if model_name == "" or entry.get("name") == model_name or entry.get("model") == model_name:
				found = int(entry["context_length"])
				break
	last_error = saved_error
	return found


## Returns { body: String } or, when streaming, { text: String } with `token` emitted
## along the way. Sets last_error on failure. With `from_root`, `path` is taken from the
## server root rather than from the endpoint's path (for Ollama's own /api routes).
func _request(method: int, path: String, body: String, stream: bool,
		from_root: bool = false, ndjson: bool = false) -> Dictionary:
	var result: Dictionary = {"body": "", "text": ""}
	var url: Dictionary = _parse_endpoint(config.endpoint)
	if url.is_empty():
		last_error = "Bad endpoint URL '%s'" % config.endpoint
		return result
	if from_root:
		url["path"] = ""

	# On Windows a refused connection stays in CONNECTING rather than failing, so
	# connecting gets its own short limit instead of the (long) read timeout.
	var deadline: Dictionary = {
		"at": _now() + minf(config.timeout_s, CONNECT_TIMEOUT_S), "ticket": _cancel_ticket,
	}
	# Plain http goes to an IPv4 address when the host has one. Godot's own lookup asks
	# for any address and may pick IPv6, where a server listening on IPv4 only (Ollama's
	# usual setup) leaves the connection hanging. https keeps the name for TLS.
	var target: String = url["host"]
	if not url["tls"]:
		target = await _resolve_ipv4(url["host"], deadline)
		if last_error != "":
			return result

	var http: HTTPClient = HTTPClient.new()
	var tls: TLSOptions = TLSOptions.client() if url["tls"] else null
	var err: Error = http.connect_to_host(target, url["port"], tls)
	if err != OK:
		last_error = "Could not start connecting to %s:%d (%s)" % [
			url["host"], url["port"], error_string(err)]
		return result

	while http.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
		http.poll()
		if not await _wait(deadline):
			last_error = _stopped(deadline, "Timed out connecting to %s:%d" % [url["host"], url["port"]])
			return result
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		last_error = "Could not connect to %s:%d (%s)" % [
			url["host"], url["port"], _status_name(http.get_status())]
		return result

	var accept: String = "application/json"
	if stream:
		accept = "application/x-ndjson" if ndjson else "text/event-stream"
	var headers: PackedStringArray = ["Accept: %s" % accept]
	if body != "":
		headers.append("Content-Type: application/json")
	if config.api_key != "":
		headers.append("Authorization: Bearer %s" % config.api_key)
	if target != url["host"]:
		headers.append("Host: %s:%d" % [url["host"], url["port"]])
	deadline["at"] = _now() + config.timeout_s
	err = http.request(method, url["path"] + path, headers, body)
	if err != OK:
		last_error = "Request failed to send (%s)" % error_string(err)
		return result

	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		if not await _wait(deadline):
			last_error = _stopped(deadline, "Timed out waiting for the server to answer")
			return result
	if not http.has_response():
		last_error = "No response (%s)" % _status_name(http.get_status())
		return result

	var code: int = http.get_response_code()
	# SseParser or NdjsonParser: the same feed() / finish() / done.
	var parser: Variant = SseParser.new()
	if ndjson:
		parser = NdjsonParser.new()
	var raw: PackedByteArray = PackedByteArray()
	var text: PackedStringArray = []
	var streaming: bool = stream and code == 200
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk: PackedByteArray = http.read_response_body_chunk()
		if chunk.is_empty():
			if not await _wait(deadline):
				last_error = _stopped(deadline, "Timed out: the server stopped sending")
				http.close()
				return result
			continue
		deadline["at"] = _now() + config.timeout_s
		if streaming:
			_handle_stream(parser, parser.feed(chunk), text, ndjson)
			if parser.done:
				break
		else:
			raw.append_array(chunk)
	if streaming:
		_handle_stream(parser, parser.finish(), text, ndjson)
	http.close()

	if code < 200 or code >= 300:
		last_error = "HTTP %d: %s" % [code, raw.get_string_from_utf8().left(500)]
		return result
	if last_error != "":
		return result
	result["body"] = raw.get_string_from_utf8()
	result["text"] = "".join(text)
	return result


func _handle_stream(parser: Variant, items: Array[String], text: PackedStringArray, ndjson: bool) -> void:
	if ndjson:
		_handle_ollama_lines(parser, items, text)
	else:
		_handle_events(items, text)


func _handle_ollama_lines(parser: Variant, lines: Array[String], text: PackedStringArray) -> void:
	for line: String in lines:
		var reply: Dictionary = OllamaApi.read_reply(OllamaApi.parse(line))
		if reply["error"] != "":
			last_error = "Server error: %s" % reply["error"]
			continue
		if reply["thinking"] != "":
			reasoning.emit(reply["thinking"])
		if reply["content"] != "":
			text.append(reply["content"])
			token.emit(reply["content"])
		if reply["done"]:
			last_finish_reason = reply["finish_reason"]
			last_usage = reply["usage"]
			parser.done = true


func _handle_events(events: Array[String], text: PackedStringArray) -> void:
	for payload: String in events:
		var data: Variant = JSON.parse_string(payload)
		if not data is Dictionary:
			continue
		if data.has("error"):
			last_error = "Server error: %s" % JSON.stringify(data["error"])
			continue
		if data.get("usage") is Dictionary:
			last_usage = data["usage"]
		var choices: Array = data.get("choices", [])
		if choices.is_empty():
			continue
		if choices[0].get("finish_reason") is String:
			last_finish_reason = choices[0]["finish_reason"]
		var delta: Dictionary = choices[0].get("delta", {})
		# Ollama and llama.cpp put a thinking model's reasoning in its own field.
		for key: String in ["reasoning", "reasoning_content"]:
			var thought: Variant = delta.get(key)
			if thought is String and thought != "":
				reasoning.emit(thought)
		var piece: Variant = delta.get("content")
		if piece is String and piece != "":
			text.append(piece)
			token.emit(piece)


func cancel() -> void:
	_cancel_ticket += 1


## Waits one frame. Returns false once the deadline has passed or cancel() was called.
func _wait(deadline: Dictionary) -> bool:
	if _now() > deadline["at"] or deadline["ticket"] != _cancel_ticket:
		return false
	# The main loop rather than get_tree(), so this also works before the node enters the tree.
	await (Engine.get_main_loop() as SceneTree).process_frame
	OS.delay_msec(2)
	return true


## The host's IPv4 address, looked up without blocking and remembered for later calls.
## Returns `host` itself if it is already an address or has no IPv4 address.
## Sets last_error if the lookup times out or is cancelled.
func _resolve_ipv4(host: String, deadline: Dictionary) -> String:
	if host.is_valid_ip_address():
		return host
	if _resolved.has(host):
		return _resolved[host]
	var item: int = IP.resolve_hostname_queue_item(host, IP.TYPE_IPV4)
	while IP.get_resolve_item_status(item) == IP.RESOLVER_STATUS_WAITING:
		if not await _wait(deadline):
			IP.erase_resolve_item(item)
			last_error = _stopped(deadline, "Timed out looking up %s" % host)
			return host
	var addresses: Array = IP.get_resolve_item_addresses(item)
	IP.erase_resolve_item(item)
	if addresses.is_empty():
		return host
	_resolved[host] = str(addresses[0])
	return _resolved[host]


## Why a wait ended: "cancelled", or the timeout message.
func _stopped(deadline: Dictionary, timeout_message: String) -> String:
	return "cancelled" if deadline["ticket"] != _cancel_ticket else timeout_message


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## "http://host:port/v1" -> { tls, host, port, path }. Empty on a bad URL.
static func _parse_endpoint(endpoint: String) -> Dictionary:
	var rest: String = endpoint.strip_edges()
	var tls: bool
	if rest.begins_with("https://"):
		tls = true
		rest = rest.trim_prefix("https://")
	elif rest.begins_with("http://"):
		tls = false
		rest = rest.trim_prefix("http://")
	else:
		return {}
	var slash: int = rest.find("/")
	var host_port: String = rest if slash < 0 else rest.left(slash)
	var path: String = "" if slash < 0 else rest.substr(slash).trim_suffix("/")
	var host: String = host_port
	var port: int = 443 if tls else 80
	var colon: int = host_port.rfind(":")
	if colon >= 0:
		host = host_port.left(colon)
		var port_text: String = host_port.substr(colon + 1)
		if not port_text.is_valid_int():
			return {}
		port = port_text.to_int()
	if host == "":
		return {}
	return {"tls": tls, "host": host, "port": port, "path": path}


static func _status_name(status: int) -> String:
	match status:
		HTTPClient.STATUS_CANT_RESOLVE:
			return "can't resolve host"
		HTTPClient.STATUS_CANT_CONNECT:
			return "can't connect"
		HTTPClient.STATUS_CONNECTION_ERROR:
			return "connection error"
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			return "TLS handshake error"
		HTTPClient.STATUS_DISCONNECTED:
			return "disconnected"
	return "status %d" % status
