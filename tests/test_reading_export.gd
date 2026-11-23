extends "res://tests/test_case.gd"


func test_markdown_has_the_deal_reading_and_dignities() -> void:
	var summary: ReadingSummary = ReadingSummary.build(
			db(), spread3(), three_card(["wands_2", "cups_2", "world"]), "Will it work?")
	var text: String = ReadingExport.to_markdown(summary, "\n**Past**\nIt began well.\n",
			{"date": "2026-11-19 14:05:00", "deck": "Test Deck", "model": "fake-model"})
	assert_true(text.begins_with("# Will it work?\n\n**Date:** 2026-11-19 14:05:00  \n**Spread:** Past, Present, Future  \n**Deck:** Test Deck  \n**Model:** fake-model\n"), text)
	assert_true(text.contains("## The deal\n\n1. **Past:** Two of Wands (ill-dignified)\n2. **Present:** Two of Cups (ill-dignified)\n3. **Future:** The World ("), text)
	assert_true(text.contains("## The reading\n\n**Past**\nIt began well.\n"), text)
	assert_true(text.contains("- **Two of Wands** (past): ill-dignified (score "), text)
	assert_true(text.contains("## Patterns\n\n- "), text)
	assert_false(text.contains("GD "), "no GD rank labels")


func test_missing_details_are_left_out() -> void:
	var summary: ReadingSummary = ReadingSummary.build(
			db(), spread3(), three_card(["wands_2", "cups_2", "world"]), "Q")
	var text: String = ReadingExport.to_markdown(summary, "R")
	assert_true(text.begins_with("# Q\n\n**Spread:** Past, Present, Future\n"), text)


func test_file_name() -> void:
	assert_eq(ReadingExport.file_name("Should I take the new job, or wait?", "2026-11-19"),
			"2026-11-19 should-i-take-the-new-job.md")
	assert_eq(ReadingExport.file_name("?!", "2026-11-19"), "2026-11-19 reading.md")
