class_name CardView
extends Control
## One card on the table. The only place a card's look is decided: the deck's image,
## or a placeholder face when there is no deck art. Adapted from KitsuTarot's CardView.

signal pressed(view: CardView)

## Real tarot proportions (most deck scans are about 0.58 wide to 1 tall).
const ASPECT: float = 0.58
const FLIP_TIME: float = 0.16
const LIFT: float = 10.0

const BACK_FILL: Color = Color("#1d1d33")
const EDGE: Color = Color(0.05, 0.05, 0.08)
const ELEMENT_TINTS: Dictionary = {
	"fire": Color("#b8664a"), "water": Color("#4f78a8"), "air": Color("#c9b46b"),
	"earth": Color("#6f8f5a"),
}

## Width / height of this card: the deck's own shape (DeckImages.aspect), else ASPECT.
var aspect: float = ASPECT
## Canonical index, or -1 for a plain back (the pile, the cut fan).
var index: int = -1
var face_up: bool = false
var images: DeckImages
## For the placeholder face when the deck has no image.
var card_data: Dictionary = {}
var highlighted: bool = false:
	set(value):
		highlighted = value
		queue_redraw()
## 0..1: a soft brass halo, raised in turn while the reader studies the spread.
var glow: float = 0.0:
	set(value):
		glow = value
		queue_redraw()
## The position number, drawn in the top corner (close-packed spreads); "" for none.
var badge: String = "":
	set(value):
		badge = value
		queue_redraw()
## The dignity glyph (▲ ▼ ·) drawn in the bottom corner, in mark_color; "" for none.
var mark_text: String = "":
	set(value):
		mark_text = value
		queue_redraw()
var mark_color: Color = ReaderTheme.MUTED
## Lifts a little under the mouse (the cut fan).
var lift_on_hover: bool = false
## How far the card rises while hovered (lift_on_hover).
var lift: float = LIFT
var clickable: bool = true:
	set(value):
		clickable = value
		mouse_default_cursor_shape = CURSOR_POINTING_HAND if value else CURSOR_ARROW

## An empty position waiting for the card the querent laid there (own cards): an
## outline instead of a card.
var empty: bool = false:
	set(value):
		empty = value
		queue_redraw()

var _hovered: bool = false


func _init(card_index: int = -1, deck_images: DeckImages = null, data: Dictionary = {}) -> void:
	index = card_index
	images = deck_images
	aspect = images.aspect if images != null else ASPECT
	card_data = data
	mouse_filter = MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_entered.connect(func() -> void: _set_hovered(true))
	mouse_exited.connect(func() -> void: _set_hovered(false))


## Sets the card's size from its height, keeping the pivot centred for flips and turns.
func set_height(height: float) -> void:
	var wanted: Vector2 = Vector2(roundf(height * aspect), roundf(height))
	# The minimum first: a size below the old minimum would be held at it.
	custom_minimum_size = wanted
	size = wanted
	pivot_offset = size / 2.0
	queue_redraw()


## Turns the card face up with a flip (squash to nothing, swap the face, open again).
func flip_up(delay: float = 0.0, motion: float = 1.0) -> void:
	if face_up:
		return
	var tween: Tween = create_tween()
	tween.tween_interval(delay * motion)
	tween.tween_property(self, "scale:x", 0.0, FLIP_TIME * motion)
	tween.tween_callback(func() -> void:
		face_up = true
		queue_redraw())
	tween.tween_property(self, "scale:x", 1.0, FLIP_TIME * motion)


## Shows another card here, turning it face up with a flip.
func set_card(card_index: int, data: Dictionary, motion: float = 1.0) -> void:
	index = card_index
	card_data = data
	empty = false
	face_up = false
	flip_up(0.0, motion)


func set_images(deck_images: DeckImages) -> void:
	images = deck_images
	aspect = images.aspect if images != null else ASPECT
	set_height(size.y)


func _gui_input(event: InputEvent) -> void:
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and clickable:
		pressed.emit(self)
		accept_event()


func _set_hovered(value: bool) -> void:
	_hovered = value
	if lift_on_hover:
		position.y += -lift if value else lift
	queue_redraw()


func _draw() -> void:
	var box: Rect2 = Rect2(Vector2.ZERO, size)
	if empty:
		_draw_empty(box)
		return
	var art: Texture2D = null
	if images != null:
		art = images.texture(index) if face_up and index >= 0 else images.back_texture()
	if art != null:
		draw_texture_rect(art, box, false)
	elif face_up:
		_draw_placeholder_face(box)
	else:
		_draw_placeholder_back(box)
	_draw_glow(box)
	var edge: Color = ReaderTheme.BRASS if highlighted or (_hovered and clickable) else EDGE
	if glow > 0.0 and edge == EDGE:
		edge = EDGE.lerp(ReaderTheme.BRASS.lightened(0.2), glow)
	draw_rect(box, edge, false, 2.0 if edge != EDGE else 1.0)
	# Corners stay visible even under the crossing card of a Celtic Cross.
	var radius: float = maxf(8.0, size.x * 0.15)
	if badge != "":
		_draw_disc(Vector2(radius + 3.0, radius + 3.0), radius, badge, ReaderTheme.TEXT)
	if mark_text != "" and face_up:
		_draw_disc(size - Vector2(radius + 3.0, radius + 3.0), radius, mark_text, mark_color)


func _draw_glow(box: Rect2) -> void:
	if glow <= 0.0:
		return
	for ring: int in 3:
		draw_rect(box.grow(2.0 + ring * 2.5), Color(ReaderTheme.BRASS.lightened(0.15),
				glow * (0.85 - ring * 0.3)), false, 2.5)


## A small dark disc with a brass ring and `text`, kept upright when the card is turned.
func _draw_disc(centre: Vector2, radius: float, text: String, color: Color) -> void:
	draw_circle(centre, radius, Color(ReaderTheme.BACKGROUND, 0.88))
	draw_arc(centre, radius, 0.0, TAU, 24, Color(ReaderTheme.BRASS, 0.8), 1.5)
	var font: Font = get_theme_default_font()
	var font_size: int = int(radius * 1.25)
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_set_transform(centre, -rotation, Vector2.ONE)
	draw_string(font, Vector2(-text_size.x / 2.0, font.get_ascent(font_size) - text_size.y / 2.0),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	draw_set_transform(Vector2.ZERO)


func _draw_empty(box: Rect2) -> void:
	_draw_glow(box)
	var lit: bool = highlighted or (_hovered and clickable)
	draw_rect(box, Color(ReaderTheme.BRASS, 0.12 if lit else 0.06), true)
	draw_rect(box, Color(ReaderTheme.BRASS, 0.9 if lit else 0.45), false, 1.5)
	var arm: float = minf(box.size.x, box.size.y) * 0.12
	var centre: Vector2 = box.get_center()
	var cross: Color = Color(ReaderTheme.BRASS, 0.8 if lit else 0.5)
	draw_line(centre - Vector2(arm, 0), centre + Vector2(arm, 0), cross, 2.0)
	draw_line(centre - Vector2(0, arm), centre + Vector2(0, arm), cross, 2.0)
	if badge != "":
		var radius: float = maxf(8.0, size.x * 0.15)
		_draw_disc(Vector2(radius + 3.0, radius + 3.0), radius, badge, ReaderTheme.TEXT)


func _draw_placeholder_back(box: Rect2) -> void:
	draw_rect(box, BACK_FILL)
	var inset: Rect2 = box.grow(-size.x * 0.08)
	draw_rect(inset, Color(ReaderTheme.BRASS, 0.45), false, 1.0)
	var centre: Vector2 = box.get_center()
	var radius: float = size.x * 0.18
	draw_arc(centre, radius, 0, TAU, 32, Color(ReaderTheme.BRASS, 0.6), 1.5)


func _draw_placeholder_face(box: Rect2) -> void:
	var element: Variant = card_data.get("dignity_element")
	var tint: Color = ELEMENT_TINTS.get(element, ReaderTheme.MUTED)
	draw_rect(box, Color("#ebe4d3"))
	draw_rect(Rect2(0, 0, size.x, size.y * 0.06), tint)
	draw_rect(Rect2(0, size.y * 0.94, size.x, size.y * 0.06), tint)
	var font: Font = get_theme_default_font()
	var text: String = str(card_data.get("name", "?"))
	var font_size: int = maxi(10, int(size.x / 8.0))
	draw_multiline_string(font, Vector2(6, size.y * 0.42), text, HORIZONTAL_ALIGNMENT_CENTER,
			size.x - 12, font_size, 3, Color("#2a2533"))
