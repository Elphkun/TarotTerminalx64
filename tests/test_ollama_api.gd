extends "res://tests/test_case.gd"
## Ollama's native API: the request body, the replies, and the streamed lines.


func _config() -> LlmConfig:
	var config: LlmConfig = LlmConfig.new()
	config.context_tokens = 12288
	config.max_tokens = 4096
	config.temperature = 0.7
	return config


func test_body_carries_the_context_window() -> void:
	var messages: Array = [{"role": "user", "content": "hi"}]
	var body: Dictionary = OllamaApi.chat_body(_config(), "gemma", messages, true, {})
	assert_eq(body["model"], "gemma")
	assert_eq(body["messages"], messages)
	assert_eq(body["stream"], true)
	assert_eq(body["options"]["num_ctx"], 12288)
	assert_eq(body["options"]["num_predict"], 4096)
	assert_true(is_equal_approx(body["options"]["temperature"], 0.7))
	assert_eq(body["keep_alive"], "30m")
	assert_false(body.has("think"), "thinking on: the model's own default, never think=true")
	assert_false(body.has("format"))


func test_body_options() -> void:
	var config: LlmConfig = _config()
	config.thinking = false
	config.keep_alive = ""
	var body: Dictionary = OllamaApi.chat_body(config, "m", [], false,
			{"max_tokens": 300, "temperature": 0.1, "response_format": {"type": "json_object"}})
	assert_eq(body["think"], false)
	assert_eq(body["format"], "json")
	assert_eq(body["options"]["num_predict"], 300)
	assert_eq(body["options"]["num_ctx"], 12288, "every call asks for the same window")
	assert_false(body.has("keep_alive"), "empty keep_alive leaves the server's default")
	assert_false(OllamaApi.chat_body(config, "m", [], false, {}, false).has("think"),
			"the retry for a model that cannot think leaves think out")


func test_a_call_may_turn_thinking_off_for_itself() -> void:
	var config: LlmConfig = _config()
	assert_true(config.thinking, "on in the settings")
	assert_eq(OllamaApi.chat_body(config, "m", [], false, {"thinking": false}).get("think"), false)
	assert_false(OllamaApi.chat_body(config, "m", [], false, {"thinking": false}, false).has("think"),
			"still left out for a model that cannot think")
	assert_false(OllamaApi.chat_body(config, "m", [], false, {}).has("think"), "other calls keep the setting")


func test_a_server_that_refuses_reasoning_effort() -> void:
	assert_true(OpenAiClient.refuses_reasoning("HTTP 400: Unrecognized request argument: reasoning_effort"))
	assert_true(OpenAiClient.refuses_reasoning("HTTP 422: {\"loc\": [\"body\", \"reasoning_effort\"]}"))
	assert_false(OpenAiClient.refuses_reasoning("HTTP 400: context too long"))
	assert_false(OpenAiClient.refuses_reasoning("HTTP 500: reasoning failed"))
	assert_false(OpenAiClient.refuses_reasoning(""))


func test_replies() -> void:
	var piece: Dictionary = OllamaApi.read_reply(JSON.parse_string(
			'{"message":{"role":"assistant","content":"Hel","thinking":""},"done":false}'))
	assert_eq(piece["content"], "Hel")
	assert_false(piece["done"])
	var thought: Dictionary = OllamaApi.read_reply(JSON.parse_string(
			'{"message":{"role":"assistant","content":"","thinking":"Goal:"},"done":false}'))
	assert_eq(thought["thinking"], "Goal:")
	var last: Dictionary = OllamaApi.read_reply(JSON.parse_string(
			'{"message":{"role":"assistant","content":""},"done":true,"done_reason":"length",'
			+ '"prompt_eval_count":22,"eval_count":225}'))
	assert_true(last["done"])
	assert_eq(last["finish_reason"], "length")
	assert_eq(last["usage"], {"prompt_tokens": 22, "completion_tokens": 225})
	var failed: Dictionary = OllamaApi.read_reply(JSON.parse_string('{"error":"model not found"}'))
	assert_eq(failed["error"], "model not found")
	assert_true(OllamaApi.read_reply("nonsense")["error"] != "")


func test_models_and_version() -> void:
	assert_eq(OllamaApi.model_names(JSON.parse_string(
			'{"models":[{"name":"gemma4:26b"},{"name":"mistral:7b"},{"size":1}]}')),
			PackedStringArray(["gemma4:26b", "mistral:7b"]))
	assert_true(OllamaApi.is_version_reply('{"version":"0.40.16"}'))
	assert_false(OllamaApi.is_version_reply('{"object":"list"}'))
	assert_false(OllamaApi.is_version_reply("404 page not found"))


func test_ndjson_lines_split_anywhere() -> void:
	var parser: NdjsonParser = NdjsonParser.new()
	var stream: PackedByteArray = '{"a":1}\n\n{"b":"é"}\n{"c":3}'.to_utf8_buffer()
	var lines: Array[String] = []
	for i: int in stream.size():
		lines.append_array(parser.feed(stream.slice(i, i + 1)))
	lines.append_array(parser.finish())
	assert_eq(lines, ['{"a":1}', '{"b":"é"}', '{"c":3}'] as Array[String])


func test_streamed_lines_reach_the_client() -> void:
	var client: OpenAiClient = OpenAiClient.new(_config())
	var tokens: PackedStringArray = []
	var thoughts: PackedStringArray = []
	client.token.connect(func(piece: String) -> void: tokens.append(piece))
	client.reasoning.connect(func(piece: String) -> void: thoughts.append(piece))
	var parser: NdjsonParser = NdjsonParser.new()
	var text: PackedStringArray = []
	client._handle_ollama_lines(parser, [
		'{"message":{"content":"","thinking":"Hmm"},"done":false}',
		'{"message":{"content":"The "},"done":false}',
		'{"message":{"content":"Tower"},"done":false}',
		'{"message":{"content":""},"done":true,"done_reason":"stop","prompt_eval_count":5,"eval_count":2}',
	] as Array[String], text)
	assert_eq("".join(text), "The Tower")
	assert_eq(tokens, PackedStringArray(["The ", "Tower"]))
	assert_eq(thoughts, PackedStringArray(["Hmm"]))
	assert_true(parser.done, "the done line ends the stream")
	assert_eq(client.last_finish_reason, "stop")
	assert_eq(client.last_usage["completion_tokens"], 2)
	client.free()


func test_backend_setting() -> void:
	var config: LlmConfig = _config()
	config.backend = "openai"
	var client: OpenAiClient = OpenAiClient.new(config)
	assert_false(client.sets_context_window())
	config.backend = "ollama"
	assert_true(client.sets_context_window())
	client.free()
	var path: String = "user://test_llm_backend.json"
	config.thinking = false
	config.keep_alive = "-1"
	config.save(path)
	var loaded: LlmConfig = LlmConfig.load_from(path)
	assert_eq(loaded.backend, "ollama")
	assert_eq(loaded.thinking, false)
	assert_eq(loaded.keep_alive, "-1")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
