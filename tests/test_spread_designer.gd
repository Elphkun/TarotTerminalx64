extends "res://tests/test_case.gd"
## The spread designer: its draft (core/spread_draft.gd), the shared layout check
## (ui/spread_layout.gd) and the canvas's transform controls (ui/spread_canvas.gd).

const FOLDER := "user://test_designer_spreads"
const WIDE: Vector2 = Vector2(760, 570)


func _clear_folder() -> void:
	var path: String = ProjectSettings.globalize_path(FOLDER)
	if DirAccess.dir_exists_absolute(path):
		for file: String in DirAccess.get_files_at(path):
			DirAccess.remove_absolute(path.path_join(file))
		DirAccess.remove_absolute(path)


## Three cards in a row, apart, each with a meaning: a spread that saves.
func _three() -> SpreadDraft:
	var draft: SpreadDraft = SpreadDraft.new()
	draft.id = "row"
	for x: float in [0.2, 0.5, 0.8]:
		var i: int = draft.add_position(Vector2(x, 0.5))
		draft.set_position_field(i, "meaning", "meaning %d" % i)
	return draft


func _canvas(draft: SpreadDraft) -> SpreadCanvas:
	var canvas: SpreadCanvas = SpreadCanvas.new()
	canvas.size = WIDE + Vector2(32, 32)
	canvas.set_draft(draft)
	canvas._fit()
	return canvas


func test_added_positions_get_free_ids_and_round_positions() -> void:
	var draft: SpreadDraft = SpreadDraft.new()
	assert_eq(draft.add_position(Vector2(0.12345, 5.0)), 0)
	assert_eq(draft.position(0)["id"], "p1")
	assert_eq(draft.position(0)["x"], 0.123)
	assert_eq(draft.position(0)["y"], 2.0, "kept within reach of the table")
	draft.rename_position(0, "p2")
	draft.add_position(Vector2(0.5, 0.5))
	assert_eq(draft.position(1)["id"], "p3", "an id in use is skipped")


func test_rotation_snaps_to_eighths_and_stays_within_a_turn() -> void:
	assert_eq(SpreadDraft.snap_eighth(30.0), 45.0)
	assert_eq(SpreadDraft.snap_eighth(-100.0), -90.0)
	var draft: SpreadDraft = _three()
	draft.set_rotation(0, -45.0)
	assert_eq(draft.position(0)["rotation"], 315)
	draft.set_rotation(0, 360.0)
	assert_eq(draft.position(0)["rotation"], 0)


func test_dignity_lines_are_not_doubled() -> void:
	var draft: SpreadDraft = _three()
	assert_true(draft.connect_positions(0, 1))
	assert_false(draft.connect_positions(1, 0), "the same line the other way round")
	assert_false(draft.connect_positions(2, 2), "a card with itself")
	assert_eq(draft.pairs(), [["p1", "p2"]])


func test_renaming_carries_lines_and_over_along() -> void:
	var draft: SpreadDraft = _three()
	draft.connect_positions(0, 1)
	draft.set_position_field(1, "over", "p1")
	assert_eq(draft.rename_position(0, "cover"), "")
	assert_eq(draft.pairs(), [["cover", "p2"]])
	assert_eq(draft.position(1)["over"], "cover")
	assert_true(draft.rename_position(1, "cover") != "", "an id in use is refused")
	assert_true(draft.rename_position(1, " ") != "", "an empty id is refused")


func test_removing_a_card_removes_its_lines_and_over() -> void:
	var draft: SpreadDraft = _three()
	draft.connect_positions(0, 1)
	draft.connect_positions(1, 2)
	draft.set_position_field(2, "over", "p2")
	draft.remove_position(1)
	assert_eq(draft.pairs(), [])
	assert_false(draft.position(1).has("over"))


func test_reading_order_moves() -> void:
	var draft: SpreadDraft = _three()
	assert_eq(draft.move_in_order(0, 1), 1)
	assert_eq(draft.position(0)["id"], "p2")
	assert_eq(draft.move_in_order(2, 5), 2, "already last")


func test_a_built_in_spread_opens_as_a_copy() -> void:
	var draft: SpreadDraft = SpreadDraft.from_spread("celtic_cross", db().spread("celtic_cross"), true)
	assert_eq(draft.id, "celtic_cross_copy")
	assert_eq(draft.file, "", "never written back to the built-in spreads")
	assert_true(str(draft.data["name"]).ends_with("(copy)"))
	draft.move_position(0, Vector2(0.1, 0.1))
	assert_eq(db().spread("celtic_cross")["positions"][0]["x"], 0.36, "the original is untouched")
	assert_true(draft.id_problems(db().builtin_spread_ids, {}).is_empty())
	draft.id = "celtic_cross"
	assert_false(draft.id_problems(db().builtin_spread_ids, {}).is_empty(), "a built-in id is refused")
	draft.id = "two words"
	assert_false(draft.id_problems(db().builtin_spread_ids, {}).is_empty(), "the id names the file")


func test_layout_check_finds_overlaps() -> void:
	var draft: SpreadDraft = _three()
	assert_eq(SpreadLayout.problems(draft.spread()), PackedStringArray())
	draft.move_position(1, Vector2(0.24, 0.5))
	var problems: PackedStringArray = SpreadLayout.problems(draft.spread())
	assert_eq(problems.size(), 1, "; ".join(problems))
	assert_true(problems[0].contains("\"p1\" and \"p2\" overlap"), problems[0])
	draft.set_position_field(1, "over", "p1")
	assert_eq(SpreadLayout.problems(draft.spread()), PackedStringArray(), "a card laid over another may")


## An open canvas: cards may go past the table, which then shows the whole spread
## smaller. A spread within the table (every built-in one) is shown as it is.
func test_a_spread_past_the_table_is_shown_whole_and_smaller() -> void:
	for spread_id: String in db().spreads:
		for table_size: Vector2 in SpreadLayout.TABLE_SIZES:
			var spread: Spread = Spread.from_db(db(), spread_id)
			var shown: float = SpreadLayout.fit_scale(SpreadLayout.bounds(spread, table_size, 0.5625), table_size)
			assert_eq(shown, 1.0, "%s at %s is shown as it is" % [spread_id, table_size])
	var draft: SpreadDraft = _three()
	draft.move_position(2, Vector2(1.6, -0.3))
	assert_eq(draft.position(2)["x"], 1.6, "a card may go past the table")
	assert_eq(SpreadLayout.problems(draft.spread()), PackedStringArray(), "and that is no problem")
	var table: TableView = TableView.new()
	table.db = db()
	table.size = WIDE
	table.set_spread(draft.spread())
	table.deal(draft.spread().lay_out([0, 1, 2]))
	assert_true(table.view_scale() < 1.0, "the table zooms out (%s)" % table.view_scale())
	var view: Rect2 = Rect2(Vector2.ZERO, WIDE)
	for slot: int in 3:
		var card: CardView = table.slot_view(slot)
		var corner: Vector2 = table._content.position + table._slot_position(slot) * table.view_scale()
		var far: Vector2 = corner + card.size * table.view_scale()
		assert_true(view.grow(0.5).has_point(corner) and view.grow(0.5).has_point(far),
				"card %d is on the table: %s to %s" % [slot, corner, far])
	var pile: Vector2 = table._content.position + table._pile_position() * table.view_scale()
	assert_true(view.has_point(pile), "so is the deck")
	table.free()
	# A turned card is measured by its corners.
	var tall: SpreadDraft = SpreadDraft.new()
	tall.add_position(Vector2(0.5, 0.5))
	tall.set_spread_field("card_height", 0.9)
	var upright: Rect2 = SpreadLayout.bounds(tall.spread(), WIDE, CardView.ASPECT)
	tall.set_rotation(0, 45.0)
	var turned: Rect2 = SpreadLayout.bounds(tall.spread(), WIDE, CardView.ASPECT)
	assert_true(turned.size.y > upright.size.y, "%s vs %s" % [turned, upright])


func test_saving_writes_a_spread_the_menu_loads_and_keeps_its_neighbours() -> void:
	_clear_folder()
	var draft: SpreadDraft = _three()
	draft.connect_positions(0, 1)
	assert_eq(draft.save(FOLDER), "")
	assert_eq(draft.file, "row.json")
	var found: Array[Dictionary] = SpreadLibrary.scan(FOLDER, db().builtin_spread_ids)
	assert_eq(found.size(), 1)
	assert_eq(found[0]["errors"], PackedStringArray())
	assert_eq(found[0]["data"]["dignity_adjacency"], [["p1", "p2"]])
	# A file of two spreads: renaming and saving one keeps the other, in its place.
	var path: String = ProjectSettings.globalize_path(FOLDER).path_join("row.json")
	var both: Dictionary = {"row": draft.to_data(), "other": _three().to_data()}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(both, "", false))
	file.close()
	var reopened: SpreadDraft = SpreadDraft.from_spread("row", both["row"], false, "row.json")
	reopened.id = "row_renamed"
	assert_eq(reopened.save(FOLDER), "")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_eq(saved.keys(), ["row_renamed", "other"])
	_clear_folder()


func test_canvas_drag_moves_a_card_with_the_tables_geometry() -> void:
	var draft: SpreadDraft = _three()
	var canvas: SpreadCanvas = _canvas(draft)
	var start: Vector2 = canvas.centre(1)
	canvas._press(start, false, false)
	assert_eq(canvas.selected, 1)
	canvas._motion(start + Vector2(40, 30), false)
	canvas._release(start + Vector2(40, 30))
	assert_true(canvas.centre(1).is_equal_approx(start + Vector2(40, 30)) \
			or canvas.centre(1).distance_to(start + Vector2(40, 30)) < 1.0, "the card follows the mouse")
	# Alt keeps it in line with where it started.
	canvas._press(canvas.centre(1), false, false)
	var from: Vector2 = canvas.centre(1)
	canvas._motion(from + Vector2(50, 8), false, true)
	assert_true(absf(canvas.centre(1).y - from.y) < 1.0, "Alt moves straight across")
	canvas._release(from + Vector2(50, 8))
	canvas.free()


func test_canvas_shift_drag_snaps_to_a_grid_from_the_decks_centre() -> void:
	var draft: SpreadDraft = _three()
	var canvas: SpreadCanvas = _canvas(draft)
	var origin: Vector2 = canvas.grid_origin()
	for step: int in SpreadCanvas.GRID_SIZES:
		canvas.grid = step
		for i: int in 3:
			var start: Vector2 = canvas.centre(i)
			canvas._press(start, false, false)
			canvas._motion(start + Vector2(13, -21), true)
			canvas._release(start + Vector2(13, -21))
			var cells: Vector2 = (canvas.centre(i) - origin) / step
			assert_true(cells.distance_to(cells.round()) * step < 1.0,
					"card %d sits on the %d grid: %s cells from the deck" % [i, step, cells])
	# Cards snapped to the same grid line share their x or y exactly, so they line up.
	canvas.grid = 64
	for i: int in 3:
		var start: Vector2 = canvas.centre(i)
		canvas._press(start, false, false)
		canvas._motion(Vector2(start.x, origin.y + 3), true)
		canvas._release(Vector2(start.x, origin.y + 3))
	assert_eq(draft.position(0)["y"], draft.position(2)["y"], "lined up across")
	canvas.free()


func test_canvas_ctrl_drag_turns_in_eighths() -> void:
	var draft: SpreadDraft = _three()
	var canvas: SpreadCanvas = _canvas(draft)
	var centre: Vector2 = canvas.centre(0)
	canvas._press(centre + Vector2(30, 0), false, true)
	canvas._motion(centre + Vector2(25, 22), false)  # about 40° round
	assert_eq(draft.rotation_of(0), 45.0)
	canvas._motion(centre + Vector2(0, 30), false)
	assert_eq(draft.rotation_of(0), 90.0)
	canvas._release(centre + Vector2(0, 30))
	canvas.free()


func test_canvas_node_drag_draws_a_dignity_line() -> void:
	var draft: SpreadDraft = _three()
	var canvas: SpreadCanvas = _canvas(draft)
	canvas._press(canvas.centre(0), false, false)
	canvas._release(canvas.centre(0))
	var node: Vector2 = canvas.nodes(0)[3]  # the right edge's midpoint
	canvas._press(node, false, false)
	canvas._motion(canvas.centre(1), false)
	canvas._release(canvas.centre(1))
	assert_eq(draft.pairs(), [["p1", "p2"]])
	assert_eq(canvas.selected_line, 0, "the new line is selected")
	var ends: PackedVector2Array = canvas.line_ends(0, 1)
	assert_eq(canvas.line_at(ends[0].lerp(ends[1], 0.5)), 0, "a click on the line finds it")
	canvas.free()


func test_canvas_ring_drag_draws_a_dignity_line() -> void:
	var draft: SpreadDraft = _three()
	var canvas: SpreadCanvas = _canvas(draft)
	var half_width: float = canvas.card_height() * canvas.aspect() / 2.0
	# Just outside the left edge of an unselected card, away from any node.
	var outside: Vector2 = canvas.centre(1) + Vector2(-half_width - 8.0 / canvas._scale(),
			canvas.card_height() * 0.3)
	assert_eq(canvas.ring_at(outside), 1, "the ring reaches past the card's edge")
	assert_eq(canvas.ring_at(canvas.centre(1)), -1, "the middle of the card is not the ring")
	canvas._press(outside, false, false)
	assert_eq(canvas._drag, SpreadCanvas.Drag.CONNECT, "pressing the ring starts a line, not a move")
	# Dropped on the other card's ring, not its body.
	var near_first: Vector2 = canvas.centre(0) + Vector2(half_width + 6.0 / canvas._scale(), 0)
	canvas._motion(near_first, false)
	canvas._release(near_first)
	assert_eq(draft.pairs(), [["p2", "p1"]])
	assert_true(canvas.centre(1).distance_to(TableView.slot_centre_for(
			Vector2(draft.position(1)["x"], draft.position(1)["y"]), WIDE)) < 1.0, "the card did not move")
	# Inside the card, clear of the ring, a press still moves it.
	canvas._press(canvas.centre(2), false, false)
	assert_eq(canvas._drag, SpreadCanvas.Drag.MOVE)
	canvas._release(canvas.centre(2))
	canvas.free()


func test_canvas_double_click_adds_a_card_where_clicked() -> void:
	var draft: SpreadDraft = _three()
	var canvas: SpreadCanvas = _canvas(draft)
	var spot: Vector2 = TableView.slot_centre_for(Vector2(0.5, 0.15), WIDE)
	canvas._press(spot, true, false)
	assert_eq(draft.size(), 4)
	assert_eq(canvas.selected, 3)
	assert_true(canvas.centre(3).distance_to(spot) < 1.0)
	canvas.free()



func test_dropping_a_card_on_another_lays_it_over_after_asking() -> void:
	var designer: SpreadDesigner = SpreadDesigner.new(db())
	designer.spreads_folder = FOLDER
	designer._load_draft(_three())
	designer._on_dropped_on(0, 1)
	designer._lay_over()
	var draft: SpreadDraft = designer.draft
	assert_eq(draft.position(1)["id"], "p1", "the card laid over goes after the card it covers")
	assert_eq(draft.position(1)["over"], "p2")
	assert_eq([draft.position(1)["x"], draft.position(1)["y"]], [draft.position(0)["x"], draft.position(0)["y"]],
			"exactly on top")
	assert_eq(SpreadLayout.problems(draft.spread()), PackedStringArray())
	assert_true(designer.dirty)
	designer.free()


func test_a_spread_holds_at_most_twelve_cards() -> void:
	var draft: SpreadDraft = SpreadDraft.new()
	for i: int in SpreadLibrary.MAX_POSITIONS:
		assert_eq(draft.add_position(Vector2(0.5, 0.5)), i)
	assert_true(draft.is_full())
	assert_eq(draft.add_position(Vector2(0.5, 0.5)), -1, "a thirteenth card is refused")
	var data: Dictionary = draft.to_data()
	(data["positions"] as Array).append({"id": "extra", "meaning": "x", "x": 0.5, "y": 0.5})
	var errors: PackedStringArray = SpreadLibrary.validate(data)
	assert_true("; ".join(errors).contains("at most 12 positions"), "a hand-written file is refused too: %s" % "; ".join(errors))
	for spread_id: String in db().spreads:
		assert_true(Spread.from_db(db(), spread_id).size() <= SpreadLibrary.MAX_POSITIONS, spread_id)


func test_canvas_wheel_zoom_keeps_the_point_under_the_mouse() -> void:
	var canvas: SpreadCanvas = _canvas(_three())
	var at: Vector2 = canvas.to_canvas(canvas.centre(2))
	canvas.zoom_at(at, 2.0)
	assert_true(canvas.to_canvas(canvas.centre(2)).distance_to(at) < 1.5, "the card under the mouse stays put")
	assert_true(canvas._table.scale.x > canvas._fitted_scale() * 1.9, "zoomed in")
	# Clicks still land on the right card when zoomed.
	canvas._press(canvas.centre(2), false, false)
	assert_eq(canvas.selected, 2)
	canvas._release(canvas.centre(2))
	canvas.reset_view()
	assert_true(is_equal_approx(canvas._table.scale.x, canvas._fitted_scale()), "fits again")
	canvas.free()


func test_the_reading_table_zooms_and_pans_within_its_edges() -> void:
	var table: TableView = TableView.new()
	table.db = db()
	table.size = WIDE
	table.set_spread(spread3())
	table.zoom_at(Vector2(380, 285), 2.0)
	assert_eq(table.zoom, 2.0)
	assert_eq(table._content.position, Vector2(-380, -285), "zoomed about the point")
	table.pan_by(Vector2(5000, 5000))
	assert_eq(table._content.position, Vector2.ZERO, "never pans past the edge")
	table.zoom_at(Vector2.ZERO, 0.01)
	assert_eq(table.zoom, 1.0, "never smaller than the whole table")
	table.zoom_at(Vector2(100, 100), 3.0)
	table.set_spread(spread3())
	assert_eq(table.zoom, 1.0, "a new spread shows the whole table")
	table.free()
