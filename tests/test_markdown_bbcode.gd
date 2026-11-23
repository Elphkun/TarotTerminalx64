extends "res://tests/test_case.gd"


func test_bold_italic_and_bullets() -> void:
	assert_eq(MarkdownBbcode.convert("A **strong** and *soft* word"),
			"A [b]strong[/b] and [i]soft[/i] word")
	assert_eq(MarkdownBbcode.convert("- one\n* two"), "  • one\n  • two")


func test_headings() -> void:
	var text: String = MarkdownBbcode.convert("## Synthesis", Color("#c9a96b"))
	assert_eq(text, "[color=#c9a96b][b]Synthesis[/b][/color]")


func test_half_streamed_bold_is_left_alone() -> void:
	assert_eq(MarkdownBbcode.convert("The **Past"), "The **Past")


func test_brackets_are_escaped() -> void:
	assert_eq(MarkdownBbcode.convert("a [b]trap[/b]"), "a [lb]b]trap[lb]/b]")


func test_snake_case_is_not_italic() -> void:
	assert_eq(MarkdownBbcode.convert("dignity_element and 2 * 3 * 4"), "dignity_element and 2 * 3 * 4")


func test_display_facts_hide_gd_rank_labels() -> void:
	var summary: ReadingSummary = ReadingSummary.build(
			db(), spread3(), three_card(["wands_page", "cups_king", "world"]), "Q?")
	var page: String = "\n".join(summary.display_facts(db().by_id("wands_page")))
	assert_true(page.contains("Earth of Fire, the daughter"), page)
	assert_false(page.contains("GD "), page)
	assert_true(page.contains("Princess of the Shining Flame"), "GD titles are shown")
	var patterns: String = "\n".join(summary.display_patterns())
	assert_false(patterns.contains("prince") or patterns.contains("princess"), patterns)
