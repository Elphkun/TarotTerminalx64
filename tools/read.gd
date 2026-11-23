extends SceneTree
## Headless reading runner, for iterating on prompts.
##
## Usage: godot --headless --script tools/read.gd -- --question="Should I take the job?"
##   --spread=three_card     spread id from data/spreads.json
##   --seed=N                reproducible shuffle (random otherwise)
##   --cut=N                 cut the shuffled deck at N
##   --cards=0,wands_page,50 force the cards (indices or ids), one per position
##   --no-llm                print the computed summary and stop
##   --classify=0            skip the classify call (use defaults)
##   --critique              run the critique pass (or set critique in user://llm.json)
##   --json                  also print the summary as JSON
##   --prompt                also print the full reading messages
##   --thinking              show a thinking model's reasoning as it streams
##   --endpoint=URL --model=NAME --api_key=KEY --temperature=0.8 --max_tokens=N
##   --backend=auto|ollama|openai --context_tokens=N (any llm.json field); --thinking=0 turns thinking off
##
## Settings come from user://llm.json; flags override them.
## Exit codes: 0 ok, 1 LLM or HTTP error, 2 bad arguments or data.

var _client: OpenAiClient


func _initialize() -> void:
	_run()


func _run() -> void:
	var options: Dictionary = _parse_options()
	var question: String = options.get("question", "")
	if question == "":
		_fail(2, "Give a question: -- --question=\"...\"")
		return

	var db: CardDb = CardDb.load_default()
	if not db.errors.is_empty():
		_fail(2, "Data problems:\n  " + "\n  ".join(db.errors))
		return
	var spread: Spread = Spread.from_db(db, options.get("spread", "three_card"))
	if spread == null:
		_fail(2, "Unknown spread '%s'" % options.get("spread"))
		return

	var config: LlmConfig = LlmConfig.load_from()
	config.apply(options)
	_client = OpenAiClient.new(config)
	root.add_child(_client)
	var pipeline: ReadingPipeline = ReadingPipeline.new(_client)
	var use_llm: bool = not options.has("no-llm")

	# 1. Classify
	var classification: Dictionary = ReadingPipeline.DEFAULT_CLASSIFICATION.duplicate()
	if use_llm and str(options.get("classify", "1")) != "0":
		print("Classifying the question with %s ..." % config.endpoint)
		classification = await pipeline.classify(question)
		if _client.last_error != "":
			_fail(1, "Classify failed: %s" % _client.last_error)
			return
		print("Using model %s" % await _client.resolve_model())

	# 2. Draw
	var layout: Array[Dictionary]
	if options.has("cards"):
		var cards: Array[int] = _parse_cards(str(options["cards"]), db)
		if cards.size() != spread.size():
			_fail(2, "--cards needs %d valid cards for %s" % [spread.size(), spread.id])
			return
		layout = spread.lay_out(cards)
	else:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		if options.has("seed"):
			rng.seed = int(options["seed"])
		else:
			rng.randomize()
		var deck: Array[int] = Deck.shuffled(rng)
		if options.has("cut"):
			deck = Deck.cut(deck, int(options["cut"]))
		layout = spread.deal(deck)

	# 3. Compute
	var summary: ReadingSummary = ReadingSummary.build(db, spread, layout, question, classification)
	print("")
	print("Question: %s" % question)
	print("Classification: %s" % JSON.stringify(classification))
	print("")
	print(summary.to_prompt_text())
	if options.has("json"):
		print("")
		print(summary.to_json())
	if options.has("prompt"):
		for message: Dictionary in ReadingPipeline.reading_messages(summary):
			print("")
			print("===== %s =====" % message["role"])
			print(message["content"])
	if not use_llm:
		quit(0)
		return

	# 4. Read (streamed)
	print("")
	print("===== Reading =====")
	_client.token.connect(func(text: String) -> void: printraw(text))
	if options.has("thinking"):
		_client.reasoning.connect(func(text: String) -> void: printraw(text))
	var started: int = Time.get_ticks_msec()
	var reading: String = await pipeline.read(summary)
	print("")
	if _client.last_error != "":
		_fail(1, "Reading failed: %s" % _client.last_error)
		return
	print("(%.1f s, %d characters, tokens: %s)" % [
		(Time.get_ticks_msec() - started) / 1000.0, reading.length(),
		JSON.stringify(_client.last_usage) if not _client.last_usage.is_empty() else "not reported",
	])

	# 5. Critique (optional)
	if config.critique or options.has("critique"):
		print("")
		print("===== Critique =====")
		var verdict: Dictionary = await pipeline.critique(summary, reading)
		if _client.last_error != "":
			_fail(1, "Critique failed: %s" % _client.last_error)
			return
		if verdict["passed"]:
			print("PASS")
		else:
			print("REVISE: %s" % verdict["reason"])
			print("")
			print(verdict["reading"])
	quit(0)


func _parse_cards(text: String, db: CardDb) -> Array[int]:
	var cards: Array[int] = []
	for part: String in text.split(",", false):
		var token: String = part.strip_edges()
		if token.is_valid_int() and CardIndex.is_valid(token.to_int()):
			cards.append(token.to_int())
		elif not db.by_id(token).is_empty():
			cards.append(int(db.by_id(token)["index"]))
		else:
			print("Unknown card '%s'" % token)
			return []
	return cards


func _fail(code: int, message: String) -> void:
	printerr(message)
	quit(code)


## --key=value, or a bare --flag (stored as true). Values with "=" inside are kept whole.
func _parse_options() -> Dictionary:
	var options: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--"):
			continue
		var body: String = argument.trim_prefix("--")
		var split: int = body.find("=")
		if split < 0:
			options[body] = true
		else:
			options[body.left(split)] = body.substr(split + 1)
	return options
