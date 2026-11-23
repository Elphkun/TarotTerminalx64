extends "res://tests/test_case.gd"


func test_render_keeps_single_braces() -> void:
	var text: String = PromptTemplate.render(
			"Q: {{question}} as {\"life_area\": \"...\"} {{missing}}", {"question": "Why?"})
	assert_eq(text, "Q: Why? as {\"life_area\": \"...\"} {{missing}}")


func test_all_templates_exist_and_fill() -> void:
	for prompt_name: String in ["classify_system", "classify_user", "read_system",
			"read_user", "read_examples_block", "critique_system", "critique_user"]:
		assert_true(PromptTemplate.load_text(prompt_name) != "", prompt_name)
	var summary: ReadingSummary = ReadingSummary.build(
			db(), spread3(), three_card(["wands_2", "cups_2", "world"]), "Will it work?",
			{"life_area": "career", "timeframe": "this year", "question_type": "yes_no"})
	for message: Dictionary in ReadingPipeline.reading_messages(summary):
		assert_false(message["content"].contains("{{"), "unfilled placeholder in %s" % message["role"])
	var user: String = ReadingPipeline.reading_messages(summary)[1]["content"]
	assert_true(user.contains("Will it work?"))
	assert_true(user.contains("Two of Cups"))
	assert_true(user.contains("Ill-dignified cards: Two of Wands in past, Two of Cups in present"), user)


func test_parse_classification() -> void:
	var parsed: Dictionary = ReadingPipeline.parse_classification(
			"Sure!\n```json\n{\"life_area\": \"Career\", \"question_type\": \"yes_no\"}\n```")
	assert_eq(parsed, {"life_area": "career", "timeframe": "unspecified", "question_type": "yes_no"})
	assert_eq(ReadingPipeline.parse_classification("no json"),
			ReadingPipeline.DEFAULT_CLASSIFICATION)
	assert_eq(ReadingPipeline.parse_classification("{\"question_type\": \"maybe\"}")["question_type"],
			"open")


func test_parse_classification_harm() -> void:
	assert_eq(ReadingPipeline.parse_classification("{\"harm\": true}").get("harm"), true)
	assert_eq(ReadingPipeline.parse_classification("{\"harm\": \"True\"}").get("harm"), true,
			"a model that quotes its true still counts")
	assert_false(ReadingPipeline.parse_classification("{\"harm\": false}").has("harm"))
	assert_false(ReadingPipeline.parse_classification("{\"harm\": \"maybe\"}").has("harm"),
			"only a clear true refuses")
	assert_false(ReadingPipeline.parse_classification("no json").has("harm"),
			"a model that can't say lets the reading go ahead")


func test_parse_critique() -> void:
	assert_true(ReadingPipeline.parse_critique("VERDICT: PASS", "draft")["passed"])
	var revised: Dictionary = ReadingPipeline.parse_critique(
			"VERDICT: REVISE\nMissed the Two of Cups.\n\nNew text.", "draft")
	assert_false(revised["passed"])
	assert_eq(revised["reason"], "Missed the Two of Cups.")
	assert_eq(revised["reading"], "New text.")


func test_endpoint_parsing() -> void:
	assert_eq(OpenAiClient._parse_endpoint("http://my-pc:11434/v1"),
			{"tls": false, "host": "my-pc", "port": 11434, "path": "/v1"})
	assert_eq(OpenAiClient._parse_endpoint("https://api.openai.com/v1/"),
			{"tls": true, "host": "api.openai.com", "port": 443, "path": "/v1"})
	assert_eq(OpenAiClient._parse_endpoint("localhost:1234"), {})


func test_config_overrides() -> void:
	var config: LlmConfig = LlmConfig.new()
	config.apply({"temperature": "0.3", "max_tokens": "512", "critique": true, "model": "x"})
	assert_eq(config.temperature, 0.3)
	assert_eq(config.max_tokens, 512)
	assert_true(config.critique)
	assert_eq(config.model, "x")
