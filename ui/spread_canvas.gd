class_name SpreadCanvas
extends Control
## The spread designer's table: the draft's positions as card backs, placed with the
## reading table's own geometry (TableView's statics), so what you see is where the
## cards land. Transform controls in the manner of an image editor:
## - drag a card to move it (Shift: snap its centre to the grid, which starts at the
##   deck's centre; Alt: straight across or down; arrow keys nudge);
## - Ctrl+drag, or drag the knob above the selected card, to turn it in eighths;
## - drag from one of a card's eight nodes onto another card for a dignity line;
## - double-click empty table to add a card; Delete removes the selected card or line;
## - the wheel zooms, the middle button pans, a middle double-click fits the table again.

## The draft changed (moved, turned, added, removed, connected).
signal edited()
## The selection changed: a card's index, or a line's index, or -1 for neither.
signal selection_changed(card: int, line: int)
## A card was dropped onto another: the designer offers to lay it "over" that card.
signal dropped_on(card: int, under: int)
## A card was asked for, but the spread already has as many as it may.
signal full()

enum Drag { NONE, MOVE, ROTATE, CONNECT }

## Node and knob grab radius, in screen pixels.
const NODE_RADIUS: float = 7.0
const KNOB_DISTANCE: float = 26.0
const LINE_GRAB: float = 6.0
## The glowing ring round a card that a dignity line is dragged from (or dropped on):
## this far outside its edge and this far inside, in screen pixels at any zoom.
const RING_OUTSIDE: float = 14.0
const RING_INSIDE: float = 3.0
const NUDGE: float = 0.005
const NUDGE_BIG: float = 0.05
## The wheel zooms by this much a notch, between these multiples of the fitted size.
const ZOOM_STEP: float = 1.15
const MIN_ZOOM: float = 0.2
const MAX_ZOOM: float = 4.0
## The grid sizes offered, in table pixels (at the designer's table shape).
const GRID_SIZES: Array[int] = [16, 32, 64]

var draft: SpreadDraft
var images: DeckImages
## The table shape being designed on: one of SpreadLayout.TABLE_SIZES.
var table_size: Vector2 = SpreadLayout.TABLE_SIZES[0]:
	set(value):
		table_size = value
		_zoom = 1.0
		_pan = Vector2.ZERO
		_frame = Rect2()
		refresh()
## Shift-drag snaps a card's centre to this grid (table pixels), from the deck's centre.
var grid: int = 32:
	set(value):
		grid = value
		_overlay.queue_redraw()
var selected: int = -1
var selected_line: int = -1

var _table: Control
var _overlay: Control
var _cards: Array[CardView] = []
var _spread: Spread
var _hovered: int = -1
## The card whose glowing ring the mouse is in, or -1.
var _ring_hovered: int = -1
var _drag: Drag = Drag.NONE
var _drag_from: int = -1
var _drag_point: Vector2 = Vector2.ZERO
var _grab_offset: Vector2 = Vector2.ZERO
var _drag_start: Vector2 = Vector2.ZERO
var _start_angle: float = 0.0
var _start_rotation: float = 0.0
var _moved: bool = false
## Zoom over the fitted size, and how far the table is moved from its fitted place.
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _frame: Rect2 = Rect2()
var _panning: bool = false
## Shift is held while dragging a card: snap to the grid, and show it.
var _snapping: bool = false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_table = Control.new()
	_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table.draw.connect(_draw_table)
	add_child(_table)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_table.add_child(_overlay)
	resized.connect(_fit)


func set_draft(value: SpreadDraft) -> void:
	draft = value
	selected = -1
	selected_line = -1
	_zoom = 1.0
	_pan = Vector2.ZERO
	_frame = Rect2()
	refresh()


func set_images(value: DeckImages) -> void:
	images = value
	for view: CardView in _cards:
		view.set_images(images)
	refresh()


func aspect() -> float:
	return images.aspect if images != null else CardView.ASPECT


func card_height() -> float:
	return TableView.card_height_for(table_size, aspect(), _spread)


## A position's centre on the table.
func centre(i: int) -> Vector2:
	var entry: Dictionary = draft.position(i)
	return TableView.slot_centre_for(Vector2(float(entry.get("x", 0.5)), float(entry.get("y", 0.5))), table_size)


## The eight nodes of a card: corners and edge midpoints, turned with it.
func nodes(i: int) -> PackedVector2Array:
	var half: Vector2 = Vector2(card_height() * aspect(), card_height()) / 2.0
	var angle: float = deg_to_rad(draft.rotation_of(i))
	var points: PackedVector2Array = []
	for local: Vector2 in [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(1, 0),
			Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0)]:
		points.append(centre(i) + (local * half).rotated(angle))
	return points


## Where the rotate knob of card `i` sits, above its top edge.
func knob(i: int) -> Vector2:
	var angle: float = deg_to_rad(draft.rotation_of(i))
	var top: Vector2 = Vector2(0, -card_height() / 2.0 - KNOB_DISTANCE / _scale())
	return centre(i) + top.rotated(angle)


func contains(i: int, point: Vector2) -> bool:
	var local: Vector2 = (point - centre(i)).rotated(-deg_to_rad(draft.rotation_of(i)))
	var half: Vector2 = Vector2(card_height() * aspect(), card_height()) / 2.0
	return absf(local.x) <= half.x and absf(local.y) <= half.y


func _notification(what: int) -> void:
	# The hover glow goes when the mouse leaves the canvas.
	if what == NOTIFICATION_MOUSE_EXIT and _drag == Drag.NONE and (_hovered >= 0 or _ring_hovered >= 0):
		_hovered = -1
		_ring_hovered = -1
		_overlay.queue_redraw()


## The card whose glowing ring is under a table point, or -1: the band from
## RING_INSIDE inside its edge to RING_OUTSIDE outside it. A card lying on top wins,
## so the ring is never grabbed through another card.
func ring_at(point: Vector2, except: int = -1) -> int:
	var on: int = card_at(point, except)
	for i: int in range(draft.size() - 1, -1, -1):
		if i == except or (on >= 0 and on != i):
			continue
		var local: Vector2 = (point - centre(i)).rotated(-deg_to_rad(draft.rotation_of(i)))
		var half: Vector2 = Vector2(card_height() * aspect(), card_height()) / 2.0
		var outer: Vector2 = half + Vector2.ONE * RING_OUTSIDE / _scale()
		var inner: Vector2 = half - Vector2.ONE * RING_INSIDE / _scale()
		if absf(local.x) <= outer.x and absf(local.y) <= outer.y \
				and not (absf(local.x) < inner.x and absf(local.y) < inner.y):
			return i
		if on == i:
			return -1
	return -1


## Where a dignity line dragged from `from` would land: a card, or a card's ring.
func line_target(point: Vector2, from: int) -> int:
	var card: int = card_at(point, from)
	return card if card >= 0 else ring_at(point, from)


## Card i's outline grown by `grow` table pixels, closed, turned with the card.
func _outline(i: int, grow: float) -> PackedVector2Array:
	var half: Vector2 = Vector2(card_height() * aspect(), card_height()) / 2.0 + Vector2.ONE * grow
	var angle: float = deg_to_rad(draft.rotation_of(i))
	var points: PackedVector2Array = []
	for local: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
		points.append(centre(i) + (local * half).rotated(angle))
	return points


## The glow the reading table gives a card while the reader studies it (CardView.glow),
## here filling the grab ring: `strength` 0..1.
func _draw_glow(i: int, strength: float) -> void:
	for ring: int in 3:
		_overlay.draw_polyline(_outline(i, (2.0 + ring * 4.5) / _scale()),
				Color(ReaderTheme.BRASS.lightened(0.15), strength * (0.5 - ring * 0.16)),
				4.0 / _scale(), true)


## The topmost card under a table point, or -1. Later positions lie on top.
func card_at(point: Vector2, except: int = -1) -> int:
	for i: int in range(draft.size() - 1, -1, -1):
		if i != except and contains(i, point):
			return i
	return -1


## The two nodes a dignity line between cards a and b is drawn between: the closest pair.
func line_ends(a: int, b: int) -> PackedVector2Array:
	var best: PackedVector2Array = [centre(a), centre(b)]
	var best_distance: float = INF
	for from: Vector2 in nodes(a):
		for to: Vector2 in nodes(b):
			var distance: float = from.distance_squared_to(to)
			if distance < best_distance:
				best_distance = distance
				best = [from, to]
	return best


func line_at(point: Vector2) -> int:
	for k: int in draft.pairs().size():
		var ends: PackedVector2Array = _pair_ends(k)
		if ends.is_empty():
			continue
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, ends[0], ends[1])
		if closest.distance_to(point) <= LINE_GRAB / _scale():
			return k
	return -1


## A point in the canvas's own coordinates, on the table.
func to_table(point: Vector2) -> Vector2:
	return (point - _table.position) / _scale()


## The canvas point for a table point (tests click with it).
func to_canvas(point: Vector2) -> Vector2:
	return _table.position + point * _scale()


func select(card: int, line: int = -1) -> void:
	selected = card
	selected_line = line
	_sync_cards()
	selection_changed.emit(selected, selected_line)


## Rebuilds the cards from the draft (after any edit).
func refresh() -> void:
	if draft == null:
		return
	_spread = draft.spread()
	while _cards.size() < draft.size():
		var view: CardView = CardView.new(-1, images)
		view.clickable = false
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_table.add_child(view)
		_cards.append(view)
	while _cards.size() > draft.size():
		_cards.pop_back().free()
	_table.move_child(_overlay, -1)
	if selected >= draft.size():
		selected = -1
	if selected_line >= draft.pairs().size():
		selected_line = -1
	_fit()


func _sync_cards() -> void:
	var height: float = card_height()
	for i: int in _cards.size():
		var view: CardView = _cards[i]
		view.set_height(height)
		view.position = centre(i) - view.size / 2.0
		view.rotation_degrees = draft.rotation_of(i)
		view.badge = str(i + 1)
		view.highlighted = i == selected
	_table.queue_redraw()
	_overlay.queue_redraw()


func _scale() -> float:
	return _table.scale.x if _table.scale.x > 0.0 else 1.0


## The area the view fits: the table and every card, as of the last fit (reset_view).
## Kept while you work, so the view doesn't move under the mouse as cards are dragged.
func _frame_rect() -> Rect2:
	if not _frame.has_area():
		_frame = _layout_rect()
	return _frame


## The table and everything the spread puts on and around it.
func _layout_rect() -> Rect2:
	return SpreadLayout.bounds(_spread, table_size, aspect()).grow(24.0)


## The scale that fits the frame in the canvas.
func _fitted_scale() -> float:
	var margin: float = 16.0
	var room: Vector2 = size - Vector2(margin, margin) * 2.0
	var frame: Rect2 = _frame_rect()
	if room.x <= 0 or room.y <= 0:
		return 1.0
	return maxf(0.05, minf(room.x / frame.size.x, room.y / frame.size.y))


## Where the table's corner goes for the frame to sit centred at `scale_now`.
func _centred(scale_now: float) -> Vector2:
	var frame: Rect2 = _frame_rect()
	return ((size - frame.size * scale_now) / 2.0 - frame.position * scale_now).floor()


func _fit() -> void:
	var factor: float = _fitted_scale() * _zoom
	_table.size = table_size
	_overlay.size = table_size
	_table.scale = Vector2(factor, factor)
	_table.position = _centred(factor) + _pan
	if draft != null:
		_sync_cards()


## Zooms by `factor`, keeping the table point under canvas point `at` where it is.
func zoom_at(at: Vector2, factor: float) -> void:
	var spot: Vector2 = to_table(at)
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	var scale_now: float = _fitted_scale() * _zoom
	_pan = at - spot * scale_now - _centred(scale_now)
	_fit()


## Fits the table and every card in view again.
func reset_view() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	_frame = Rect2()
	_fit()


func _pair_ends(k: int) -> PackedVector2Array:
	var pair: Array = draft.pairs()[k]
	if pair.size() != 2:
		return PackedVector2Array()
	var a: int = draft.index_of(str(pair[0]))
	var b: int = draft.index_of(str(pair[1]))
	if a < 0 or b < 0:
		return PackedVector2Array()
	return line_ends(a, b)


func _gui_input(event: InputEvent) -> void:
	if draft == null:
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if button.pressed:
			zoom_at(button.position, ZOOM_STEP if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP)
		accept_event()
		return
	if button != null and button.button_index == MOUSE_BUTTON_MIDDLE:
		if button.pressed and button.double_click:
			reset_view()
		else:
			_panning = button.pressed
		accept_event()
		return
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			grab_focus()
			_press(to_table(button.position), button.double_click, button.ctrl_pressed)
		else:
			_release(to_table(button.position))
		accept_event()
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		if _panning:
			_pan += motion.relative
			_fit()
			return
		_motion(to_table(motion.position), motion.shift_pressed, motion.alt_pressed)
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and _key(key):
		accept_event()


func _press(point: Vector2, double_click: bool, ctrl: bool) -> void:
	_moved = false
	if double_click and card_at(point) < 0:
		var added: int = draft.add_position(TableView.normalized_for(point, table_size))
		if added < 0:
			full.emit()
			return
		refresh()
		select(added)
		edited.emit()
		return
	for candidate: int in [selected, _hovered]:
		if candidate < 0 or candidate >= draft.size():
			continue
		for node: Vector2 in nodes(candidate):
			if point.distance_to(node) <= NODE_RADIUS / _scale():
				_drag = Drag.CONNECT
				_drag_from = candidate
				_drag_point = point
				return
	if selected >= 0 and point.distance_to(knob(selected)) <= NODE_RADIUS / _scale():
		_start_rotate(selected, point)
		return
	var ring: int = ring_at(point)
	if ring >= 0:
		_drag = Drag.CONNECT
		_drag_from = ring
		_drag_point = point
		_overlay.queue_redraw()
		return
	var card: int = card_at(point)
	if card >= 0:
		select(card)
		if ctrl:
			_start_rotate(card, point)
		else:
			_drag = Drag.MOVE
			_grab_offset = centre(card) - point
			_drag_start = centre(card)
		return
	var line: int = line_at(point)
	select(-1, line)


func _start_rotate(card: int, point: Vector2) -> void:
	_drag = Drag.ROTATE
	_start_angle = (point - centre(card)).angle()
	_start_rotation = draft.rotation_of(card)


## The grid point nearest `point`. The grid starts at the deck's centre, so cards line
## up with the deck and with each other.
func snap_to_grid(point: Vector2) -> Vector2:
	var origin: Vector2 = grid_origin()
	var step: float = float(maxi(grid, 1))
	return origin + ((point - origin) / step).round() * step


func grid_origin() -> Vector2:
	var height: float = card_height()
	return TableView.pile_position_for(table_size, height, aspect()) + Vector2(height * aspect(), height) / 2.0


func _motion(point: Vector2, shift: bool, alt: bool = false) -> void:
	match _drag:
		Drag.MOVE:
			var target: Vector2 = point + _grab_offset
			if alt:
				var delta: Vector2 = target - _drag_start
				if absf(delta.x) >= absf(delta.y):
					target.y = _drag_start.y
				else:
					target.x = _drag_start.x
			if shift:
				target = snap_to_grid(target)
			if shift != _snapping:
				_snapping = shift
				_overlay.queue_redraw()
			draft.move_position(selected, TableView.normalized_for(target, table_size))
			_moved = true
			_sync_cards()
			edited.emit()
		Drag.ROTATE:
			var turned: float = rad_to_deg((point - centre(selected)).angle() - _start_angle)
			var degrees: float = SpreadDraft.snap_eighth(_start_rotation + turned)
			if not is_equal_approx(fposmod(degrees, 360.0), draft.rotation_of(selected)):
				draft.set_rotation(selected, degrees)
				_sync_cards()
				edited.emit()
		Drag.CONNECT:
			_drag_point = point
			_overlay.queue_redraw()
		_:
			var ring: int = ring_at(point)
			var over: int = card_at(point)
			if ring >= 0:
				over = ring
			if over != _hovered or ring != _ring_hovered:
				_hovered = over
				_ring_hovered = ring
				_overlay.queue_redraw()
			mouse_default_cursor_shape = Control.CURSOR_CROSS if ring >= 0 \
					else (Control.CURSOR_MOVE if over >= 0 else Control.CURSOR_ARROW)
			for candidate: int in [selected, _hovered]:
				if candidate >= 0 and candidate < draft.size():
					for node: Vector2 in nodes(candidate):
						if point.distance_to(node) <= NODE_RADIUS / _scale():
							mouse_default_cursor_shape = Control.CURSOR_CROSS


func _release(point: Vector2) -> void:
	var drag: Drag = _drag
	_drag = Drag.NONE
	if _snapping:
		_snapping = false
		_overlay.queue_redraw()
	match drag:
		Drag.CONNECT:
			var target: int = line_target(point, _drag_from)
			if target >= 0 and draft.connect_positions(_drag_from, target):
				select(-1, draft.pairs().size() - 1)
				edited.emit()
			_overlay.queue_redraw()
		Drag.MOVE:
			if _moved:
				var under: int = card_at(centre(selected), selected)
				if under >= 0 and draft.position(selected).get("over") != draft.position(under).get("id") \
						and draft.position(under).get("over") != draft.position(selected).get("id"):
					dropped_on.emit(selected, under)


func _key(key: InputEventKey) -> bool:
	match key.keycode:
		KEY_DELETE, KEY_BACKSPACE:
			if selected >= 0:
				draft.remove_position(selected)
				selected = -1
				refresh()
				select(-1)
				edited.emit()
				return true
			if selected_line >= 0:
				draft.disconnect_pair(selected_line)
				select(-1)
				edited.emit()
				return true
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			if selected < 0:
				return false
			var step: float = NUDGE_BIG if key.shift_pressed else NUDGE
			var direction: Vector2 = {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT,
					KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}[key.keycode]
			var entry: Dictionary = draft.position(selected)
			draft.move_position(selected, Vector2(entry["x"], entry["y"]) + direction * step)
			_sync_cards()
			edited.emit()
			return true
	return false


func _draw_table() -> void:
	var table: Rect2 = Rect2(Vector2.ZERO, table_size)
	_table.draw_rect(table, Color(ReaderTheme.PANEL, 0.55))
	_table.draw_rect(table, Color(ReaderTheme.BRASS, 0.5), false, 1.0 / _scale())
	# Where the deck lies: positions must keep clear of it.
	var height: float = card_height()
	var pile: Rect2 = Rect2(TableView.pile_position_for(table_size, height, aspect()),
			Vector2(height * aspect(), height))
	_table.draw_rect(pile, Color(ReaderTheme.MUTED, 0.15))
	_table.draw_rect(pile, Color(ReaderTheme.MUTED, 0.6), false, 1.0 / _scale())
	var font: Font = get_theme_default_font()
	_table.draw_string(font, pile.get_center() + Vector2(-pile.size.x / 2.0, 6), "deck",
			HORIZONTAL_ALIGNMENT_CENTER, pile.size.x, 16, ReaderTheme.MUTED)
	_table.draw_string(font, Vector2(8, 18), "shown at full size", HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
			Color(ReaderTheme.BRASS, 0.7))
	# Past the table: what the reading table will show when it zooms out to fit.
	var layout: Rect2 = SpreadLayout.bounds(_spread, table_size, aspect())
	if not table.encloses(layout.grow(-0.5)):
		_table.draw_dashed_line(layout.position, Vector2(layout.end.x, layout.position.y), Color(ReaderTheme.MUTED, 0.6), 1.0 / _scale(), 6.0 / _scale())
		_table.draw_dashed_line(Vector2(layout.end.x, layout.position.y), layout.end, Color(ReaderTheme.MUTED, 0.6), 1.0 / _scale(), 6.0 / _scale())
		_table.draw_dashed_line(layout.end, Vector2(layout.position.x, layout.end.y), Color(ReaderTheme.MUTED, 0.6), 1.0 / _scale(), 6.0 / _scale())
		_table.draw_dashed_line(Vector2(layout.position.x, layout.end.y), layout.position, Color(ReaderTheme.MUTED, 0.6), 1.0 / _scale(), 6.0 / _scale())


## The grid over the visible part of the canvas, while snapping. Lines through the
## deck's centre are stronger.
func _draw_grid() -> void:
	var step: float = float(maxi(grid, 1))
	if step * _scale() < 6.0:
		return
	var origin: Vector2 = grid_origin()
	var seen: Rect2 = Rect2(to_table(Vector2.ZERO), size / _scale())
	var first: Vector2 = origin + ((seen.position - origin) / step).floor() * step
	var faint: Color = Color(ReaderTheme.MUTED, 0.22)
	var strong: Color = Color(ReaderTheme.BRASS, 0.45)
	var width: float = 1.0 / _scale()
	var x: float = first.x
	while x <= seen.end.x:
		var on_origin: bool = absf(x - origin.x) < step / 2.0
		_overlay.draw_line(Vector2(x, seen.position.y), Vector2(x, seen.end.y), strong if on_origin else faint, width)
		x += step
	var y: float = first.y
	while y <= seen.end.y:
		var on_origin: bool = absf(y - origin.y) < step / 2.0
		_overlay.draw_line(Vector2(seen.position.x, y), Vector2(seen.end.x, y), strong if on_origin else faint, width)
		y += step


func _draw_overlay() -> void:
	if draft == null:
		return
	var thin: float = 1.5 / _scale()
	if _snapping:
		_draw_grid()
	for k: int in draft.pairs().size():
		var ends: PackedVector2Array = _pair_ends(k)
		if ends.is_empty():
			continue
		var chosen: bool = k == selected_line
		var color: Color = ReaderTheme.TEXT if chosen else ReaderTheme.BRASS
		_overlay.draw_line(ends[0], ends[1], color, (4.0 if chosen else 2.5) / _scale(), true)
		for end: Vector2 in ends:
			_overlay.draw_circle(end, 4.0 / _scale(), color)
	# The grab ring glows faintly round the card under the mouse, fully in the ring
	# itself and round both cards of a line being drawn.
	if _drag == Drag.CONNECT and _drag_from >= 0 and _drag_from < draft.size():
		_draw_glow(_drag_from, 1.0)
	elif _hovered >= 0 and _hovered < draft.size() and _drag == Drag.NONE:
		_draw_glow(_hovered, 1.0 if _ring_hovered == _hovered else 0.35)
	if _hovered >= 0 and _hovered < draft.size() and _hovered != selected:
		for node: Vector2 in nodes(_hovered):
			_overlay.draw_circle(node, 3.0 / _scale(), Color(ReaderTheme.BRASS, 0.6))
	if selected >= 0 and selected < draft.size():
		var points: PackedVector2Array = nodes(selected)
		var outline: PackedVector2Array = [points[0], points[2], points[4], points[6], points[0]]
		_overlay.draw_polyline(outline, ReaderTheme.TEXT, thin, true)
		var top: Vector2 = points[1]
		_overlay.draw_line(top, knob(selected), ReaderTheme.TEXT, thin, true)
		_overlay.draw_circle(knob(selected), NODE_RADIUS * 0.8 / _scale(), ReaderTheme.BRASS)
		var side: float = NODE_RADIUS * 1.3 / _scale()
		for node: Vector2 in points:
			var square: Rect2 = Rect2(node - Vector2(side, side) / 2.0, Vector2(side, side))
			_overlay.draw_rect(square, ReaderTheme.BACKGROUND)
			_overlay.draw_rect(square, ReaderTheme.TEXT, false, thin)
	if _drag == Drag.CONNECT and _drag_from >= 0:
		var target: int = line_target(_drag_point, _drag_from)
		var from: Vector2 = centre(_drag_from)
		var best: float = INF
		for node: Vector2 in nodes(_drag_from):
			if node.distance_squared_to(_drag_point) < best:
				best = node.distance_squared_to(_drag_point)
				from = node
		_overlay.draw_dashed_line(from, _drag_point, ReaderTheme.BRASS, 2.0 / _scale(), 8.0 / _scale())
		if target >= 0:
			var corners: PackedVector2Array = nodes(target)
			_overlay.draw_polyline([corners[0], corners[2], corners[4], corners[6], corners[0]],
					ReaderTheme.WELL, 3.0 / _scale(), true)
