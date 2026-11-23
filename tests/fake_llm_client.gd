extends LlmClient
## Stands in for the LLM in tests. Answers classify with JSON, streams a canned
## reading, and passes any critique. With `frames_per_token` 0 it never waits, so
## a whole ReadingSession runs synchronously inside a unit test.

const READING := "**Past: the first card**\nA canned reading for tests.\n\n**Synthesis**\nAll is well."

var frames_per_token: int = 0
## The next call fails with this error, then the client works again.
var fail_next: String = ""
var classify_reply: String = "{\"life_area\": \"career\", \"timeframe\": \"this year\", \"question_type\": \"yes_no\"}"
var critique_reply: String = "VERDICT: PASS"
## Streamed as hidden reasoning, word by word, before a streamed reading. "" for none.
var thinking_reply: String = ""
## The streamed reading comes back empty, as when a thinking model runs out of tokens.
var empty_reading: bool = false
## The streamed reading stops halfway with finish_reason "length", as when the server's
## context window fills (usage: 3000 prompt + 1096 written = 4096).
var finish_length: bool = false
## What loaded_context() reports; -1 means the server cannot say.
var context_window: int = -1
## The system prompt of every call, in order.
var calls: Array[String] = []
## Classify waits for release_classify() instead of answering at once, as a real server
## does while the model loads.
var hold_classify: bool = false

signal _classify_released()

var _cancel_ticket: int = 0


func release_classify() -> void:
	hold_classify = false
	_classify_released.emit()


func complete(messages: Array, stream: bool = false, _options: Dictionary = {}) -> String:
	last_error = ""
	last_finish_reason = "stop"
	last_usage = {}
	last_model = "fake-model"
	var system: String = messages[0]["content"] if not messages.is_empty() else ""
	calls.append(system)
	if fail_next != "":
		last_error = fail_next
		fail_next = ""
		return ""
	if system.contains("sort tarot questions"):
		if hold_classify:
			await _classify_released
		return classify_reply
	if system.contains("You check tarot readings"):
		return critique_reply
	if not stream:
		return READING
	var ticket: int = _cancel_ticket
	for word: String in thinking_reply.split(" ", false):
		for frame: int in frames_per_token:
			await (Engine.get_main_loop() as SceneTree).process_frame
		if ticket != _cancel_ticket:
			last_error = "cancelled"
			return ""
		reasoning.emit(word + " ")
	if empty_reading:
		return ""
	var words: PackedStringArray = READING.split(" ")
	if finish_length:
		words = words.slice(0, floori(words.size() / 2.0))
	for word: String in words:
		for frame: int in frames_per_token:
			await (Engine.get_main_loop() as SceneTree).process_frame
		if ticket != _cancel_ticket:
			last_error = "cancelled"
			return ""
		token.emit(word + " ")
	if finish_length:
		last_finish_reason = "length"
		last_usage = {"prompt_tokens": 3000, "completion_tokens": 1096}
		return " ".join(words)
	last_usage = {"prompt_tokens": 1000, "completion_tokens": 200}
	return READING


func loaded_context(_model_name: String = "") -> int:
	return context_window


func cancel() -> void:
	_cancel_ticket += 1


func list_chat_models() -> PackedStringArray:
	last_error = ""
	return PackedStringArray(["fake-small", "fake-large"])


func count(prompt_marker: String) -> int:
	return calls.filter(func(system: String) -> bool: return system.contains(prompt_marker)).size()
