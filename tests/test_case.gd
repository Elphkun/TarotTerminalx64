extends RefCounted
## Base class for tests. Test files use `extends "res://tests/test_case.gd"`
## and define test_* methods. Adapted from KitsuTarot.

var failures: Array[String] = []
var assertions: int = 0

var _db: CardDb


## The real data in res://data, loaded once per test instance.
func db() -> CardDb:
	if _db == null:
		_db = CardDb.load_from(CardDb.DEFAULT_DIR)
	return _db


func assert_true(condition: bool, message: String = "expected true") -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func assert_false(condition: bool, message: String = "expected false") -> void:
	assert_true(not condition, message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	assertions += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%sexpected %s, got %s" % [
			_prefix(message), str(expected), str(actual),
		])


## A three-card layout of the given card ids in the three_card spread.
func three_card(ids: Array) -> Array[Dictionary]:
	var cards: Array[int] = []
	for id: String in ids:
		cards.append(int(db().by_id(id)["index"]))
	return spread3().lay_out(cards)


func spread3() -> Spread:
	return Spread.from_db(db(), "three_card")


func _prefix(message: String) -> String:
	return "" if message == "" else "%s: " % message
