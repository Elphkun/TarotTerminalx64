extends "res://tests/test_case.gd"

const FakeLlmClient := preload("res://tests/fake_llm_client.gd")

var _client: FakeLlmClient
var _config: LlmConfig


func _session() -> ReadingSession:
	_client = FakeLlmClient.new()
	_config = LlmConfig.new()
	return ReadingSession.new(db(), _client, _config)


func _free_client() -> void:
	_client.free()


func test_needs_a_question() -> void:
	var session: ReadingSession = _session()
	assert_eq(session.start("   ", "three_card", 1), "Ask a question first.")
	assert_eq(session.step, ReadingSession.Step.ASK)
	assert_true(session.start("Will it rain?", "no_such_spread", 1).begins_with("Unknown spread"))
	_free_client()


func test_full_reading_in_order() -> void:
	var session: ReadingSession = _session()
	var events: Array[String] = []
	session.dealt.connect(func(_layout: Array[Dictionary]) -> void: events.append("dealt"))
	session.summary_ready.connect(func(_s: ReadingSummary) -> void: events.append("summary"))
	session.reading_finished.connect(func(_t: String) -> void: events.append("read"))
	var tokens: Array[String] = []
	session.token.connect(func(text: String) -> void: tokens.append(text))

	assert_eq(session.start("Should I move?", "three_card", 1), "")
	assert_eq(session.step, ReadingSession.Step.SHUFFLED)
	assert_eq(session.classification["life_area"], "career", "classify ran")
	session.deal()
	assert_eq(session.layout.size(), 3)
	session.turn(0)
	session.turn(0)
	session.turn(2)
	assert_eq(session.summary, null, "no summary until every card is up")
	assert_eq(_client.count("Golden Dawn tradition, reading"), 0, "no reading yet")
	session.turn(1)
	assert_eq(events, ["dealt", "summary", "read"] as Array[String])
	assert_eq(session.step, ReadingSession.Step.DONE)
	assert_eq("".join(tokens).strip_edges(), FakeLlmClient.READING)
	assert_eq(session.summary.classification["question_type"], "yes_no")
	_free_client()


func test_thinking_is_forwarded_but_not_part_of_the_reading() -> void:
	var session: ReadingSession = _session()
	_client.thinking_reply = "Let me weigh the Tower against the Star."
	var thoughts: Array[String] = []
	session.thinking.connect(func(text: String) -> void: thoughts.append(text))
	session.start("Q", "three_card", 3)
	session.deal()
	session.turn_all()
	assert_eq("".join(thoughts).strip_edges(), _client.thinking_reply)
	assert_eq(session.reading_text, FakeLlmClient.READING, "thinking stays out of the reading")
	_free_client()


func test_an_empty_reading_is_a_failure() -> void:
	var session: ReadingSession = _session()
	_client.empty_reading = true
	var failed_messages: Array[String] = []
	session.failed.connect(func(message: String) -> void: failed_messages.append(message))
	session.start("Q", "three_card", 3)
	session.deal()
	session.turn_all()
	assert_eq(failed_messages.size(), 1)
	assert_true(failed_messages[0].contains("Max tokens"), str(failed_messages))
	_free_client()


func test_a_full_window_is_a_failure_that_names_the_window() -> void:
	var session: ReadingSession = _session()
	_client.finish_length = true
	_client.context_window = 4096
	var failed_messages: Array[String] = []
	session.failed.connect(func(message: String) -> void: failed_messages.append(message))
	var tokens: Array[String] = []
	session.token.connect(func(text: String) -> void: tokens.append(text))
	session.start("Q", "three_card", 3)
	session.deal()
	session.turn_all()
	assert_eq(failed_messages.size(), 1)
	assert_true(failed_messages[0].contains("ran out of room") and failed_messages[0].contains("4,096-token"),
			str(failed_messages))
	assert_true(failed_messages[0].contains("3,000 + 1,096"), str(failed_messages))
	assert_false(tokens.is_empty(), "the partial reading still streamed")
	assert_eq(session.reading_text, "", "a cut-off reading is not kept as finished")
	_free_client()


func test_budget_warning_and_usage() -> void:
	var session: ReadingSession = _session()
	var warnings: Array[String] = []
	var usage: Array[String] = []
	session.budget_warning.connect(func(message: String) -> void: warnings.append(message))
	session.usage_reported.connect(func(line: String) -> void: usage.append(line))
	_config.max_tokens = 8192
	_client.context_window = 4096  # the server's real window wins over the 16k setting
	session.start("Q", "three_card", 3)
	session.deal()
	session.turn_all()
	assert_eq(warnings.size(), 1, "8,192 for the reply cannot fit a 4,096 window")
	assert_true(warnings[0].contains("4,096-token window"), str(warnings))
	assert_eq(usage.size(), 1, "one usage line")
	var timed: RegEx = RegEx.create_from_string("^Prompt 1,000 · reply 200 · window 4,096 tokens · \\d+ s$")
	assert_true(timed.search(usage[0]) != null, "tokens, then the seconds taken: %s" % usage)
	assert_true(session.chars_per_token > 1.0, "calibrated from the real prompt size")

	session.reset()
	warnings.clear()
	_client.context_window = -1  # unknown: the setting is used
	_config.max_tokens = 4096
	session.start("Q", "three_card", 4)
	session.deal()
	session.turn_all()
	assert_eq(warnings.size(), 0, str(warnings))
	assert_eq(session.window, 16384)
	_free_client()


func test_cut_changes_the_deal() -> void:
	var plain: ReadingSession = _session()
	plain.start("Q", "three_card", 7)
	var top: Array[int] = plain.deck.slice(0, 13)
	_free_client()
	var session: ReadingSession = _session()
	session.start("Q", "three_card", 7)
	session.cut(10)
	session.deal()
	assert_eq(session.layout[0]["card"], top[10], "the 11th card is now on top")
	session.cut(5)
	assert_eq(session.layout[0]["card"], top[10], "no cutting after the deal")
	_free_client()


func test_failure_then_retry() -> void:
	var session: ReadingSession = _session()
	var failed_messages: Array[String] = []
	session.failed.connect(func(message: String) -> void: failed_messages.append(message))
	session.start("Q", "three_card", 3)
	session.deal()
	_client.fail_next = "HTTP 500: boom"
	session.turn_all()
	assert_eq(failed_messages, ["HTTP 500: boom"] as Array[String])
	assert_eq(session.reading_text, "")
	assert_true(session.summary != null, "the facts are there even when the LLM fails")
	session.retry()
	assert_eq(session.reading_text, FakeLlmClient.READING)
	_free_client()


func test_classify_failure_falls_back_to_defaults() -> void:
	var session: ReadingSession = _session()
	_client.fail_next = "Could not connect"
	session.start("Q", "three_card", 3)
	assert_eq(session.classify_error, "Could not connect")
	assert_eq(session.classification, ReadingPipeline.DEFAULT_CLASSIFICATION)
	_free_client()


func test_critique_revision_replaces_the_text() -> void:
	var session: ReadingSession = _session()
	_config.critique = true
	_client.critique_reply = "VERDICT: REVISE\nMissed a card.\n\nBetter text."
	var verdicts: Array[Dictionary] = []
	session.critique_finished.connect(func(v: Dictionary) -> void: verdicts.append(v))
	session.start("Q", "three_card", 3)
	session.deal()
	session.turn_all()
	assert_eq(verdicts.size(), 1)
	assert_eq(session.reading_text, "Better text.")
	assert_eq(session.step, ReadingSession.Step.DONE)
	_free_client()


const HARM_REPLY := "{\"life_area\": \"relationships\", \"timeframe\": \"unspecified\", " \
		+ "\"question_type\": \"yes_no\", \"harm\": true}"


func test_a_question_about_harm_is_refused_before_the_deal() -> void:
	var session: ReadingSession = _session()
	_client.classify_reply = HARM_REPLY
	var refused: Array[String] = []
	session.refused.connect(func(message: String) -> void: refused.append(message))
	var dealt: Array[bool] = []
	session.dealt.connect(func(_layout: Array[Dictionary]) -> void: dealt.append(true))
	assert_eq(session.start("Should I kill my best friend?", "three_card", 1), "")
	assert_eq(refused, [ReadingSession.REFUSAL] as Array[String])
	assert_eq(session.step, ReadingSession.Step.DONE)
	session.deal()
	assert_eq(session.pick(0), -1, "no picking either")
	assert_true(dealt.is_empty() and session.layout.is_empty(), "no card is dealt")
	assert_eq(_client.count("Golden Dawn tradition, reading"), 0, "no reading is asked for")
	session.reset()
	assert_eq(session.refusal, "", "a new reading starts clean")
	_free_client()


func test_dealing_waits_for_the_question_to_be_weighed() -> void:
	var session: ReadingSession = _session()
	_client.hold_classify = true
	session.start("Should I move?", "three_card", 1)
	assert_true(session.is_weighing())
	session.deal()
	assert_eq(session.step, ReadingSession.Step.SHUFFLED, "Deal waits while the question is weighed")
	assert_eq(session.pick(0), -1, "and so does picking")
	_client.release_classify()
	assert_false(session.is_weighing())
	session.deal()
	assert_eq(session.step, ReadingSession.Step.DEALT, "then deals as usual")
	_free_client()


func test_own_cards_wait_for_the_harm_verdict() -> void:
	var session: ReadingSession = _session()
	_client.hold_classify = true
	session.start("Should I move?", "three_card", -1, true)
	assert_eq(session.place(0, 5), "not waiting for cards", "no card is placed while weighing")
	assert_eq(session.layout[0]["card"], -1)
	_client.release_classify()
	assert_eq(session.place(0, 5), "", "then cards are placed as usual")
	_free_client()


func test_own_cards_are_refused_before_any_is_placed() -> void:
	var session: ReadingSession = _session()
	_client.hold_classify = true
	_client.classify_reply = HARM_REPLY
	session.start("Should I hurt him?", "three_card", -1, true)
	for slot: int in 3:
		session.place(slot, slot)
	_client.release_classify()
	assert_eq(session.refusal, ReadingSession.REFUSAL)
	assert_eq(session.step, ReadingSession.Step.DONE)
	assert_true(session.layout.is_empty(), "the empty positions go")
	assert_false(session.can_reread(), "a refused question can't be read again")
	assert_eq(_client.count("Golden Dawn tradition, reading"), 0, "no reading is asked for")
	_free_client()


func _unweighed(session: ReadingSession) -> Array[String]:
	var notes: Array[String] = []
	session.unweighed.connect(func(message: String) -> void: notes.append(message))
	return notes


func test_an_unreadable_verdict_is_asked_for_again_as_json() -> void:
	var session: ReadingSession = _session()
	var notes: Array[String] = _unweighed(session)
	_client.classify_replies = ["No, I do not recommend it."]
	_client.classify_reply = HARM_REPLY
	session.start("Should I kill my best friend?", "three_card", 1)
	assert_eq(_client.count("sort tarot questions"), 2)
	assert_false(_client.options_seen[0].has("response_format"))
	assert_true(_client.options_seen[1].has("response_format"), "the second try asks for JSON")
	assert_eq(session.refusal, ReadingSession.REFUSAL, "and its verdict counts")
	assert_true(notes.is_empty())
	_free_client()


func test_no_verdict_after_two_tries_goes_ahead_and_says_so() -> void:
	var session: ReadingSession = _session()
	var notes: Array[String] = _unweighed(session)
	_client.classify_reply = "{\"life_area\": \"career\", \"harm\": \"perhaps\"}"
	session.start("Should I move?", "three_card", 1)
	assert_eq(_client.count("sort tarot questions"), 2)
	assert_eq(notes.size(), 1)
	assert_true(notes.size() == 1 and notes[0].contains("could not weigh"))
	assert_eq(session.classification["life_area"], "career", "what it did say is kept")
	session.deal()
	assert_eq(session.step, ReadingSession.Step.DEALT, "the reading goes ahead")
	_free_client()


func test_weighing_never_thinks() -> void:
	var session: ReadingSession = _session()
	_config.thinking = true
	_client.classify_replies = ["Not JSON."]
	session.start("Should I move?", "three_card", 1)
	session.deal()
	session.turn_all()
	assert_eq(_client.options_seen.size(), 3, "two tries at weighing, then the reading")
	assert_eq(_client.options_seen[0].get("thinking"), false)
	assert_eq(_client.options_seen[1].get("thinking"), false, "nor does the second try")
	assert_false(_client.options_seen[2].has("thinking"), "the reading follows the setting")
	_free_client()


func test_a_failed_weighing_is_not_tried_twice_and_says_so() -> void:
	var session: ReadingSession = _session()
	var notes: Array[String] = _unweighed(session)
	_client.fail_next = "Could not connect"
	session.start("Should I move?", "three_card", 1)
	assert_eq(_client.calls.size(), 1)
	assert_true(notes.size() == 1 and notes[0].contains("Could not connect"))
	_free_client()


func _finished(question: String = "Should I move?") -> ReadingSession:
	var session: ReadingSession = _session()
	session.start(question, "three_card", 1)
	session.deal()
	session.turn_all()
	return session


func test_reread_keeps_the_cards_and_uses_the_model_now_chosen() -> void:
	var session: ReadingSession = _finished()
	assert_eq(session.step, ReadingSession.Step.DONE)
	var cards: Array = session.layout.map(func(entry: Dictionary) -> int: return entry["card"])
	_client.model_name = "another-model"
	_client.classify_reply = "{\"life_area\": \"home\", \"question_type\": \"open\", \"harm\": false}"
	assert_true(session.can_reread())
	session.reread()
	assert_eq(session.step, ReadingSession.Step.DONE)
	assert_eq(session.layout.map(func(entry: Dictionary) -> int: return entry["card"]), cards)
	assert_eq(session.reading_model, "another-model")
	assert_eq(session.summary.classification["life_area"], "home", "the question is sorted again")
	assert_eq(_client.count("sort tarot questions"), 2)
	assert_eq(_client.count("Golden Dawn tradition, reading"), 2)
	_free_client()


func test_reread_waits_for_the_verdict() -> void:
	var session: ReadingSession = _finished()
	_client.hold_classify = true
	session.reread()
	assert_eq(session.step, ReadingSession.Step.READING)
	assert_true(session.is_weighing())
	assert_false(session.can_reread(), "not while one is under way")
	assert_eq(_client.count("Golden Dawn tradition, reading"), 1, "no reading before the verdict")
	_client.release_classify()
	assert_eq(session.step, ReadingSession.Step.DONE)
	assert_eq(_client.count("Golden Dawn tradition, reading"), 2)
	_free_client()


func test_reread_can_be_refused() -> void:
	# At once, and after a wait: either way it ends refused, with the cards left lying.
	for hold: bool in [false, true]:
		var session: ReadingSession = _finished()
		_client.classify_reply = HARM_REPLY
		_client.hold_classify = hold
		session.reread()
		_client.release_classify()
		assert_eq(session.step, ReadingSession.Step.DONE, "hold %s" % hold)
		assert_eq(session.refusal, ReadingSession.REFUSAL)
		assert_eq(session.layout.size(), 3)
		assert_eq(session.reading_text, "")
		assert_false(session.can_reread())
		assert_eq(_client.count("Golden Dawn tradition, reading"), 1, "only the first reading")
		_free_client()


func test_new_reading_during_a_reread_drops_it() -> void:
	var session: ReadingSession = _finished()
	_client.hold_classify = true
	session.reread()
	session.reset()
	_client.release_classify()
	assert_eq(session.step, ReadingSession.Step.ASK)
	assert_eq(_client.count("Golden Dawn tradition, reading"), 1)
	_free_client()


func test_reset_starts_over() -> void:
	var session: ReadingSession = _session()
	session.start("Q", "three_card", 3)
	session.deal()
	session.reset()
	assert_eq(session.step, ReadingSession.Step.ASK)
	assert_eq(session.layout.size(), 0)
	assert_eq(session.start("Again?", "three_card", 4), "")
	_free_client()
