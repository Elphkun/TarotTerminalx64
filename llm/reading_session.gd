class_name ReadingSession
extends RefCounted
## One reading, step by step: shuffle, optional cut, deal, turn the cards, then the
## LLM reading and the optional critique. The UI calls these methods and listens to
## the signals; nothing here knows about nodes, so tests drive it with a fake client.

enum Step { ASK, SHUFFLED, DEALT, READING, DONE }

signal step_changed(step: Step)
## The shuffled (and possibly cut) deck, top card first.
signal deck_changed(deck: Array[int])
signal dealt(layout: Array[Dictionary])
signal card_turned(slot: int)
## Own cards: the querent put `card` in `slot` (it may replace another).
signal card_placed(slot: int, card: int)
## Every card is face up and the code has worked out the facts.
signal summary_ready(summary: ReadingSummary)
signal reading_started()
signal token(text: String)
## A piece of a thinking model's hidden reasoning, streamed before the visible answer.
signal thinking(text: String)
signal reading_finished(text: String)
## { passed, reason, reading } from ReadingPipeline.parse_critique.
signal critique_finished(verdict: Dictionary)
signal failed(message: String)
## Before the reading is sent: the prompt plus Max tokens may not fit the context window.
signal budget_warning(message: String)
## After a reading: how many tokens it used and how long it took, for the reading panel.
signal usage_reported(line: String)
## The question has been sorted (or the classify call failed): dealing may go ahead.
signal classified()
## The question asks about doing harm: no cards are dealt and no reading is written.
signal refused(message: String)
## The model gave no harm verdict: the reading goes ahead, and says so.
signal unweighed(message: String)

const REFUSAL: String = ("The reader won't lay out the cards for this question. The cards never "
		+ "counsel harm to anyone, you included. If you are thinking of hurting yourself or someone "
		+ "else, please talk to someone you trust, or to a local crisis line.")

var db: CardDb
## When the reader was set to work (_announce_reading, or the verdict on a question weighed
## again), for the time the reading took.
var _reading_started_ms: int = 0
var client: LlmClient
var config: LlmConfig
var pipeline: ReadingPipeline

var step: Step = Step.ASK
var question: String = ""
var spread: Spread
var deck: Array[int] = []
var layout: Array[Dictionary] = []
var turned: Array[bool] = []
var classification: Dictionary = {}
var summary: ReadingSummary
var reading_text: String = ""
## Who wrote the reading and when it finished ("2026-11-19 14:05:00"), for exports.
var reading_model: String = ""
## The deck the cards were drawn from, for the history and the export. Set by the UI.
var reading_deck: String = ""
## The critique's verdict ({passed, reason, reading}), or {} when none ran.
var critique_verdict: Dictionary = {}
## The querent shuffled and laid out their own cards, and names each one (place()).
var own_cards: bool = false
## Picking from the fan: places in `deck` (0 = top card) in the order picked (pick()).
var picked: Array[int] = []
## How the cards came: "app" (dealt from the top), "picked" (chosen face down from the
## fan) or "own" (the querent's own deck). For the history and the export.
var draw: String = "app"
var finished_at: String = ""
## The context window of the last reading: what the server reported, else the setting.
var window: int = 0
## Calibrated from each reading's real prompt_tokens, for the next budget estimate.
var chars_per_token: float = ReadingPipeline.CHARS_PER_TOKEN
## Set when the classify call failed; the reading then uses default classification.
var classify_error: String = ""
## Why the question could not be weighed ("" when it was).
var weigh_problem: String = ""
## Why the reader refused the question ("" unless it asks about doing harm).
var refusal: String = ""

var _classifying: bool = false
## Bumped by reset(), so work still running for an old reading drops its results.
var _generation: int = 0


func _init(card_db: CardDb, llm_client: LlmClient, llm_config: LlmConfig) -> void:
	db = card_db
	client = llm_client
	config = llm_config
	pipeline = ReadingPipeline.new(client)


## ASK -> SHUFFLED. Returns an error message, or "" when the reading has started.
## A `shuffle_seed` >= 0 makes the shuffle reproducible (tests).
func start(question_text: String, spread_id: String, shuffle_seed: int = -1,
		own: bool = false) -> String:
	if step != Step.ASK:
		return "a reading is already under way"
	if question_text.strip_edges() == "":
		return "Ask a question first."
	spread = Spread.from_db(db, spread_id)
	if spread == null:
		return "Unknown spread '%s'." % spread_id
	question = question_text.strip_edges()
	own_cards = own
	# Weighing from the start, so the UI never offers Deal before _classify() begins.
	_classifying = true
	draw = "own" if own else "app"
	if own_cards:
		# Their own deck: no shuffle here, the positions wait for the cards (place()).
		deck.clear()
		var empty: Array[int] = []
		empty.resize(spread.size())
		empty.fill(-1)
		layout = spread.lay_out(empty)
		turned.clear()
		turned.resize(layout.size())
		turned.fill(false)
		_set_step(Step.DEALT)
		dealt.emit(layout)
		_classify(_generation)
		return ""
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if shuffle_seed >= 0:
		rng.seed = shuffle_seed
	else:
		rng.randomize()
	deck = Deck.shuffled(rng)
	_set_step(Step.SHUFFLED)
	deck_changed.emit(deck)
	_classify(_generation)
	return ""


## Lifts the top `at` cards to the bottom. Only between shuffling and dealing.
func cut(at: int) -> void:
	if step != Step.SHUFFLED or not picked.is_empty():
		return
	deck = Deck.cut(deck, at)
	deck_changed.emit(deck)


## The question is still being sorted: dealing, picking and placing wait for it, so a
## question about doing harm is refused before any card is laid.
func is_weighing() -> bool:
	return _classifying


## SHUFFLED -> DEALT: the top cards go face down into the positions. Not while the
## question is being sorted (is_weighing()).
func deal() -> void:
	if step != Step.SHUFFLED or not picked.is_empty() or _classifying:
		return
	draw = "app"
	_deal_cards(deck.slice(0, spread.size()))


## SHUFFLED, then DEALT once the spread is full: takes the card at place `at` in the
## deck (0 = top) for the next position, face down. Returns the card's index, or -1 when
## the pick is refused (not shuffled, out of range, picked already, spread full).
func pick(at: int) -> int:
	if step != Step.SHUFFLED or _classifying or at < 0 or at >= deck.size() or picked.has(at) \
			or picked.size() >= spread.size():
		return -1
	picked.append(at)
	var card: int = deck[at]
	if picked.size() == spread.size():
		var cards: Array[int] = []
		for spot: int in picked:
			cards.append(deck[spot])
		draw = "picked"
		_deal_cards(cards)
	return card


## The cards face down into the positions, in order: SHUFFLED -> DEALT.
func _deal_cards(cards: Array[int]) -> void:
	layout = spread.lay_out(cards)
	turned.clear()
	turned.resize(layout.size())
	turned.fill(false)
	_set_step(Step.DEALT)
	dealt.emit(layout)


## Own cards: puts `card` in `slot`, face up, or changes the card there. Placing the
## last one starts the reading. Not while the question is being sorted (is_weighing()).
## Returns an error message, or "" when placed.
func place(slot: int, card: int) -> String:
	if step != Step.DEALT or not own_cards or _classifying or slot < 0 or slot >= layout.size():
		return "not waiting for cards"
	if not CardIndex.is_valid(card):
		return "not a card"
	for i: int in layout.size():
		if i != slot and layout[i]["card"] == card:
			return "%s is already in position %d." % [db.card(card)["name"], i + 1]
	layout[slot]["card"] = card
	turned[slot] = true
	card_placed.emit(slot, card)
	if not turned.has(false):
		_begin_reading(_generation)
	return ""


## Turns the card in `slot` face up. Turning the last one starts the reading.
func turn(slot: int) -> void:
	if step != Step.DEALT or own_cards or slot < 0 or slot >= turned.size() or turned[slot]:
		return
	turned[slot] = true
	card_turned.emit(slot)
	if not turned.has(false):
		_begin_reading(_generation)


func turn_all() -> void:
	for slot: int in turned.size():
		turn(slot)


func all_turned() -> bool:
	return not turned.is_empty() and not turned.has(false)


## Runs the reading again, after a failure or for another take.
func retry() -> void:
	if summary == null or step == Step.READING:
		return
	_read(_generation)


## The finished (or failed) reading on the table can be read again (reread()).
func can_reread() -> bool:
	return step == Step.DONE and summary != null and refusal == ""


## Reads the cards on the table again from the start, with the model now in the settings:
## the question is weighed again, then read. Same question, spread and cards.
func reread() -> void:
	if not can_reread():
		return
	_generation += 1
	classification = {}
	classify_error = ""
	weigh_problem = ""
	reading_text = ""
	reading_model = ""
	finished_at = ""
	critique_verdict = {}
	_classifying = true
	# Waits for `classified`. First, so a refusal that comes at once is not overwritten.
	_begin_reading(_generation)
	_classify(_generation)


## Back to ASK. Anything still running for this reading is ignored when it returns.
func reset() -> void:
	_generation += 1
	client.cancel()
	_classifying = false
	question = ""
	deck.clear()
	layout.clear()
	turned.clear()
	classification = {}
	summary = null
	reading_text = ""
	reading_model = ""
	finished_at = ""
	critique_verdict = {}
	own_cards = false
	picked.clear()
	draw = "app"
	classify_error = ""
	weigh_problem = ""
	refusal = ""
	_set_step(Step.ASK)


## A saved reading (ReadingHistory) back as the finished reading, with its summary
## worked out again from the cards. Returns an error message, or "" when restored.
## Signals nothing but step_changed: the UI shows the restored reading itself.
func restore(record: Dictionary) -> String:
	var stored: Dictionary = record.get("spread", {})
	var restored: Spread = Spread.from_data(str(stored.get("id", "")),
			stored.get("data", {}) if stored.get("data") is Dictionary else {})
	if restored == null:
		return "The saved reading has no spread."
	var cards: Array[int] = []
	for entry: Variant in record.get("layout", []):
		var card: int = int(entry.get("card", -1)) if entry is Dictionary else -1
		if not CardIndex.is_valid(card):
			return "The saved reading has a card that is not in the deck."
		cards.append(card)
	if cards.size() != restored.size():
		return "The saved reading has %d cards for %d positions." % [cards.size(), restored.size()]
	reset()
	spread = restored
	question = str(record.get("question", ""))
	classification = record.get("classification", {}) if record.get("classification") is Dictionary else {}
	layout = spread.lay_out(cards)
	turned.resize(layout.size())
	turned.fill(true)
	summary = ReadingSummary.build(db, spread, layout, question, classification)
	reading_text = str(record.get("reading", ""))
	reading_model = str(record.get("model", ""))
	reading_deck = str(record.get("deck", ""))
	finished_at = str(record.get("date", ""))
	critique_verdict = record.get("critique", {}) if record.get("critique") is Dictionary else {}
	draw = str(record.get("draw", "app"))
	own_cards = draw == "own"
	_set_step(Step.DONE)
	return ""


## Why a reply stopped at "length": the server's window filled, or Max tokens ran out.
func _out_of_room(prompt_tokens: int, reply_tokens: int) -> String:
	var total: int = prompt_tokens + reply_tokens
	if prompt_tokens <= 0:
		return ("the reader ran out of room before finishing. Raise Max tokens or the context "
				+ "window (%s), or delete an example.") % _n(window)
	if (total >= window * 0.95 or reply_tokens < config.max_tokens * 0.95):
		var advice: String = "Raise Context window in Settings"
		if not client.sets_context_window():
			advice = "Raise the window on the server (OLLAMA_CONTEXT_LENGTH for Ollama) and Context window in Settings"
		return ("the reader ran out of room: prompt %s + %s written = %s of the %s-token context "
				+ "window. %s, or delete an example.") % [
				_n(prompt_tokens), _n(reply_tokens), _n(total), _n(window), advice]
	return ("the reader hit the Max tokens limit (%s) before finishing; a thinking model spends "
			+ "part of it thinking. Raise Max tokens in Settings.") % _n(config.max_tokens)


## 12345 -> "12,345".
static func _n(value: int) -> String:
	var digits: String = str(absi(value))
	var out: String = ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


func _set_step(value: Step) -> void:
	step = value
	step_changed.emit(step)


func _classify(generation: int) -> void:
	_classifying = true
	var result: Dictionary = await pipeline.classify(question)
	if generation != _generation:
		return
	classify_error = client.last_error
	weigh_problem = pipeline.weigh_problem
	classification = result
	_classifying = false
	if result.get("harm") == true:
		refusal = REFUSAL
		if step == Step.DEALT:
			# Own cards: the empty positions go. (Cards read again stay on the table.)
			layout.clear()
			turned.clear()
		_set_step(Step.DONE)
		refused.emit(refusal)
	elif weigh_problem != "":
		unweighed.emit("The reader could not weigh this question for harm: %s." % weigh_problem.trim_suffix("."))
	classified.emit()


## Starts at the last card turned or placed, when the question has been weighed, or with
## reread(), which weighs it again first.
func _begin_reading(generation: int) -> void:
	_announce_reading()
	if _classifying:
		await classified
		if generation != _generation:
			return
		# Weighing may have loaded the model; the reading's own time starts here.
		_reading_started_ms = Time.get_ticks_msec()
	if refusal != "":
		return
	summary = ReadingSummary.build(db, spread, layout, question, classification)
	summary_ready.emit(summary)
	_read(generation, false)


func _announce_reading() -> void:
	_reading_started_ms = Time.get_ticks_msec()
	_set_step(Step.READING)
	reading_text = ""
	reading_started.emit()


func _read(generation: int, announce: bool = true) -> void:
	if announce:
		_announce_reading()
	var forward: Callable = func(piece: String) -> void:
		if generation == _generation:
			token.emit(piece)
	var forward_thinking: Callable = func(piece: String) -> void:
		if generation == _generation:
			thinking.emit(piece)
	# Classify has loaded the model by now, so the server can say what window it has.
	# The base LlmClient returns at once; OpenAiClient makes a request, so the await stays.
	@warning_ignore("redundant_await")
	window = await client.loaded_context()
	if generation != _generation:
		return
	if window <= 0:
		window = config.context_tokens
	var prompt_chars: int = ReadingPipeline.messages_length(ReadingPipeline.reading_messages(summary))
	var estimate: int = ReadingPipeline.estimate_tokens_for(prompt_chars, chars_per_token)
	if estimate + config.max_tokens > window:
		budget_warning.emit(("This prompt is about %s tokens; with up to %s more for thinking and "
				+ "the reply it may not fit the %s-token window.") % [
				_n(estimate), _n(config.max_tokens), _n(window)])
	client.token.connect(forward)
	client.reasoning.connect(forward_thinking)
	var text: String = await pipeline.read(summary)
	client.token.disconnect(forward)
	client.reasoning.disconnect(forward_thinking)
	if generation != _generation:
		return
	var used: Dictionary = client.last_usage
	var prompt_tokens: int = int(used.get("prompt_tokens", 0))
	var reply_tokens: int = int(used.get("completion_tokens", 0))
	if prompt_tokens > 0:
		chars_per_token = float(prompt_chars) / prompt_tokens
	var problem: String = client.last_error
	if problem == "" and client.last_finish_reason == "length":
		problem = _out_of_room(prompt_tokens, reply_tokens)
	elif problem == "" and text.strip_edges() == "":
		problem = "the model sent no reading. A thinking model may have spent the whole " \
				+ "Max tokens limit (%s) thinking; raise it in Settings." % _n(config.max_tokens)
	if problem != "":
		_set_step(Step.DONE)
		failed.emit(problem)
		return
	reading_text = text
	reading_model = client.last_model
	finished_at = Time.get_datetime_string_from_system(false, true)
	reading_finished.emit(text)
	# The time runs from "The reader is studying the spread" (the panel's timer) to the end.
	var seconds: int = roundi((Time.get_ticks_msec() - _reading_started_ms) / 1000.0)
	if prompt_tokens > 0:
		usage_reported.emit("Prompt %s · reply %s · window %s tokens · %s s" % [
				_n(prompt_tokens), _n(reply_tokens), _n(window), _n(seconds)])
	else:
		usage_reported.emit("%s s" % _n(seconds))
	if config.critique:
		var verdict: Dictionary = await pipeline.critique(summary, text)
		if generation != _generation:
			return
		if client.last_error != "":
			failed.emit("Critique failed: %s" % client.last_error)
		else:
			reading_text = verdict["reading"]
			critique_verdict = verdict
			critique_finished.emit(verdict)
	_set_step(Step.DONE)
