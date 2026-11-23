# Your own card meanings

TarotTerminal ships two meanings for every card: Waite's (*The Pictorial Key to the
Tarot*, 1911) and the Golden Dawn's (*Book T*). The reader works from those. Add your own
and the reader gives them the most weight, so readings come out in your terms.

## Where the file goes

- In this folder, as `meanings.json`: the `local` folder next to `TarotTerminal.exe`.
- Running from source: `local/meanings.json` in the project (git-ignored).

The file is read when the app starts, so restart it after a change.

## The format

One JSON object, keyed by card number (as text), each with any of three fields:

- `personal`: your own reading of the card. The reader leans on it most.
- `gd`: replaces the shipped Golden Dawn meaning.
- `waite`: replaces the shipped Waite meaning.

Only the fields you write change. Leave a field out and the shipped text stays.

```json
{
  "0": {"personal": "A leap before looking; trust in the new."},
  "16": {"personal": "What was built on a false footing falls.", "gd": "Ambition, fighting, war"},
  "36": {"personal": "An offer of love, or the start of it."}
}
```

## Card numbers

| Numbers | Cards |
|---|---|
| 0–21 | The trumps, Fool to World (Strength is 8, Justice 11) |
| 22–35 | Wands: Ace, 2–10, Page, Knight, Queen, King |
| 36–49 | Cups, in the same order |
| 50–63 | Swords |
| 64–77 | Pentacles |

For example: the 7 of Wands is 28, the Page of Wands 32, the Ace of Cups 36, the King
of Pentacles 77.

A mistake in the file (a number that isn't a card, or text that isn't JSON) is skipped,
and the rest still loads.
