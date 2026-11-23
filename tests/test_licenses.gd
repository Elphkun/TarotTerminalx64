extends "res://tests/test_case.gd"
## Settings -> Licenses…: the app's MIT license and the Godot Engine's notices, which a
## build must carry.


func test_licenses_show_ours_and_godots() -> void:
	var text: String = LicensesDialog.licenses_text()
	assert_true(text.begins_with("TarotTerminal\n\nMIT License"), "ours comes first")
	assert_true(text.contains("Copyright (c) 2026 Sasazaki Software (Reiji Kitsuoka)"))
	assert_true(text.contains("CC BY 4.0"), "the decks' license is named")
	assert_true(text.contains(Engine.get_license_text().strip_edges().left(60)), "Godot's own license")
	assert_true(text.contains("FreeType") or text.contains("freetype"),
			"the libraries inside the engine are credited")
