class_name CardPickerDialog
extends Control
## Own cards: which card did you lay in this position? A filter box over the 78 cards.
## Typing narrows by name ("seven wands", "tower") or by a short code: a rank and a suit
## letter ("7w", "aw" or "1w" for the Ace, "pw" "nw" "qw" "kw" for the courts; w c s p)
## or a trump's number ("16"). Cards already laid elsewhere are greyed out.

## The querent named `card` for `slot`.
signal card_chosen(slot: int, card: int)

const SUIT_LETTERS: Dictionary = {"wands": "w", "cups": "c", "swords": "s", "pentacles": "p"}
const COURT_LETTERS: Dictionary = {"page": "p", "knight": "n", "queen": "q", "king": "k"}

var db: CardDb
var title_label: Label
var filter_input: LineEdit
var list: ItemList
var hint: Label
var choose_button: Button
var cancel_button: Button

var _slot: int = -1
var _used: Array[int] = []
## Card index for each row shown, in order.
var _shown: Array[int] = []
## Card index -> words it can be found by.
var _keys: Dictionary = {}


func _init(card_db: CardDb) -> void:
	db = card_db
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	for index: int in CardIndex.DECK_SIZE:
		_keys[index] = search_keys(db.card(index))
	_build()


## Asks for the card in `slot`. `used` are the cards laid elsewhere; `current` is the
## card already in this slot (-1 for none).
func open(slot: int, position_title: String, used: Array[int], current: int = -1) -> void:
	_slot = slot
	_used = used
	title_label.text = "Position %d: %s" % [slot + 1, position_title]
	filter_input.text = ""
	_refresh()
	visible = true
	if is_inside_tree():
		filter_input.grab_focus()
	var row: int = _shown.find(current)
	if row >= 0:
		list.select(row)
		list.ensure_current_is_visible()
	_update_choose()


func close() -> void:
	visible = false


## The cards shown for the filter, in deck order (for tests).
func shown() -> Array[int]:
	return _shown


func set_filter(text: String) -> void:
	filter_input.text = text
	_refresh()


## Picks the selected card, or the first card the filter leaves when none is selected.
func choose() -> void:
	var picks: PackedInt32Array = list.get_selected_items()
	var row: int = picks[0] if not picks.is_empty() else _first_free_row()
	if row < 0 or row >= _shown.size() or _used.has(_shown[row]):
		return
	close()
	card_chosen.emit(_slot, _shown[row])


## The words a card can be found by: its name, its short code, its number.
static func search_keys(card: Dictionary) -> PackedStringArray:
	var keys: PackedStringArray = [str(card.get("name", "")).to_lower()]
	var suit: String = SUIT_LETTERS.get(str(card.get("suit", "")), "")
	match str(card.get("type", "")):
		"trump":
			keys.append(str(int(card.get("number", -1))))
		"pip":
			var rank: int = int(card.get("rank", 0))
			keys.append("%d%s" % [rank, suit])
			if rank == 1:
				keys.append("a" + suit)
		"court":
			keys.append(str(COURT_LETTERS.get(str(card.get("rws_rank", "")), "")) + suit)
	return keys


## True when the filter is the card's short code or number ("7w", "16").
static func is_code(keys: PackedStringArray, filter: String) -> bool:
	return keys.slice(1).has(filter.strip_edges().to_lower().replace(" ", ""))


## True when every word of `filter` is found in the card's name, or the filter is the
## card's short code or number.
static func matches(keys: PackedStringArray, filter: String) -> bool:
	var text: String = filter.strip_edges().to_lower()
	if text == "":
		return true
	if is_code(keys, text):
		return true
	for word: String in text.split(" ", false):
		if word != "of" and not keys[0].contains(word):
			return false
	return true


func _refresh() -> void:
	list.clear()
	_shown.clear()
	# A code or number ("nc", "16") shows just its card, not every name containing it.
	var by_code: bool = false
	for index: int in CardIndex.DECK_SIZE:
		by_code = by_code or is_code(_keys[index], filter_input.text)
	for index: int in CardIndex.DECK_SIZE:
		if by_code and not is_code(_keys[index], filter_input.text):
			continue
		if not matches(_keys[index], filter_input.text):
			continue
		_shown.append(index)
		var used: bool = _used.has(index)
		list.add_item(db.card(index)["name"] + ("  (laid already)" if used else ""))
		list.set_item_disabled(list.item_count - 1, used)
	hint.text = "No card matches." if _shown.is_empty() else \
			"Type a name, or a code: 7w, aw, kp, 16. Enter picks the first match."
	_update_choose()


func _first_free_row() -> int:
	for row: int in _shown.size():
		if not _used.has(_shown[row]):
			return row
	return -1


func _update_choose() -> void:
	choose_button.disabled = _first_free_row() < 0 and list.get_selected_items().is_empty()


func _build() -> void:
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var dialog: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = ReaderTheme.panel()
	style.bg_color = ReaderTheme.BACKGROUND.lightened(0.04)
	style.border_color = Color(ReaderTheme.BRASS, 0.5)
	style.set_content_margin_all(22)
	dialog.add_theme_stylebox_override("panel", style)
	dialog.custom_minimum_size = Vector2(460, 520)
	centre.add_child(dialog)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	dialog.add_child(column)

	var heading: Label = Label.new()
	heading.text = "Which card did you lay here?"
	heading.theme_type_variation = ReaderTheme.TITLE
	column.add_child(heading)
	title_label = Label.new()
	title_label.theme_type_variation = ReaderTheme.HEADING
	column.add_child(title_label)
	filter_input = LineEdit.new()
	filter_input.placeholder_text = "Find a card"
	filter_input.clear_button_enabled = true
	filter_input.text_changed.connect(func(_t: String) -> void: _refresh())
	filter_input.text_submitted.connect(func(_t: String) -> void: choose())
	column.add_child(filter_input)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(func(_i: int) -> void: _update_choose())
	list.item_activated.connect(func(_i: int) -> void: choose())
	column.add_child(list)
	hint = Label.new()
	hint.theme_type_variation = ReaderTheme.MUTED_LABEL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(close)
	buttons.add_child(cancel_button)
	choose_button = Button.new()
	choose_button.text = "Choose"
	choose_button.pressed.connect(choose)
	buttons.add_child(choose_button)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
