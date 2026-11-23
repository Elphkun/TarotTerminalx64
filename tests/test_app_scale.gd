extends "res://tests/test_case.gd"
## The interface size: the chosen scale, cut down only when the window cannot hold the
## 1280x720 design at that scale (a small screen or browser window).


func test_scale_keeps_the_chosen_size_when_there_is_room() -> void:
	assert_eq(App.scale_for(Vector2(1280, 720), 1.0), 1.0)
	assert_eq(App.scale_for(Vector2(2560, 1440), 1.0), 1.0, "a big window gives room, not bigger text")
	assert_eq(App.scale_for(Vector2(1920, 1080), 1.5), 1.5)


func test_scale_shrinks_to_fit_a_small_window() -> void:
	assert_eq(App.scale_for(Vector2(1920, 1080), 2.0), 1.5, "limited by the window")
	assert_eq(App.scale_for(Vector2(960, 720), 1.0), 0.75, "a narrow browser window shrinks the app")
	assert_eq(App.scale_for(Vector2(10, 10), 1.0), 0.25, "never below a quarter")


func test_settings_keep_the_interface_size_as_a_number() -> void:
	var path: String = "user://test_ui_scale_settings.json"
	var settings: AppSettings = AppSettings.load_from(path)
	settings.ui_scale = 1.5
	settings.deck = "x"
	settings.save()
	var loaded: AppSettings = AppSettings.load_from(path)
	assert_eq(loaded.ui_scale, 1.5)
	assert_eq(loaded.deck, "x")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_settings_remember_the_notice_agreed_to() -> void:
	var path: String = "user://test_notice_settings.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var settings: AppSettings = AppSettings.load_from(path)
	assert_eq(settings.notice_accepted, 0, "a first run has agreed to nothing")
	settings.notice_accepted = NoticeDialog.VERSION
	settings.save()
	assert_eq(AppSettings.load_from(path).notice_accepted, NoticeDialog.VERSION)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_window_icon_is_shrunk_to_the_asked_size() -> void:
	var source: Image = Image.create(300, 300, false, Image.FORMAT_RGB8)
	source.fill(Color(0.2, 0.9, 0.3))
	var icon: Image = App.icon_image(source, 48)
	assert_eq(icon.get_size(), Vector2i(48, 48))
	assert_eq(icon.get_format(), Image.FORMAT_RGBA8)
	assert_eq(source.get_size(), Vector2i(300, 300), "the source is left alone")
	assert_eq(App.icon_image(null, 32), null)
