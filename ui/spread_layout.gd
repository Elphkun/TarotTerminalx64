class_name SpreadLayout
extends RefCounted
## A spread's layout on the reading table, with TableView's own geometry and the cards'
## real rotated outlines (any angle):
## - problems(): a card covering the deck or another card it doesn't lie `over`, at two
##   table shapes (a wide and a narrow one). Shared by tests/test_spreads.gd and the
##   designer.
## - bounds() and fit_scale(): a spread may reach past the table (an open canvas); the
##   table then shows all of it smaller. A spread within the table is shown as it is.

const TABLE_SIZES: Array[Vector2] = [Vector2(760, 570), Vector2(600, 480)]
## Cards are shrunk by this much before checking, so cards that only touch are fine.
const TOUCH: float = 2.0
## Room under a card for its name and dignity mark (TableView's labels).
const LABEL_ROOM: float = TableView.LABEL_GAP + 46.0


## Everything wrong with the layout, one line per problem, naming the table shapes it
## happens at. Empty when the spread fits.
static func problems(spread: Spread, aspect: float = CardView.ASPECT,
		table_sizes: Array[Vector2] = TABLE_SIZES) -> PackedStringArray:
	# Message -> the table shapes it happens at, in first-found order.
	var found: Dictionary = {}
	for table_size: Vector2 in table_sizes:
		var where: String = "%d×%d" % [table_size.x, table_size.y]
		var height: float = TableView.card_height_for(table_size, aspect, spread)
		var pile: PackedVector2Array = _rect_polygon(Rect2(
				TableView.pile_position_for(table_size, height, aspect), Vector2(height * aspect, height)))
		var outlines: Array[PackedVector2Array] = []
		for i: int in spread.size():
			outlines.append(card_polygon(spread.positions[i], table_size, height, aspect))
		for i: int in spread.size():
			var a: Dictionary = spread.positions[i]
			var shrunk: PackedVector2Array = card_polygon(a, table_size, height, aspect, TOUCH)
			if not Geometry2D.intersect_polygons(shrunk, pile).is_empty():
				_add(found, "\"%s\" covers the pile" % a.get("id"), where)
			for j: int in range(i + 1, spread.size()):
				var b: Dictionary = spread.positions[j]
				if a.get("over") == b.get("id") or b.get("over") == a.get("id"):
					continue
				if not Geometry2D.intersect_polygons(shrunk, outlines[j]).is_empty():
					_add(found, "\"%s\" and \"%s\" overlap" % [a.get("id"), b.get("id")], where)
	var lines: PackedStringArray = []
	for message: String in found:
		lines.append("%s (at %s)" % [message, ", ".join(found[message])])
	return lines


## Everything the spread puts on a table of `table_size`: the table itself, the deck,
## every card (turned) and the name labels under them. In the table's coordinates.
static func bounds(spread: Spread, table_size: Vector2, aspect: float) -> Rect2:
	var height: float = TableView.card_height_for(table_size, aspect, spread)
	var found: Rect2 = Rect2(Vector2.ZERO, table_size)
	found = found.merge(Rect2(TableView.pile_position_for(table_size, height, aspect),
			Vector2(height * aspect, height)))
	if spread == null:
		return found
	for entry: Dictionary in spread.positions:
		var outline: PackedVector2Array = card_polygon(entry, table_size, height, aspect)
		var lowest: float = -INF
		for point: Vector2 in outline:
			found = found.expand(point)
			lowest = maxf(lowest, point.y)
		if not spread.compact_labels:
			# The name and the dignity mark underneath (TableView._relayout): the room they
			# take below the card. Their short text spills sideways harmlessly.
			var centre_x: float = TableView.slot_centre_for(Vector2(float(entry.get("x", 0.5)), 0.0), table_size).x
			var width: float = height * aspect
			found = found.merge(Rect2(centre_x - width / 2.0, lowest, width, LABEL_ROOM))
	return found


## How much the table shrinks a layout of `layout_bounds` to show all of it: 1 when it
## is within the table.
static func fit_scale(layout_bounds: Rect2, table_size: Vector2) -> float:
	if layout_bounds.size.x <= 0.0 or layout_bounds.size.y <= 0.0:
		return 1.0
	return minf(1.0, minf(table_size.x / layout_bounds.size.x, table_size.y / layout_bounds.size.y))


## The four corners of a position's card on a table of `table_size`, rotated, shrunk
## by `inset` on every side.
static func card_polygon(position_data: Dictionary, table_size: Vector2, height: float,
		aspect: float, inset: float = 0.0) -> PackedVector2Array:
	var centre: Vector2 = TableView.slot_centre_for(Vector2(float(position_data.get("x", 0.5)),
			float(position_data.get("y", 0.5))), table_size)
	var half: Vector2 = Vector2(height * aspect, height) / 2.0 - Vector2(inset, inset)
	var angle: float = deg_to_rad(float(position_data.get("rotation", 0.0)))
	var corners: PackedVector2Array = []
	for corner: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		corners.append(centre + corner.rotated(angle))
	return corners


static func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
			rect.end, Vector2(rect.position.x, rect.end.y)])


static func _add(found: Dictionary, message: String, where: String) -> void:
	if not found.has(message):
		found[message] = PackedStringArray()
	var places: PackedStringArray = found[message]
	if not places.has(where):
		places.append(where)
	found[message] = places
