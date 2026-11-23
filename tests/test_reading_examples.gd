extends "res://tests/test_case.gd"

const PATH := "user://test_read_examples.txt"


func _write(text: String) -> void:
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_placeholder_counts_as_no_examples() -> void:
	_write("[PLACEHOLDER] Replace this file.\n")
	assert_eq(ReadingExamples.load_text(PATH), "")
	assert_eq(ReadingExamples.count(PATH), 0)


func test_draft_lists_cards_and_dignities() -> void:
	var summary: ReadingSummary = ReadingSummary.build(
			db(), spread3(), three_card(["wands_2", "cups_2", "world"]), "  Will it work? ")
	var draft: String = ReadingExamples.draft(summary, "\nThe reading.\n")
	assert_true(draft.begins_with("Question: Will it work?\nCards: past Two of Wands (ill-dignified), "), draft)
	assert_true(draft.contains("present Two of Cups (ill-dignified)"), draft)
	assert_true(draft.ends_with("\n\nThe reading."), draft)


## Only a line holding just "---" separates; dashes inside text and "----" do not.
func test_entries_split_on_separator_lines_only() -> void:
	_write("Question: one\nA --- dash.\n\n---\n\nQuestion: two\r\n----\r\n---\n\n---\n")
	var found: PackedStringArray = ReadingExamples.entries(PATH)
	assert_eq(found, PackedStringArray(["Question: one\nA --- dash.", "Question: two\n----"]))
	assert_eq(ReadingExamples.title(found[1]), "two")
	assert_eq(ReadingExamples.load_text(PATH), "Question: one\nA --- dash.\n\n---\n\nQuestion: two\n----")


func test_save_entries_drops_empty_and_keeps_the_limit() -> void:
	assert_eq(ReadingExamples.save_entries(PackedStringArray(["One.", "  ", "\nTwo.\n"]), PATH), OK)
	assert_eq(ReadingExamples.entries(PATH), PackedStringArray(["One.", "Two."]))
	assert_eq(ReadingExamples.save_entries(PackedStringArray(["1", "2", "3", "4"]), PATH),
			ERR_INVALID_PARAMETER)
	assert_eq(ReadingExamples.count(PATH), 2, "a refused save leaves the file alone")
	assert_eq(ReadingExamples.save_entries(PackedStringArray(), PATH), OK)
	assert_eq(ReadingExamples.count(PATH), 0)
	assert_eq(ReadingExamples.load_text(PATH), "")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
