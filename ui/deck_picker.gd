class_name DeckPicker
extends OptionButton
## Deck dropdown. Rescans the deck folders every time it is opened, remembers the
## choice in AppSettings, and lists broken decks greyed out with their problems as a tooltip.

signal deck_changed(deck: DeckInfo)

var settings: AppSettings
var decks: Array[DeckInfo] = []


func _ready() -> void:
	if settings == null:
		settings = AppSettings.load_from()
	get_popup().about_to_popup.connect(refresh)
	item_selected.connect(_on_item_selected)
	refresh()
	deck_changed.emit(selected_deck())


## Rescans the deck folders and rebuilds the list, keeping the current choice.
func refresh() -> void:
	decks = DeckLibrary.scan(DeckLibrary.folders(settings))
	clear()
	if decks.is_empty():
		add_item("No decks in %s" % DeckLibrary.folder(settings))
		set_item_disabled(0, true)
		return
	var chosen: DeckInfo = settings.pick_deck(decks)
	for i: int in decks.size():
		var deck: DeckInfo = decks[i]
		add_item(deck.name if deck.is_valid() else "%s (cannot load)" % deck.name, i)
		set_item_disabled(i, not deck.is_valid())
		var notes: Array[String] = deck.errors + deck.warnings
		set_item_tooltip(i, "\n".join(notes))
		if deck == chosen:
			select(i)


func selected_deck() -> DeckInfo:
	var index: int = get_selected_id()
	return decks[index] if index >= 0 and index < decks.size() else null


func _on_item_selected(_index: int) -> void:
	var deck: DeckInfo = selected_deck()
	if deck == null:
		return
	settings.deck = deck.id
	settings.save()
	deck_changed.emit(deck)
