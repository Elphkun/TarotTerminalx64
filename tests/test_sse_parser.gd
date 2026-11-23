extends "res://tests/test_case.gd"


func _bytes(text: String) -> PackedByteArray:
	return text.to_utf8_buffer()


func test_events_split_across_chunks() -> void:
	var parser: SseParser = SseParser.new()
	assert_eq(parser.feed(_bytes("data: {\"a\":")), [] as Array[String])
	assert_eq(parser.feed(_bytes("1}\n")), [] as Array[String], "no blank line yet")
	assert_eq(parser.feed(_bytes("\ndata: x\n\ndata: y")), ["{\"a\":1}", "x"] as Array[String])
	assert_eq(parser.finish(), ["y"] as Array[String])


func test_done_and_comments() -> void:
	var parser: SseParser = SseParser.new()
	var events: Array[String] = parser.feed(_bytes(": keep-alive\n\ndata: a\r\n\r\ndata: [DONE]\n\n"))
	assert_eq(events, ["a"] as Array[String])
	assert_true(parser.done)


func test_utf8_split_inside_a_character() -> void:
	var parser: SseParser = SseParser.new()
	var bytes: PackedByteArray = _bytes("data: ש é\n\n")
	var first: Array[String] = parser.feed(bytes.slice(0, 7))
	var second: Array[String] = parser.feed(bytes.slice(7))
	assert_eq(first.size(), 0)
	assert_eq(second, ["ש é"] as Array[String])


func test_multiline_data() -> void:
	var parser: SseParser = SseParser.new()
	assert_eq(parser.feed(_bytes("data: one\ndata: two\n\n")), ["one\ntwo"] as Array[String])
