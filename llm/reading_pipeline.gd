class_name ReadingPipeline
extends RefCounted
## The LLM steps of a reading: classify the question, write the reading, critique it.
## Drawing and computing happen in code (Spread, Dignities, ReadingSummary) between
## classify and read. Prompts come from res://prompts.

const DEFAULT_CLASSIFICATION: Dictionary = {
	"life_area": "general", "timeframe": "unspecified", "question_type": "open",
}
const QUESTION_TYPES: PackedStringArray = ["yes_no", "open"]
## Rough characters per token for English prompts, until a real reading calibrates it.
const CHARS_PER_TOKEN: float = 3.5

var client: LlmClient
## Why the last classify() got no harm verdict ("" when it got one, yes or no).
var weigh_problem: String = ""


func _init(llm_client: LlmClient) -> void:
	client = llm_client


## LLM call 1. Always returns all three keys; falls back to defaults for anything
## the model left out or got wrong. Check client.last_error to see if the call failed.
## A reply with no harm verdict (some models answer the question instead) is asked for
## once more as JSON; weigh_problem says so when there is still none.
func classify(question: String) -> Dictionary:
	var messages: Array = [
		{"role": "system", "content": PromptTemplate.load_and_render("classify_system")},
		{"role": "user", "content": PromptTemplate.load_and_render(
				"classify_user", {"question": question})},
	]
	# LlmClient.complete() is a coroutine in every real backend, though not in the base.
	@warning_ignore("redundant_await")
	var answer: String = await client.complete(messages, false, {"temperature": 0.0})
	var problem: String = client.last_error
	if problem == "" and harm_verdict(answer) == null:
		@warning_ignore("redundant_await")
		var again: String = await client.complete(messages, false,
				{"temperature": 0.0, "response_format": {"type": "json_object"}})
		if client.last_error == "" and harm_verdict(again) != null:
			answer = again
		else:
			problem = client.last_error if client.last_error != "" else "its answer was unreadable"
	# Set last, so it belongs to the call that returns here.
	weigh_problem = problem
	return parse_classification(answer)


## Takes the first {...} block in `answer`, tolerating prose or code fences around it.
static func parse_classification(answer: String) -> Dictionary:
	var result: Dictionary = DEFAULT_CLASSIFICATION.duplicate()
	var data: Dictionary = _reply_object(answer)
	if data.is_empty():
		return result
	for key: String in DEFAULT_CLASSIFICATION:
		var value: Variant = data.get(key)
		if value is String and value.strip_edges() != "":
			result[key] = value.strip_edges().to_lower()
	if not QUESTION_TYPES.has(result["question_type"]):
		result["question_type"] = DEFAULT_CLASSIFICATION["question_type"]
	# The question asks about doing harm: the cards are not dealt (ReadingSession). Only
	# a clear true counts; a model that can't say leaves the reading to go ahead.
	if _as_verdict(data.get("harm")) == true:
		result["harm"] = true
	return result


## Whether the question asks about doing harm, as `answer` says: true, false, or null
## when it does not say.
static func harm_verdict(answer: String) -> Variant:
	return _as_verdict(_reply_object(answer).get("harm"))


static func _as_verdict(harm: Variant) -> Variant:
	if harm is bool:
		return harm
	if harm is String:
		return {"true": true, "false": false}.get(harm.strip_edges().to_lower())
	return null


## The first {...} block in `answer` as a Dictionary, or {} when there is none.
static func _reply_object(answer: String) -> Dictionary:
	var start: int = answer.find("{")
	var end: int = answer.rfind("}")
	if start < 0 or end <= start:
		return {}
	var data: Variant = OllamaApi.parse(answer.substr(start, end - start + 1))
	return data if data is Dictionary else {}


## An estimate of how many tokens `text` costs; good to about 10-20%.
static func estimate_tokens(text: String, chars_per_token: float = CHARS_PER_TOKEN) -> int:
	return estimate_tokens_for(text.length(), chars_per_token)


static func estimate_tokens_for(chars: int, chars_per_token: float = CHARS_PER_TOKEN) -> int:
	return ceili(chars / maxf(chars_per_token, 1.0))


static func messages_length(messages: Array) -> int:
	var total: int = 0
	for message: Dictionary in messages:
		total += str(message.get("content", "")).length()
	return total


## The messages for LLM call 2, exposed so the runner can print them.
static func reading_messages(summary: ReadingSummary) -> Array:
	var values: Dictionary = _values(summary)
	values["examples"] = examples_block()
	return [
		{"role": "system", "content": PromptTemplate.load_and_render("read_system", values)},
		{"role": "user", "content": PromptTemplate.load_and_render("read_user", values)},
	]


## The few-shot examples, fenced off, or "" while read_examples.txt is empty or still
## the placeholder. A placeholder example made mistral-nemo copy its cards instead of
## reading the real ones, so nothing is sent until the author writes real examples.
static func examples_block() -> String:
	var examples: String = ReadingExamples.load_text()
	if examples == "":
		return ""
	return "\n" + PromptTemplate.load_and_render("read_examples_block", {"examples": examples})


## LLM call 2, streamed through client.token.
func read(summary: ReadingSummary) -> String:
	@warning_ignore("redundant_await")
	return await client.complete(reading_messages(summary), true)


## LLM call 3. Returns { passed: bool, reason: String, reading: String }, where
## `reading` is the revised text, or the original when it passed or the reply was unclear.
func critique(summary: ReadingSummary, reading: String) -> Dictionary:
	var values: Dictionary = _values(summary)
	values["reading"] = reading
	var messages: Array = [
		{"role": "system", "content": PromptTemplate.load_and_render("critique_system")},
		{"role": "user", "content": PromptTemplate.load_and_render("critique_user", values)},
	]
	@warning_ignore("redundant_await")
	var answer: String = await client.complete(messages, false, {"temperature": 0.2})
	return parse_critique(answer, reading)


static func parse_critique(answer: String, original: String) -> Dictionary:
	var text: String = answer.strip_edges()
	if text.begins_with("VERDICT: REVISE"):
		var rest: String = text.trim_prefix("VERDICT: REVISE").strip_edges()
		var split: int = rest.find("\n")
		var reason: String = rest if split < 0 else rest.left(split).strip_edges()
		var revised: String = "" if split < 0 else rest.substr(split).strip_edges()
		return {"passed": false, "reason": reason,
				"reading": revised if revised != "" else original}
	return {"passed": text.begins_with("VERDICT: PASS"),
			"reason": "" if text.begins_with("VERDICT: PASS") else "unclear critique reply",
			"reading": original}


static func _values(summary: ReadingSummary) -> Dictionary:
	var values: Dictionary = DEFAULT_CLASSIFICATION.duplicate()
	values.merge(summary.classification, true)
	values["question"] = summary.question
	values["summary"] = summary.to_prompt_text()
	values["reading_words"] = summary.reading_words
	values["position_count"] = summary.positions.size()
	return values
