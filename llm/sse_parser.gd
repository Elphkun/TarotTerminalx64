class_name SseParser
extends RefCounted
## Splits a server-sent-events byte stream into event payloads.
## Feed it chunks as they arrive. Chunks may split lines or UTF-8 characters anywhere.

## True once a "data: [DONE]" event has been seen.
var done: bool = false

var _pending: PackedByteArray = PackedByteArray()
var _data_lines: PackedStringArray = []


## Returns the data payloads of every event completed by this chunk.
## "[DONE]" is not returned; it sets `done` instead.
func feed(chunk: PackedByteArray) -> Array[String]:
	_pending.append_array(chunk)
	var events: Array[String] = []
	var last_newline: int = _pending.rfind(10)
	if last_newline < 0:
		return events
	# Every byte up to a newline is complete UTF-8, since "\n" never occurs inside a character.
	var text: String = _pending.slice(0, last_newline + 1).get_string_from_utf8()
	_pending = _pending.slice(last_newline + 1)
	var lines: PackedStringArray = text.split("\n")
	lines.resize(lines.size() - 1)  # text ends with "\n", so the last piece is always empty
	for raw_line: String in lines:
		_take_line(raw_line.trim_suffix("\r"), events)
	return events


## Flushes a final event that was not followed by a blank line.
func finish() -> Array[String]:
	var events: Array[String] = []
	if not _pending.is_empty():
		_take_line(_pending.get_string_from_utf8().trim_suffix("\r"), events)
		_pending = PackedByteArray()
	_take_line("", events)
	return events


func _take_line(line: String, events: Array[String]) -> void:
	if line == "":
		if _data_lines.is_empty():
			return
		var payload: String = "\n".join(_data_lines)
		_data_lines = []
		if payload.strip_edges() == "[DONE]":
			done = true
		else:
			events.append(payload)
		return
	if line.begins_with(":"):
		return  # comment / keep-alive
	if line.begins_with("data:"):
		_data_lines.append(line.trim_prefix("data:").trim_prefix(" "))
	# Other fields (event:, id:, retry:) are not used by chat completion streams.
