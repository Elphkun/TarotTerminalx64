# Adding your own spreads

TarotTerminal ships with its own spreads. You can add more: put a `.json` file in the
`spreads` folder next to `TarotTerminal.exe` (the project's `spreads/` folder when
running from Godot). The spread menu looks in the folder every time it opens, so there
is no need to restart. A file can hold one spread or several.

A spread that can't be used is still listed, greyed out as "(cannot load)"; hover over
it to see what is wrong.

## The spread designer

The easiest way is Settings → Spreads → **Design…**, which opens the designer in a
window of its own:

- **Cards:** double-click the table (or press Add card) to add a card. Drag it to place
  it. Hold Shift to snap its centre to the grid (16, 32 or 64 pixels, from the Grid
  menu), which starts at the deck's centre, so cards line up with the deck and each
  other. Hold Alt to move it straight across or down, or nudge it with the arrow keys
  (Shift for bigger steps).
- **Turning:** hold Ctrl and drag a card, or drag the round knob above the selected
  card, to turn it in eighths of a turn. The Rotation field takes any angle.
- **Dignity lines:** drag from the glowing ring just outside a card's edge (it lights
  up under the mouse) onto another card, or its ring, to make the two neighbours for
  dignities. The eight nodes on a card's corners and sides work too.
  Click a line to select it.
- **Deleting:** Delete removes the selected card (with its lines) or line.
- **Zoom and pan:** the mouse wheel zooms in on the point under the mouse, dragging with
  the middle button moves the view, and a middle double-click fits the whole table again.
  The reading table zooms and pans the same way.
- **Up to 12 cards:** every card's correspondences and dignities go to the reader, and
  the reading covers each position, so a spread holds at most 12 cards.
- **Crossing cards:** drop a card onto another, and the designer offers to lay it over
  that card, as the Celtic Cross's crossing card lies over the first.
- **Fields:** the side panel holds the spread's fields and the selected card's id,
  name, meaning and rotation. The position list sets the reading order.
- **An open canvas:** the outline marked "shown at full size" is the reading window's
  card area; card sizes are a share of its height. Cards can go past it, up to one
  outline's width or height beyond each edge. A spread that does is shown whole on the
  reading table, zoomed out to fit (the note under the canvas says how small), and
  any card can still be clicked to see it large. The middle double-click fits the view
  to everything again.
- **Table shapes:** the table menu shows the table in a 1280×720 window and a smaller
  one. Anything that would stop the spread loading, or a card that covers the deck or
  overlaps another, is listed under the table, and Save waits until the list is empty.
- **Saving:** a new spread is saved as `<id>.json` in the spreads folder; a spread
  opened from a file is saved back into it. A built-in spread opens as a copy to adapt,
  and the built-in one is never changed.

The rest of this page describes the file the designer writes, for editing by hand.

## The format

The file is a JSON object of spreads, keyed by an id of your choosing (letters, digits
and underscores; it must differ from the built-in ids `three_card`, `celtic_cross`,
`planetary_orbit` and `single`, and from every other added spread).

```json
{
	"horseshoe": {
		"name": "Horseshoe",
		"source": "Where the spread comes from, for your own reference",
		"reading_words": "500 to 700",
		"positions": [
			{"id": "past", "meaning": "The past", "x": 0.1, "y": 0.3},
			{"id": "present", "meaning": "The present", "x": 0.3, "y": 0.6},
			{"id": "hidden", "name": "hidden influences", "meaning": "What is hidden", "x": 0.5, "y": 0.8},
			{"id": "obstacles", "meaning": "Obstacles", "x": 0.7, "y": 0.6},
			{"id": "outcome", "meaning": "The likely outcome", "x": 0.9, "y": 0.3}
		],
		"dignity_adjacency": [
			["past", "present"],
			["present", "hidden"],
			["hidden", "obstacles"],
			["obstacles", "outcome"]
		]
	}
}
```

### Spread fields

| Field | Needed | What it does |
|---|---|---|
| `name` | no (the id is used) | Shown in the spread menu and the exported reading. |
| `positions` | **yes** | The positions in dealing order; see below. |
| `dignity_adjacency` | no | Pairs of position ids that count as neighbours when the elemental dignities are worked out. A card with no neighbours is neither well nor ill dignified. |
| `reading_words` | no ("300 to 500") | How long a reading the model is asked for. |
| `card_height` | no (0.42) | Card height as a share of the table's height (0.21 = about a fifth, 1 = as tall as the table). Smaller for spreads with many cards. Cards also stay narrow enough for `columns` to fit across, so a big height may need fewer columns. The designer shows the default as "Auto". |
| `columns` | no (cards + 1.5) | How many card widths must fit across the table; the cards shrink to fit. |
| `compact_labels` | no (false) | `true` draws each position's number and dignity mark on the card instead of a label underneath. Use it when cards sit close together. |
| `source` | no | A note for you (credit, link); not shown or sent. |

### Position fields

| Field | Needed | What it does |
|---|---|---|
| `id` | **yes** | A short id, unique within the spread. |
| `meaning` | **yes** | What the position means. Sent to the model and shown in the correspondences panel. |
| `name` | no (the id) | The position's name as it sits mid-sentence, in lower case unless it is a proper name ("hopes and fears", "Mars"). |
| `x`, `y` | **yes** | Where the card's centre sits: 0 to 1 spans the table across and down (to the right of the deck). Values from -1 to 2 lay cards past the table; the table then shows the whole spread smaller. |
| `rotation` | no (0) | Degrees clockwise; 90 lays the card sideways. |
| `over` | no | The id of a position this card lies across, as the Celtic Cross's second card does. |

Cards are tall: at the default size one card takes about a fifth of the table's height
and a tenth of its width, so leave about 0.22 between rows and 0.12 between columns, or
make the cards smaller with `card_height`.
