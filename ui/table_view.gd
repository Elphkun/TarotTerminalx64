class_name TableView
extends Control
## The reading table: the pile, the cut fan, and the spread's cards at the positions
## from spreads.json (normalized x/y, optional rotation). Presentation only: it never
## changes the reading, it just shows what ReadingSession did.

## A card in the spread was clicked.
signal slot_pressed(slot: int)
## A card in the cut fan was clicked: cut with this many cards lifted.
signal cut_chosen(at: int)
## The deck was clicked (set_pile_clickable): fan it to pick cards from.
signal pile_pressed()
## A card in the picking fan was clicked: the card at this place in the deck (0 = top).
signal fan_card_picked(at: int)

const PILE_X: float = 0.1
const DEAL_TIME: float = 0.45
const DEAL_STAGGER: float = 0.18
const RIFFLE_TIME: float = 0.09
const FAN_TIME: float = 0.35
## The picking fan peeks up from the table's bottom edge: this share of each card shows,
## and a hovered card rises to show this much more.
const PICK_PEEK: float = 0.55
const PICK_LIFT: float = 0.4
## Half of one card's glow while the reader studies the spread.
const STUDY_TIME: float = 0.7
## Wait before the glow starts, so cards still turning over finish first.
const STUDY_DELAY: float = 1.0
## Card height as a share of the table's height.
const CARD_HEIGHT: float = 0.42
## Every position sits this far above its y, leaving room for the labels underneath.
const SLOT_RAISE: float = 20.0
const LABEL_GAP: float = 6.0
const LIGHTBOX_TIME: float = 0.18
## The wheel zooms the table by this much a notch, from the whole table up to MAX_ZOOM.
const ZOOM_STEP: float = 1.15
const MAX_ZOOM: float = 4.0

var db: CardDb
var images: DeckImages
## Scales every animation; 0 makes them instant (tests).
var motion: float = 1.0
## True from the last card turned until the reading's first words (set_studying).
var studying: bool = false
## True while the question is being weighed (set_weighing).
var weighing: bool = false
## The slot shown enlarged over the table (show_lightbox), or -1.
var lightbox_slot: int = -1

var _spread: Spread
var _summary: ReadingSummary
var _lightbox: Control
var _lightbox_card: CardView
var _lightbox_caption: Label
var _study_tween: Tween
var _weigh_tween: Tween
var _pile: Array[CardView] = []
var _fan: Array[CardView] = []
var _slots: Array[CardView] = []
var _labels: Array[Label] = []
var _marks: Array[Label] = []
## Holds the cards and labels; scaled and moved to zoom and pan (the wheel and the middle
## button). The enlarged card (lightbox) sits outside it, unzoomed.
var _content: Control
## The user's zoom, over the fitted view (1: the whole spread).
var zoom: float = 1.0
## What the spread puts on the table (SpreadLayout.bounds), and the scale that shows all
## of it: below 1 for a spread laid out past the table's edges.
var _bounds: Rect2 = Rect2()
var _fit: float = 1.0
var _panning: bool = false


func _init() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_PASS
	_content = Control.new()
	_content.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_content)
	resized.connect(_relayout)


## Zooms by `factor` keeping the table point under `at` (in the table's own coordinates)
## where it is. Never further out than the whole spread.
func zoom_at(at: Vector2, factor: float) -> void:
	var before: float = _fit * zoom
	zoom = clampf(zoom * factor, 1.0, MAX_ZOOM)
	var spot: Vector2 = (at - _content.position) / before
	_set_view(at - spot * _fit * zoom)


## The scale cards are drawn at: below 1 when the spread reaches past the table.
func view_scale() -> float:
	return _fit * zoom


## Moves the zoomed table by `delta`, within its edges.
func pan_by(delta: Vector2) -> void:
	_set_view(_content.position + delta)


## Back to the whole table.
func reset_view() -> void:
	zoom = 1.0
	_set_view(Vector2.ZERO)


## Scales the cards to the current zoom and moves them by `offset`, kept so the spread
## covers the table where it is bigger than it, and is centred where it is smaller.
func _set_view(offset: Vector2) -> void:
	var scale_now: float = _fit * zoom
	_content.scale = Vector2(scale_now, scale_now)
	var area: Rect2 = _bounds if _bounds.has_area() else Rect2(Vector2.ZERO, size)
	var placed: Vector2 = offset
	for axis: int in 2:
		var low: float = size[axis] - area.end[axis] * scale_now
		var high: float = -area.position[axis] * scale_now
		placed[axis] = clampf(offset[axis], low, high) if low <= high else (low + high) / 2.0
	_content.position = placed


## The wheel zooms and the middle button pans, while the mouse is over the table (the
## cards take clicks themselves, so this listens before them). A middle double-click
## shows the whole table again.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or lightbox_slot >= 0:
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	var motion_event: InputEventMouseMotion = event as InputEventMouseMotion
	if motion_event != null:
		if _panning:
			pan_by(motion_event.relative / get_global_transform_with_canvas().get_scale())
			get_viewport().set_input_as_handled()
		return
	if button == null:
		return
	if button.button_index == MOUSE_BUTTON_MIDDLE and not button.pressed:
		if _panning:
			_panning = false
			get_viewport().set_input_as_handled()
		return
	if not _mouse_over_table():
		return
	var at: Vector2 = get_global_transform_with_canvas().affine_inverse() * button.position
	match button.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				zoom_at(at, ZOOM_STEP if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP)
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_MIDDLE:
			if button.double_click:
				reset_view()
			else:
				_panning = true
			get_viewport().set_input_as_handled()


## True when the control under the mouse is this table or one of its cards (not a
## dialog or menu above it).
func _mouse_over_table() -> bool:
	var hovered: Control = get_viewport().gui_get_hovered_control()
	return hovered != null and (hovered == self or is_ancestor_of(hovered))


## Shows the empty spread positions and a full pile, ready for a new reading.
func set_spread(spread: Spread) -> void:
	clear()
	reset_view()
	_spread = spread
	for i: int in spread.size():
		var position_data: Dictionary = spread.positions[i]
		var label: Label = Label.new()
		label.text = Spread.title(Spread.label(position_data))
		# Close-packed spreads number the cards instead (CardView.badge).
		label.visible = not spread.compact_labels
		label.theme_type_variation = ReaderTheme.MUTED_LABEL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.tooltip_text = str(position_data.get("meaning", ""))
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		_content.add_child(label)
		_labels.append(label)
		var mark: Label = Label.new()
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(mark)
		_marks.append(mark)
	_build_pile()
	_relayout()


func clear() -> void:
	set_studying(false)
	set_weighing(false)
	hide_lightbox()
	_summary = null
	for view: CardView in _pile + _fan + _slots:
		if view != null:  # a picked card leaves a gap in the fan
			view.queue_free()
	for label: Label in _labels + _marks:
		label.queue_free()
	_pile.clear()
	_fan.clear()
	_slots.clear()
	_labels.clear()
	_marks.clear()


func set_images(deck_images: DeckImages) -> void:
	images = deck_images
	for view: CardView in _pile + _fan + _slots:
		if view != null:
			view.set_images(images)
	# A new deck may have a different card shape.
	_relayout()


## The width / height of a card on this table: the deck's own shape, or the default.
func card_aspect() -> float:
	return images.aspect if images != null else CardView.ASPECT


## A short shuffle: the pile's cards jostle and settle.
func riffle() -> void:
	var home: Vector2 = _pile_position()
	for i: int in _pile.size():
		var view: CardView = _pile[i]
		var tween: Tween = view.create_tween()
		for step: int in 4:
			var jolt: Vector2 = Vector2(randf_range(-14, 14), randf_range(-6, 6))
			tween.tween_property(view, "position", home + _pile_offset(i) + jolt, RIFFLE_TIME * motion)
		tween.tween_property(view, "position", home + _pile_offset(i), RIFFLE_TIME * motion)


func is_fanned() -> bool:
	return not _fan.is_empty()


## Lets the top of the deck be clicked (pile_pressed), to fan it and pick cards.
func set_pile_clickable(on: bool) -> void:
	for i: int in _pile.size():
		var view: CardView = _pile[i]
		var top: bool = on and i == _pile.size() - 1
		view.clickable = top
		view.mouse_filter = Control.MOUSE_FILTER_STOP if top else Control.MOUSE_FILTER_IGNORE
		view.tooltip_text = "Click to fan the deck and pick your cards face down" if top else ""


## The top card of the deck (for tests).
func pile_top() -> CardView:
	return _pile[_pile.size() - 1] if not _pile.is_empty() else null


## Spreads `count` backs across the table so one can be clicked: to cut there, or with
## `picking`, to take that card (fan_card_picked).
func show_fan(count: int = CardIndex.DECK_SIZE, picking: bool = false) -> void:
	hide_fan()
	var height: float = _card_height() * 0.8
	var width: float = height * card_aspect()
	var left: float = size.x * 0.04
	var step: float = (size.x * 0.92 - width) / maxf(1, count - 1)
	# Cutting: across the middle. Picking: along the bottom edge, out of the way of the
	# positions the picked cards go to.
	var top: float = size.y * 0.5 - height / 2.0
	if picking:
		top = size.y - height * PICK_PEEK
	_set_pile_and_labels_visible(false)
	for i: int in count:
		var view: CardView = CardView.new(-1, images)
		view.set_height(height)
		view.position = _pile_position()
		view.lift_on_hover = true
		if picking:
			view.lift = height * PICK_LIFT
			view.tooltip_text = "Pick this card"
			view.pressed.connect(func(_v: CardView) -> void: fan_card_picked.emit(i))
		else:
			view.tooltip_text = "Cut here (%d cards lifted)" % i if i > 0 else "Leave the deck uncut"
			view.pressed.connect(func(_v: CardView) -> void: cut_chosen.emit(i))
		_content.add_child(view)
		_fan.append(view)
		view.create_tween().tween_property(view, "position", Vector2(left + step * i, top),
				FAN_TIME * motion).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func hide_fan() -> void:
	for view: CardView in _fan:
		if view != null:
			view.queue_free()
	_fan.clear()
	_set_pile_and_labels_visible(true)


## Moves the picking fan's card at `at` to position `slot`, face down, as that slot's
## card (`card_index`). The rest of the fan stays, with a gap where it was.
func take_from_fan(at: int, slot: int, card_index: int) -> void:
	if at < 0 or at >= _fan.size() or _fan[at] == null:
		return
	var view: CardView = _fan[at]
	_fan[at] = null  # keeps the other cards' places
	for connection: Dictionary in view.pressed.get_connections():
		view.pressed.disconnect(connection["callable"])
	if view.lift_on_hover and view._hovered:
		view._set_hovered(false)
	view.lift_on_hover = false
	view.index = card_index
	view.card_data = db.card(card_index)
	view.set_height(_card_height())
	view.pressed.connect(func(_v: CardView) -> void: slot_pressed.emit(slot))
	var position_data: Dictionary = _spread.positions[slot]
	view.tooltip_text = "%d. %s: %s" % [slot + 1, Spread.title(Spread.label(position_data)),
			position_data.get("meaning", "")]
	# Under the fan, so a picked card never covers the cards still to pick from.
	var first_fan: int = _content.get_child_count()
	for other: CardView in _fan:
		if other != null:
			first_fan = mini(first_fan, other.get_index())
	_content.move_child(view, mini(first_fan, _content.get_child_count() - 1))
	while _slots.size() <= slot:
		_slots.append(null)
	_slots[slot] = view
	var tween: Tween = view.create_tween()
	tween.tween_property(view, "position", _slot_position(slot), DEAL_TIME * motion) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(view, "rotation_degrees", _slot_rotation(slot), DEAL_TIME * motion)
	# The table may have been resized while the card flew (the last pick changes the
	# status line): land where the position is now.
	tween.tween_callback(func() -> void: view.position = _slot_position(slot))
	if _spread.compact_labels:
		tween.tween_callback(func() -> void: view.badge = str(slot + 1))


## After the last pick: the rest of the fan goes back, the deck shows what is left.
func end_pick() -> void:
	hide_fan()
	for i: int in mini(_slots.size(), _pile.size() - 2):
		_pile[_pile.size() - 1 - i].visible = false
	set_pile_clickable(false)


## Deals face down from the pile to each position, one after another.
func deal(layout: Array[Dictionary]) -> void:
	hide_fan()
	for i: int in layout.size():
		var index: int = layout[i]["card"]
		# -1: an empty position, for the querent's own card (ReadingSession.place).
		var view: CardView = CardView.new(index, images, db.card(index) if index >= 0 else {})
		view.empty = index < 0
		view.set_height(_card_height())
		view.position = _pile_position()
		view.pressed.connect(func(_v: CardView) -> void: slot_pressed.emit(i))
		var position_data: Dictionary = _spread.positions[i]
		view.tooltip_text = "%d. %s: %s" % [i + 1, Spread.title(Spread.label(position_data)),
				position_data.get("meaning", "")]
		_content.add_child(view)
		_slots.append(view)
		var tween: Tween = view.create_tween()
		tween.tween_interval(i * DEAL_STAGGER * motion)
		tween.tween_property(view, "position", _slot_position(i), DEAL_TIME * motion) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(view, "rotation_degrees", _slot_rotation(i),
				DEAL_TIME * motion)
		# The number appears once the card has landed (drawn upright against its rotation).
		if _spread.compact_labels:
			tween.tween_callback(func() -> void: view.badge = str(i + 1))
	# One card per position leaves the pile, but the rest of the deck stays in view.
	for i: int in mini(layout.size(), _pile.size() - 2):
		_pile[_pile.size() - 1 - i].visible = false


func turn(slot: int) -> void:
	if slot < _slots.size():
		_slots[slot].flip_up(0.0, motion)


## Puts `index` in an (empty or filled) position, face up.
func set_slot_card(slot: int, index: int) -> void:
	if slot < _slots.size():
		_slots[slot].set_card(index, db.card(index), motion)


func is_face_up(slot: int) -> bool:
	return slot < _slots.size() and _slots[slot].face_up


func dealt_count() -> int:
	return _slots.size()


## The view in `slot`, for tests and screenshots.
func slot_view(slot: int) -> CardView:
	return _slots[slot]


func fan_view(at: int) -> CardView:
	return _fan[at]


## Marks each turned card with its dignity, from Dignities.compute.
func show_dignities(summary: ReadingSummary) -> void:
	_summary = summary
	for i: int in mini(summary.positions.size(), _marks.size()):
		var dignity: Dictionary = summary.positions[i]["dignity"]
		var state: String = dignity["state"]
		_marks[i].text = {Dignities.WELL: "▲ well-dignified", Dignities.ILL: "▼ ill-dignified"} \
				.get(state, "· neutral")
		_marks[i].add_theme_color_override("font_color", ReaderTheme.dignity_color(state))
		_marks[i].tooltip_text = Dignities.describe(dignity)
		_marks[i].mouse_filter = Control.MOUSE_FILTER_PASS
		if _spread != null and _spread.compact_labels and i < _slots.size():
			_slots[i].mark_text = {Dignities.WELL: "▲", Dignities.ILL: "▼"}.get(state, "·")
			_slots[i].mark_color = ReaderTheme.dignity_color(state)
			_slots[i].tooltip_text += "\n" + Dignities.describe(dignity)


## While the reader studies the spread: a glow passes from card to card until stopped.
## With motion 0 (tests) only the flag changes.
func set_studying(on: bool) -> void:
	studying = on
	if _study_tween != null:
		_study_tween.kill()
		_study_tween = null
	for view: CardView in _slots:
		view.glow = 0.0
	if not on or _slots.is_empty() or motion <= 0.0:
		return
	# Let the last cards finish turning over before the glow starts.
	_study_tween = create_tween()
	_study_tween.tween_interval(STUDY_DELAY * motion)
	_study_tween.tween_callback(_start_study_loop)


func _start_study_loop() -> void:
	if not studying:
		return
	_study_tween = _glow_loop(_slots)


## While the question is weighed (and the model loads): the glow passes over the cards or
## empty positions on the table, or pulses on the deck when none are laid.
func set_weighing(on: bool) -> void:
	weighing = on
	if _weigh_tween != null:
		_weigh_tween.kill()
		_weigh_tween = null
	var views: Array[CardView] = _slots.duplicate()
	if views.is_empty() and not _pile.is_empty():
		views.append(pile_top())
	for view: CardView in views:
		view.glow = 0.0
	if on and motion > 0.0 and not views.is_empty():
		_weigh_tween = _glow_loop(views)


func _glow_loop(views: Array[CardView]) -> Tween:
	var tween: Tween = create_tween().set_loops()
	for view: CardView in views:
		tween.tween_property(view, "glow", 1.0, STUDY_TIME * motion) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(view, "glow", 0.0, STUDY_TIME * motion) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween


## Shows a turned card large over the table, upright, with its position and dignity
## underneath. Clicking the card (or the dimmed table, or Esc) lays it down again.
func show_lightbox(slot: int) -> void:
	hide_lightbox()
	if slot < 0 or slot >= _slots.size() or not _slots[slot].face_up:
		return
	lightbox_slot = slot
	var source: CardView = _slots[slot]
	_lightbox = Control.new()
	_lightbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lightbox.mouse_filter = Control.MOUSE_FILTER_STOP
	_lightbox.gui_input.connect(_on_lightbox_input)
	add_child(_lightbox)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(ReaderTheme.BACKGROUND, 0.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lightbox.add_child(shade)

	_lightbox_card = CardView.new(source.index, images, source.card_data)
	_lightbox_card.face_up = true
	# No number or dignity discs here: they grow with the card and would cover its art.
	# The caption underneath carries both.
	_lightbox_card.tooltip_text = "Click to lay the card down"
	_lightbox_card.pressed.connect(func(_v: CardView) -> void: hide_lightbox())
	_lightbox.add_child(_lightbox_card)

	_lightbox_caption = Label.new()
	_lightbox_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lightbox_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lightbox_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lightbox_caption.text = _caption(slot)
	if _summary != null and slot < _summary.positions.size():
		_lightbox_caption.add_theme_color_override("font_color",
				ReaderTheme.dignity_color(_summary.positions[slot]["dignity"]["state"]))
	_lightbox.add_child(_lightbox_caption)
	_layout_lightbox()

	if motion > 0.0:
		_lightbox.modulate.a = 0.0
		_lightbox_card.scale = Vector2(0.85, 0.85)
		var tween: Tween = _lightbox.create_tween().set_parallel()
		tween.tween_property(_lightbox, "modulate:a", 1.0, LIGHTBOX_TIME * motion)
		tween.tween_property(_lightbox_card, "scale", Vector2.ONE, LIGHTBOX_TIME * motion) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func hide_lightbox() -> void:
	if _lightbox != null:
		_lightbox.queue_free()
	_lightbox = null
	_lightbox_card = null
	_lightbox_caption = null
	lightbox_slot = -1


## The enlarged card, while the lightbox is open (for tests).
func lightbox_card() -> CardView:
	return _lightbox_card


func _caption(slot: int) -> String:
	if _summary == null or slot >= _summary.positions.size():
		return ""
	var entry: Dictionary = _summary.positions[slot]
	return "%d. %s · %s · %s" % [slot + 1, Spread.title(entry["name"]), entry["card"]["name"],
			entry["dignity"]["state"]]


func _layout_lightbox() -> void:
	if _lightbox_card == null:
		return
	var caption_room: float = 56.0
	var height: float = minf(size.y * 0.9 - caption_room, size.x * 0.9 / card_aspect())
	_lightbox_card.set_height(maxf(60.0, height))
	var card_size: Vector2 = _lightbox_card.size
	var top: float = (size.y - card_size.y - caption_room) / 2.0
	_lightbox_card.position = Vector2((size.x - card_size.x) / 2.0, top)
	_lightbox_caption.size = Vector2(size.x * 0.9, caption_room)
	_lightbox_caption.position = Vector2(size.x * 0.05, top + card_size.y + 8.0)


## A click on the dimmed table (outside the card) also lays the card down.
func _on_lightbox_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		hide_lightbox()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if _lightbox != null and event.is_action_pressed("ui_cancel"):
		hide_lightbox()
		get_viewport().set_input_as_handled()


func highlight(slot: int) -> void:
	for i: int in _slots.size():
		_slots[i].highlighted = i == slot


func _set_pile_and_labels_visible(shown: bool) -> void:
	for view: CardView in _pile:
		view.visible = shown
	for label: Label in _labels + _marks:
		label.visible = shown and not (_spread != null and _spread.compact_labels)


func _build_pile() -> void:
	for i: int in 6:
		var view: CardView = CardView.new(-1, images)
		view.clickable = false
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Only answers while set_pile_clickable makes it the clickable top card.
		view.pressed.connect(func(_v: CardView) -> void: pile_pressed.emit())
		_content.add_child(view)
		_pile.append(view)


func _relayout() -> void:
	_layout_lightbox()
	_content.size = size
	_bounds = SpreadLayout.bounds(_spread, size, card_aspect())
	_fit = SpreadLayout.fit_scale(_bounds, size)
	_set_view(_content.position)
	if _spread == null:
		return
	var height: float = _card_height()
	for i: int in _pile.size():
		_pile[i].set_height(height)
		_pile[i].position = _pile_position() + _pile_offset(i)
	for i: int in _slots.size():
		_slots[i].set_height(height)
		_slots[i].position = _slot_position(i)
		_slots[i].rotation_degrees = _slot_rotation(i)
	for i: int in _labels.size():
		var centre: Vector2 = _slot_centre(i)
		var width: float = height * card_aspect() + 60
		# Under the card's lowest point, which a turned card reaches with a corner.
		var angle: float = deg_to_rad(_slot_rotation(i))
		var below: float = (absf(height * card_aspect() * sin(angle)) + absf(height * cos(angle))) / 2.0
		_labels[i].size = Vector2(width, 24)
		_labels[i].position = Vector2(centre.x - width / 2.0, centre.y + below + LABEL_GAP)
		_marks[i].size = Vector2(width, 24)
		_marks[i].position = _labels[i].position + Vector2(0, 22)


func _card_height() -> float:
	return card_height_for(size, card_aspect(), _spread)


## How tall cards are on a table of `table_size` for `spread` (null: the default), at
## card shape `aspect`. Shared with the spread designer, so it places cards exactly as
## the table does.
static func card_height_for(table_size: Vector2, aspect: float, spread: Spread) -> float:
	var share: float = CARD_HEIGHT
	var columns: float = 4.0
	if spread != null:
		share = spread.card_height if spread.card_height > 0.0 else CARD_HEIGHT
		columns = spread.columns if spread.columns > 0.0 else spread.size() + 1.5
	var by_height: float = table_size.y * share
	var by_width: float = table_size.x / columns / aspect
	return maxf(60.0, minf(by_height, by_width))


## Where a position at normalized (x, y) has its centre on a table of `table_size`.
## Positions are laid out to the right of the pile.
static func slot_centre_for(normalized: Vector2, table_size: Vector2) -> Vector2:
	var left: float = table_size.x * (PILE_X * 2.0)
	return Vector2(left + normalized.x * (table_size.x - left), normalized.y * table_size.y - SLOT_RAISE)


## The inverse of slot_centre_for: the normalized (x, y) of a centre on the table.
static func normalized_for(centre: Vector2, table_size: Vector2) -> Vector2:
	var left: float = table_size.x * (PILE_X * 2.0)
	return Vector2((centre.x - left) / (table_size.x - left), (centre.y + SLOT_RAISE) / table_size.y)


## The pile's top-left corner, for cards `height` tall at shape `aspect`.
static func pile_position_for(table_size: Vector2, height: float, aspect: float) -> Vector2:
	return Vector2(table_size.x * PILE_X - height * aspect / 2.0,
			table_size.y * 0.5 - height / 2.0 - SLOT_RAISE)


func _slot_centre(i: int) -> Vector2:
	var position_data: Dictionary = _spread.positions[i]
	return slot_centre_for(Vector2(float(position_data.get("x", 0.5)),
			float(position_data.get("y", 0.5))), size)


func _slot_position(i: int) -> Vector2:
	var height: float = _card_height()
	return _slot_centre(i) - Vector2(height * card_aspect(), height) / 2.0


func _slot_rotation(i: int) -> float:
	return float(_spread.positions[i].get("rotation", 0.0))


func _pile_position() -> Vector2:
	return pile_position_for(size, _card_height(), card_aspect())


func _pile_offset(i: int) -> Vector2:
	return Vector2(i * 1.5, -i * 1.5)
