class_name MarkdownBbcode
## Turns the little markdown LLMs write (bold, italics, headings, bullets) into
## RichTextLabel BBCode. Safe to run on half-streamed text: an unclosed ** stays as-is.

static var _bold: RegEx = RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
static var _italic: RegEx = RegEx.create_from_string("(?<![\\*\\w])[\\*_](?![\\s\\*_])(.+?)(?<![\\s\\*_])[\\*_](?![\\*\\w])")
static var _heading: RegEx = RegEx.create_from_string("^(#{1,6})\\s+(.*)$")


static func convert(markdown: String, heading_color: Color = ReaderTheme.BRASS) -> String:
	var lines: PackedStringArray = []
	for raw: String in markdown.replace("\r", "").split("\n"):
		# Escape BBCode the model may have written by accident.
		var line: String = raw.replace("[", "[lb]")
		var heading: RegExMatch = _heading.search(line)
		if heading != null:
			line = "[color=#%s][b]%s[/b][/color]" % [heading_color.to_html(false), heading.get_string(2)]
		elif line.begins_with("- ") or line.begins_with("* "):
			line = "  • " + line.substr(2)
		line = _bold.sub(line, "[b]$1[/b]", true)
		line = _italic.sub(line, "[i]$1[/i]", true)
		lines.append(line)
	return "\n".join(lines)
