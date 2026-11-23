extends "res://tests/test_case.gd"
## The window opens where it was last closed, moved back onto a screen if it would
## otherwise open off one.

const PATH := "user://test_window_place.json"
const SCREEN := Rect2i(0, 0, 1920, 1040)


func _areas(list: Array) -> Array[Rect2i]:
	var areas: Array[Rect2i] = []
	for area: Rect2i in list:
		areas.append(area)
	return areas


func test_a_place_on_screen_is_kept() -> void:
	var wanted := Rect2i(300, 200, 1280, 720)
	assert_eq(WindowPlace.fit(wanted, _areas([SCREEN])), wanted)


func test_a_place_running_off_the_screen_is_moved_back() -> void:
	var fitted: Rect2i = WindowPlace.fit(Rect2i(1000, 600, 1280, 720), _areas([SCREEN]))
	assert_eq(fitted, Rect2i(640, 320, 1280, 720))


func test_room_is_left_for_the_title_bar() -> void:
	var fitted: Rect2i = WindowPlace.fit(Rect2i(100, 0, 1280, 720), _areas([SCREEN]))
	assert_eq(fitted.position.y, WindowPlace.TITLE_BAR_ROOM)


func test_a_window_too_big_for_the_screen_is_shrunk() -> void:
	var fitted: Rect2i = WindowPlace.fit(Rect2i(0, 0, 2560, 1440), _areas([SCREEN]))
	assert_eq(fitted.size, Vector2i(1920, 1040 - WindowPlace.TITLE_BAR_ROOM))
	assert_eq(fitted.position, Vector2i(0, WindowPlace.TITLE_BAR_ROOM))


func test_the_window_stays_on_the_screen_it_mostly_covers() -> void:
	var second := Rect2i(1920, 0, 2560, 1400)
	var fitted: Rect2i = WindowPlace.fit(Rect2i(2000, 300, 1280, 720), _areas([SCREEN, second]))
	assert_eq(fitted, Rect2i(2000, 300, 1280, 720))


func test_a_place_on_a_screen_that_is_gone_moves_to_one_that_is_there() -> void:
	var fitted: Rect2i = WindowPlace.fit(Rect2i(3000, 300, 1280, 720), _areas([SCREEN]))
	assert_true(SCREEN.encloses(fitted), "on the remaining screen: %s" % fitted)


func test_the_place_is_saved_and_loaded() -> void:
	var place := WindowPlace.new()
	place.rect = Rect2i(-1500, 120, 1600, 900)
	place.maximized = true
	assert_eq(place.save(PATH), OK)
	var loaded: WindowPlace = WindowPlace.load_from(PATH)
	assert_eq(loaded.rect, place.rect)
	assert_true(loaded.maximized)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_no_file_or_a_bad_file_means_no_place() -> void:
	assert_false(WindowPlace.load_from("user://no_such_window.json").has_place())
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("{\"x\": \"left\"}")
	file.close()
	assert_false(WindowPlace.load_from(PATH).has_place())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
