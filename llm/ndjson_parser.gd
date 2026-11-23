class_name NdjsonParser
extends RefCounted
## Splits a newline-delimited JSON byte stream (Ollama's native streaming) into lines.
## Same interface as SseParser: feed chunks as they arrive; chunks may split lines or
## UTF-8 characters anywhere.

## Set by whoever reads the lines, once the last one ("done": true) has been seen.
var done: bool = false

var _pending: PackedByteArray = PackedByteArray()


## Returns every complete, non-empty line in this chunk.
func feed(chunk: PackedByteArray) -> Array[String]:
	_pending.append_array(chunk)
	var lines: Array[String] = []
	var last_newline: int = _pending.rfind(10)
	if last_newline < 0:
		return lines
	# Every byte up to a newline is complete UTF-8, since "\n" never occurs inside a character.
	var text: String = _pending.slice(0, last_newline + 1).get_string_from_utf8()
	_pending = _pending.slice(last_newline + 1)
	for line: String in text.split("\n", false):
		if line.strip_edges() != "":
			lines.append(line.strip_edges())
	return lines


## The last line, if the stream did not end with a newline.
func finish() -> Array[String]:
	var lines: Array[String] = []
	var text: String = _pending.get_string_from_utf8().strip_edges()
	_pending = PackedByteArray()
	if text != "":
		lines.append(text)
	return lines
