class_name CorrespondencePanel
extends PanelContainer
## The facts the reading was given: each card's correspondences and dignity, then the
## spread's patterns. Collapsible; clicking a card on the table jumps to its entry.

var toggle: Button
var text_view: RichTextLabel

var _paragraph_of_slot: Array[int] = []


func _init() -> void:
	var box: VBoxContainer = VBoxContainer.new()
	add_child(box)
	toggle = Button.new()
	toggle.flat = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.add_theme_color_override("font_color", ReaderTheme.BRASS)
	toggle.pressed.connect(func() -> void: set_expanded(not text_view.visible))
	box.add_child(toggle)
	text_view = RichTextLabel.new()
	text_view.bbcode_enabled = true
	text_view.selection_enabled = true
	text_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text_view)
	set_expanded(false)
	clear()


func set_expanded(expanded: bool) -> void:
	text_view.visible = expanded
	size_flags_vertical = Control.SIZE_EXPAND_FILL if expanded else Control.SIZE_SHRINK_END
	toggle.text = ("▾ " if expanded else "▸ ") + "Correspondences and dignities"


func is_expanded() -> bool:
	return text_view.visible


func clear() -> void:
	text_view.text = ""
	_paragraph_of_slot.clear()
	toggle.disabled = true


func show_summary(summary: ReadingSummary) -> void:
	text_view.clear()
	_paragraph_of_slot.clear()
	toggle.disabled = false
	var muted: String = ReaderTheme.MUTED.to_html(false)
	var brass: String = ReaderTheme.BRASS.to_html(false)
	for entry: Dictionary in summary.positions:
		_paragraph_of_slot.append(text_view.get_paragraph_count() - 1)
		var card: Dictionary = entry["card"]
		var dignity: Dictionary = entry["dignity"]
		text_view.append_text("[color=#%s][b]%s[/b][/color] — %s\n" % [
			brass, _escape(card["name"]), _escape(Spread.title(entry["name"]))])
		text_view.append_text("[color=#%s][i]%s[/i][/color]\n" % [muted, _escape(entry["meaning"])])
		text_view.append_text("[indent]")
		for line: String in summary.display_facts(card):
			text_view.append_text("%s\n" % _escape(line))
		text_view.append_text("[color=#%s]%s[/color][/indent]\n\n" % [
			ReaderTheme.dignity_color(dignity["state"]).to_html(false),
			_escape(Dignities.describe(dignity))])
	text_view.append_text("[color=#%s][b]Patterns[/b][/color]\n" % brass)
	text_view.append_text("[indent]%s[/indent]" % _escape("\n".join(summary.display_patterns())))


## Opens the panel at a card's entry.
func show_slot(slot: int) -> void:
	if slot < 0 or slot >= _paragraph_of_slot.size():
		return
	set_expanded(true)
	text_view.scroll_to_paragraph.call_deferred(maxi(0, _paragraph_of_slot[slot]))


func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
