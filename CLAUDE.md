# TarotTerminal: Golden Dawn spread reader with a local LLM

A personal Godot project: a tarot spread reader. The app draws cards into a spread, computes Golden Dawn correspondences and elemental dignities **in code**, then hands a structured summary plus the querent's question to a **local LLM**, which writes the reading.

Core principle: **code does the esoteric bookkeeping, the LLM only interprets.** The LLM never decides correspondences or dignities. It receives them as facts.

## Stack

- **Engine:** Godot 4.x, GDScript.
- **LLM:** local server with an OpenAI-compatible API (llama.cpp server / Ollama / LM Studio) on `localhost`. Called with `HTTPRequest`, with streaming (SSE) so the reading appears as it's written.
- The endpoint URL, model name and API key go in settings so Claude or OpenAI can be swapped in later with no code changes.
- **Dev hardware:** 16 GB VRAM GPU. Target models are 12–14B dense or ~30B MoE quantized.

## Reference project

`../kitsu-tarot/` is a finished Godot French Tarot game by the same author. Read it for how card scenes, deck/shuffle logic, card flip animations and layout were done, then adapt that code here. Copy and rework it; don't link to it.

## Tradition and source decisions (fixed)

- Golden Dawn system per David Allen Hulse. The author verifies all data against Hulse.
- RWS numbering: Strength = 8, Justice = 11.
- **Trumps** = the 22 paths (11–32): Hebrew letter, element/planet/sign attribution, the two sephiroth each path connects.
- **Pips:** Ace = root of the element in Kether; 2–10 = sephiroth Chokmah–Malkuth in the suit's element, each also a decan (planet in sign) with its GD title.
- **Courts (Hulse mapping):** RWS Knight = GD Knight = Fire of; Queen = Water of; RWS King = GD Prince = Air of; RWS Page = GD Princess = Earth of.
- **The UI always says "Page"** (and the other RWS names). GD rank names appear only in the data and the LLM prompt. One exception (author's decision): the correspondences panel shows each card's GD title in quotes, even when the title contains a rank name ("Princess of the Shining Flame").
- **Suits:** Wands (Fire), Cups (Water), Swords (Air), Pentacles (Earth).
- **Dignities (Book T), stored as data, not hard-coded:** contrary = Fire/Water, Air/Earth; every other pairing is friendly; same element is strong. The GD reads no reversals; dignities do that job.
- **Celtic Cross (author's decision):** Waite's 1911 order (1 covers, 2 crosses, 3 crowns, 4 beneath, 5 behind, 6 before, staff 7–10 from the bottom up), no significator. Dignity neighbours run along the lines of the layout: 1–2, 3–1–4, 5–1–6, and 7–8–9–10.
- **Card meanings:** `waite` (Waite, 1911) and `gd` (Book T) are tradition and ship in `data/cards.json`. `personal` is the user's own and ships empty; `tests/test_data.gd` checks that. Users add theirs in the git-ignored `local/meanings.json`, which `CardDb.load_default()` lays over `cards.json` (`docs/card_meanings.md`). Hulse is credited in README.md's Sources and in Settings.
- **Private notes:** the author keeps private project notes in the git-ignored `CLAUDE.local.md`. Nothing from it goes into a tracked file, a commit message or anything public.

## Data files (`data/`)

### `cards.json`: 78 entries, keyed by canonical index

```json
{
  "id": "wands_page",
  "index": 32,
  "type": "court",
  "name": "Page of Wands",
  "suit": "wands",
  "rws_rank": "page",
  "gd_rank": "princess",
  "gd_title": "Princess of the Shining Flame",
  "element": "fire",
  "sub_element": "earth",
  "dignity_element": "fire",
  "meanings": { "waite": "", "gd": "", "personal": "" },
  "keywords": []
}
```

Fields by type:
- **trump:** `number`, `path`, `hebrew_letter`, `attribution {kind: element|planet|sign, value}`, `connects [sephira, sephira]`, `dignity_element` (may be `null` for planetary trumps; the dignity calculator then skips the card).
- **pip:** `rank` (1–10), `sephira`, `element`, `decan {planet, sign}` (null for Aces), `gd_title`.
- **court:** `rws_rank`, `gd_rank`, `element`, `sub_element`, `zodiac_span {from, to}` (null for Princesses/Pages), `gd_title`.
- `dignity_element` is its own field so the author can change it per card.
- `meanings` in `cards.json`: `waite` and `gd` filled, `personal` empty (see Tradition and source decisions). They're the author's text, never written or changed by Claude. Users add their own the same way (`docs/card_meanings.md`; a build has `local/README.md` next to the exe). The overlay file is `local/meanings.json` (`{index: {waite, gd, personal}}`). Tests and `verify_data.gd` load `cards.json` without the overlay (`CardDb.load_from(CardDb.DEFAULT_DIR)`).

### `correspondences.json`
Sephiroth (number, title, planet, notes), elements (suit, Tetragrammaton letter, notes), Hebrew letters, and the dignities table:

```json
"dignities": {
  "contrary": [["fire","water"],["air","earth"]],
  "friendly": [["fire","air"],["fire","earth"],["water","air"],["water","earth"]]
}
```

### `spreads.json`
Each spread: name, positions (`id`, `meaning`, normalized `x`/`y`, optional rotation) and `dignity_adjacency` (pairs of positions that count as neighbors for dignities). Spreads: `three_card` (Past/Present/Future), `celtic_cross`, `planetary_orbit` (Rainwolf; dignities along the spiral) and `single` (one card, no neighbours, so always neutral). The menu remembers the last spread chosen (`AppSettings.spread`).

Optional fields:
- Per position: `name` (shown and sent to the model instead of the id, lower case: "hopes and fears") and `over` (this card lies over that position, as the crossing card does; the layout test allows that overlap).
- Per spread: `reading_words` (the length asked of the model, default "300 to 500"), `card_height` (share of the table's height), `columns` (card widths that must fit across), and `compact_labels` (number and dignity mark drawn on each card instead of labels underneath, for close-packed spreads).

`tests/test_spreads.gd` checks every spread's data and that no cards overlap or leave the table at two table sizes, so a new spread only needs its JSON.

**Added spreads (the user's own):** every `.json` file in a `spreads/` folder (next to the exe in a build; the project's git-ignored `spreads/` from source), same format, one or more spreads per file. `SpreadLibrary.scan()` reads and checks them (`SpreadLibrary.validate()`, which the built-in spreads also pass). `CardDb.set_added_spreads()` adds the usable ones after the built-ins, which are never replaced (`builtin_spread_ids`). The spread menu rescans each time it opens; a spread with problems is listed disabled as "(cannot load)", with the reasons as its tooltip. The format is documented for users in `docs/custom_spreads.md`, and the build copies that file to `spreads/README.md`. A test checks that its example is valid.

**Spread designer** (Settings → Spreads → "Design…", `App.open_designer()`):
- **Pieces:** `ui/spread_designer_window.gd` is a `Window` with `force_native` set on desktop, so it is a separate OS window; the root keeps embedding every other window. It is embedded in headless runs. It holds `ui/spread_designer.gd` (toolbar, fields, problems), `ui/spread_canvas.gd` (the table) and `core/spread_draft.gd` (the edits and saving, with no UI).
- **Geometry:** the canvas places cards with `TableView`'s statics (`card_height_for`, `slot_centre_for`, `normalized_for`, `pile_position_for`), which the table itself uses, so the designer shows exactly what the table will.
- **Controls:**
  - drag to move (Shift snaps to the grid, Alt locks the axis; arrow keys nudge);
  - Ctrl+drag or the knob turns in 45° steps;
  - drag from a card's grab ring (`SpreadCanvas.ring_at`: RING_OUTSIDE screen px outside its edge to RING_INSIDE inside, at any zoom; drawn as the reading table's study glow, faint on hover, full in the ring) or one of the eight nodes onto another card or its ring to add a dignity pair;
  - double-click adds a card; Delete removes a card or line;
  - dropping a card on another offers `over`.
- **Checks:** `SpreadLayout.problems()` (`ui/spread_layout.gd`) checks for cards covering the pile or overlapping, without `over`. It runs on both `SpreadLayout.TABLE_SIZES` using real rotated outlines (`Geometry2D`), so any angle is checked. `tests/test_spreads.gd` uses it too. The designer adds `SpreadLibrary.validate()` and the id checks, and Save waits until there are no problems.
- **Open canvas:** x/y may run from -1 to 2 (`SpreadLibrary.REACH`), so a spread is shown at a third of full size at the smallest; 0 to 1 is the table. The designer labels the table's outline "shown at full size".
- **Grid:** Shift-drag snaps a card's centre to the grid (`SpreadCanvas.grid`, 16/32/64 table px from the toolbar). The grid starts at the deck's centre (`grid_origin()`) and is drawn only while snapping. Alt locks the drag to one axis.
  - `SpreadLayout.bounds()` is the table, deck, turned cards and labels. `fit_scale()` is how much the table shrinks to show all of that. It is 1 for every built-in spread, which a test checks.
  - `TableView` applies it as `_fit` under the user's zoom (`view_scale()`), so a spread past the table is shown whole and smaller.
  - The designer canvas fits its view to `bounds()` only on open, on a table-shape change and on a middle double-click, so the view doesn't move while cards are dragged. It draws the table's outline and a dashed outline of the whole layout, and notes the size readings show it at.
- **Saving:** a new spread goes to `<spreads folder>/<id>.json`; a spread opened from a file goes back into that file, keeping its other spreads. Built-in spreads open as "<name> (copy)" and are never written.
- **Labels:** labels on the table sit below a turned card's lowest corner.
- **Card limit:** a spread has at most `SpreadLibrary.MAX_POSITIONS` (12) positions, checked by `validate()` for hand-written files too. This keeps the prompt and the reading within what a local model handles. `SpreadDraft.add_position` refuses a 13th card.

**Zoom and pan** (the reading table and the designer canvas):
- **Controls:** the wheel zooms about the mouse, a middle-drag pans, and a middle double-click shows the whole table.
- **Reading table:** `TableView` keeps its cards and labels in `_content`, which it scales and moves (`zoom_at`, `pan_by`, `reset_view`). The lightbox stays outside `_content`. Zoom runs from 1 (the whole spread) to 4. Panning keeps the layout covering the view, or centred where it is smaller. A new spread resets the view.
- **Input on the table:** it listens in `_input`, because the cards stop mouse events. It only acts while `gui_get_hovered_control()` is the table or one of its cards, so dialogs above it are left alone.
- **Designer canvas:** zoom runs from 0.5 to 4 times the fitted size. Hit testing goes through `to_table()`, so clicks land right at any zoom.

## Canonical index scheme

Images are `0.jpg`–`77.jpg`:

| Range | Cards |
|---|---|
| 0–21 | Trumps |
| 22–35 | Wands |
| 36–49 | Cups |
| 50–63 | Swords |
| 64–77 | Pentacles |

Within a suit: Ace = +0, 2–10 = +(rank−1), Page = +10, Knight = +11, Queen = +12, King = +13.
Checks: 7 of Wands = 28, Page of Wands = 32, Ace of Cups = 36, Ace of Swords = 50, King of Pentacles = 77.

## Decks (hot-swappable)

- Decks live in the project's `decks/` folder by default (in an exported build, a `decks/` folder next to the executable); the folder can be changed in settings. They are loaded at runtime with `Image.load_from_file()` and never imported. Decks that can't be distributed must never end up in git or an export: `decks/` is git-ignored apart from its `.gdignore`, which keeps Godot from importing or exporting it.
- The ten decks in `decks/` now (Baroque, Dark Fantasy, Etching, HD, Mystical, Pastel, Steampunk, Synthwave, Ukiyoe, Vibrant; 810×1440 JPEG, about 225 MB, converted from the author's 1080×1920 PNG originals, which they keep backed up) are the author's own work and may be redistributed freely; each has `"distributable": true` in its `deck.json`. They still stay out of git for their size; a release bundles them next to the executable.
- "Rider Waite (LuciellaES)" (300×527 PNG, `back.png`, 22 MB) is Luciella Elisabeth Scarlett's CC0 Rider-Waite-Smith (https://luciellaes.itch.io/rider-waite-smith-tarot-cards-cc0), credited in README. It is distributable too; its `deck.json` also records `artist`, `license` and `source`, which the loader ignores.
- Each deck folder: `0.jpg`–`77.jpg`, `back.jpg`, `deck.json`:

```json
{
  "name": "Rider-Waite-Smith",
  "back": "back.jpg",
  "court_order": ["page", "knight", "queen", "king"],
  "index_overrides": {},
  "distributable": false
}
```

- `suit_order` (optional) says which suit fills files 22–35, 36–49, 50–63, 64–77 in this deck, for decks that put Swords before Cups.
- `court_order` says how ranks are arranged at suit offsets +10..+13 in this deck.
- Image quality:
  - Cards load scaled down with Lanczos to `ReadingScreen.card_image_height()`: half the screen height × Interface size, kept within 720–1440 px. They get mipmaps, so they shrink cleanly to the ~190 px of a Celtic Cross.
  - Each deck is drawn at its own shape (`DeckImages.aspect`, measured from the back or card 0, kept within 0.45–0.75), for example 0.5625 for 1080×1920 scans.
  - Make the back the same size as the cards.
  - A deck with no back is still valid: the app draws its own back and `deck_check` warns.
- Card files are found by number, so `7.jpg`, `07.jpg` and `007.png` all count as file 7; `deck.json` is optional, and every field defaults to the canonical layout.
- `godot --headless --script tools/convert_decks.gd -- [--dry-run] [--skip=FOLDER] [--height=1440] [--quality=90] [deck folders]` shrinks decks to JPEGs no taller than the app's 1440 px cap and **deletes the originals** (`tools/deck_converter.gd`; updates `deck.json`'s `back`). With no folders it does every deck; the LuciellaES deck was left as it came (`--skip`).
- `godot --headless --script tools/deck_check.gd` checks every deck and loads every image; `godot --path . res://tools/deck_viewer.tscn` shows a deck in canonical order so the mapping can be checked by eye.
- `index_overrides` maps canonical index → file index (e.g. `{"8": 11, "11": 8}` for Marseille-numbered decks).
- Settings has a deck dropdown that rescans the folder.

## Reading pipeline

1. **Question.** The user enters a question and picks a spread.
2. **Classify (LLM call 1, short, JSON output):** life area, timeframe, yes/no vs open-ended, and `harm`.
   - It never thinks, whatever Settings says (`"thinking": false` in the call's options): `qwen3.5:4b` thought for 8,192 tokens, twice, and gave no verdict. It also takes about half a second instead of 3 to 20.
   - It starts at the shuffle (or Lay out, or Re-read). Dealing, picking and placing own cards wait for it (`ReadingSession.is_weighing()`). It is also when a model loads, so it shows: the panel's "weighing" phase with its timer, and `TableView.set_weighing()`'s glow on the deck, the empty positions or the cards.
   - `harm: true` means the question asks whether, when or how to kill, injure, abuse or torment someone, the querent included. The session then refuses (`refused`, `ReadingSession.REFUSAL`, step DONE): no card is dealt and no reading is asked for. Empty own-card positions are cleared; cards being read again stay.
   - A reply with no verdict (some models answer the question instead) is asked for once more as JSON (`ReadingPipeline.harm_verdict`). A failed call is not.
   - Only a clear true counts. If the model fails or still can't say (`ReadingPipeline.weigh_problem`), the reading goes ahead with a note under it (`unweighed`), and `prompts/read_harm_rule.txt` goes into the system prompt as the backstop.
   - A question weighed as harmless gets only `read_system.txt`'s one line against advising harm (`ReadingPipeline.harm_rule`). Sent with every reading, the whole rule made models open ordinary readings with a refusal, repeating its quoted example. So keep quoted openings out of it.
3. **Draw.** Shuffle, optionally cut (a cut leaves the deck shuffled), then either Deal (the top cards) or click the deck to fan it and pick the N cards face down (`ReadingSession.pick(at)`, in pick order; `TableView.take_from_fan`). `ReadingSession.draw` records "app", "picked" or "own" for the history and the export.
4. **Compute (code):**
   - Per card: full data entry + position meaning.
   - Elemental dignities for each card from its adjacent positions → well-dignified / ill-dignified / neutral, with the reason.
   - Spread patterns: count of each element, trumps vs pips vs courts, repeated numbers, which court roles appear.
5. **Read (LLM call 2, streamed):** system prompt (reader persona + rules) + few-shot example readings + the computed summary + the question. The model reads each position against the question, then writes a synthesis that must refer to the computed dignities and patterns.
6. **Critique (optional LLM call 3):** checks that the reading answered the question and didn't ignore any ill-dignified card; revises if needed.
7. **Display.** Streamed reading text, plus a collapsible panel listing the correspondences and dignities used.

Prompts live in `prompts/` as plain text templates, not hard-coded strings, so they can be edited without touching code.

The few-shot examples are the author's own edited readings, at most three (`ReadingExamples.LIMIT`), separated by lines holding only `---`. "Save as example…" on the finished-reading screen and Settings → Examples → "Manage…" open the same Example readings dialog (list, edit, delete; nothing is written until Save). They live in `prompts/read_examples.txt` (`user://read_examples.txt` in an exported build). That file holds real questions, so it is git-ignored; while it is missing or starts with `[PLACEHOLDER]`, no examples are sent.

## Milestones

1. **Data skeleton.** Generate all 78 entries of `cards.json` plus `correspondences.json` from standard GD tables. Leave meanings empty. Print a verification table (index, name, path/letter/attribution or sephira/decan, GD title) for the author to check against Hulse. **Flag anything uncertain; don't guess quietly.**
2. **Headless core.** Deck/card data loading, the index↔card mapping, the dignities calculator and the spread pattern summary as plain GDScript classes with no UI. A headless runner script (`godot --headless --script`) draws a three-card spread, prints the computed summary, sends it to the local LLM and prints the reading. Prompt iteration happens here.
3. **Deck loader.** Runtime loading from the deck folder, `deck.json` parsing, `court_order` / `index_overrides`, deck dropdown.
4. **Godot UI.** Question entry, spread selection, shuffle/cut, dealing animation and card flips (adapted from KitsuTarot), streamed reading panel, correspondences panel.
5. **Settings.** LLM endpoint/model/key, deck folder, temperature, critique pass on/off.
6. **Later:** Celtic Cross (done) and other spreads, reading history saved to disk, API backends (Claude/OpenAI), a release build bundling only `distributable: true` decks.

## Running and testing

Godot 4.7 (`C:\Users\elphk\Godot\Godot_v4.7.2-stable_win64_console.exe`). `--script` does not scan for classes, so after adding a `class_name` run `godot --headless --import` once.

- App: `godot --path .`
- Unit tests: `godot --headless --script tests/run_tests.gd`
- UI smoke test (real buttons, fake LLM): `godot --headless --script tests/ui_smoke.gd -- --readings=4`. Without `--headless`, `--shots=<dir>` saves a screenshot of each step; `--live=1` uses the real LLM instead, and `--spread=celtic_cross` picks the spread for it (reading 1 is always a Celtic Cross).
- Context window: prompt, examples, hidden thinking and reply must all fit in the window.
  - **Ollama native (the default with Ollama).** `OpenAiClient` asks `GET /api/version` once (Settings → API "Automatic"; `LlmConfig.backend`). If it answers, the client uses Ollama's `/api/chat` (`llm/ollama_api.gd`, NDJSON stream via `llm/ndjson_parser.gd`).
    - Every call sends `options.num_ctx` = Settings → Context window, the same for classify, read and critique: Ollama reloads the model whenever num_ctx changes. So the server needs no `OLLAMA_CONTEXT_LENGTH`.
    - Tested live: the model loads at the window asked for.
  - **OpenAI-compatible (`/v1`, other servers).** The window can't be set: Ollama ignores `num_ctx` there and loads 4096 by default. Settings → Test reads the real window from `/api/ps`.
  - **Either way:** the reading warns when the prompt plus Max tokens won't fit, and a reply cut off (`finish_reason` / `done_reason` "length") is an error with Retry.
- Thinking (`LlmConfig.thinking`, Settings → Thinking):
  - **Off:** native sends `think: false`; `/v1` sends `"reasoning_effort": "none"`.
  - **On:** `think` is left out (the model's default), because `think: true` is an HTTP 400 for models that can't think. If a model refuses `think: false`, the call is retried without it; so is a `/v1` call whose server refuses `reasoning_effort` (`OpenAiClient.refuses_reasoning`).
- `keep_alive` (llm.json only, default "30m") is how long Ollama keeps the model loaded.
- Headless reading for prompt work: `godot --headless --script tools/read.gd -- --question="..."`
- Comparing models on the same cards: `godot --headless --script tools/compare.gd -- --question="..." --models=a,b@thinking=0 --runs=3 --weigh` writes a table and every reading to `user://compare/` (Markdown and JSON). It skips a model that doesn't fit on the graphics card (`--allow-cpu` reads anyway), stops a slow reading (`--limit`), and unloads each model. The checks are in `tools/reading_checks.gd`; they say whether a reading did what the prompt asks, not how good it is.
- **After changing `prompts/classify_system.txt`**, weigh harmful and merely dark questions on several models (`--runs=0 --weigh`). Wording that stops one kind of mistake makes the other in small models.
- GDScript warnings (as the editor shows them): `bash tools/check_warnings.sh` lists every warning by file and line and should report 0. `--strict` adds the opt-in typing warnings (untyped, unsafe, discarded return values); those aren't kept at zero. A warning that is a false alarm gets a statement-level `@warning_ignore` with a comment saying why. The usual one is `redundant_await` on `LlmClient` calls, whose base methods return at once while real backends stream; a function-level `@warning_ignore` does not cover the statements inside it.
- If a windowed run logs `Unrecognized UID: "uid://cpkwuqxyl2xca"` (the project icon), `.godot/uid_cache.bin` is stale: close the editor, delete it, and run `godot --headless --import`. `App.apply_window_icon()` falls back to the icon's file meanwhile.
- Data check and verification table: `godot --headless --script tools/verify_data.gd`
- Deck check: `godot --headless --script tools/deck_check.gd`; deck viewer: `godot --path . res://tools/deck_viewer.tscn`
- Windows build: `bash tools/build_windows.sh [--debug] [--no-decks]`.
  - It exports the "Windows Desktop" preset (`export_presets.cfg`) to `build/windows/TarotTerminal.exe`, with the pck embedded.
  - The preset adds `prompts/*.txt` (examples included: two of the author's ship as the starting set) and leaves out `tests/`, `tools/`, `docs/` and `build/`.
  - The script copies the `distributable: true` decks to `build/windows/decks/` and writes `build/windows/spreads/README.md`.
  - `tools/check_private.sh` stops the build if the project or the built folder holds the builder's server address or API key (read from their `llm.json`), or a Tailscale address. The project is searched before the export, because packed scripts are compressed.
  - `build/` holds a `.gdignore` (the script recreates it). Without it, Godot imports the copied decks and packs them into the next exe.
  - The exe should be about 110 MB. Check the export log's "Storing File" lines for anything from `decks/`, `local/` or `build/`.

First run: after the splash, `ui/notice_dialog.gd` (the author's entertainment-only notice and disclaimer) covers the app until "I agree"; Quit closes the app. Agreeing saves `notice_accepted` = `NoticeDialog.VERSION` in `user://settings.json` (`App.show_notice_if_needed()`). Raise `VERSION` when the wording changes, to ask again.

The window opens where it was last closed (`ui/window_place.gd`, `user://window.json`, saved on the close request; maximized is remembered too). `WindowPlace.fit()` moves a saved place back onto the screen it mostly covers, or the first screen if that one is gone, and shrinks it to fit, leaving room for the title bar. With no saved place the window is centred. Tests point `App.window_place_path` elsewhere.

The window: stretch mode `disabled`, so a bigger window gives the layout more room at the same text size. `App.scale_for()` sets the content scale to Settings → Interface size (100–200%), shrinking only when the window can't hold 1280×720 at that size; on desktop the window's minimum is 1280×720 × Interface size. The smoke test takes `--ui_scale=1.5`, and `godot --resolution 1920x1080` sets the window for screenshots.

Own cards ("Cards: My own cards" beside the spread menu, `AppSettings.draw_mode`):
- **The flow:** the querent shuffles and lays out a physical deck. "Lay out" (`ReadingSession.start(..., own = true)`) skips the shuffle and shows each position as an empty outline (`CardView.empty`, layout card -1). Clicking a position, or pressing Space, opens `ui/card_picker_dialog.gd`.
- **The picker:** filter by name ("seven wands"), a code (rank + suit letter w/c/s/p, a/1 for the Ace, p/n/q/k for the courts: "7w", "kp") or a trump's number ("16").
- **Placing:** `ReadingSession.place(slot, card)` refuses anything while the question is weighed, and a card already laid, and can change a card until the last one is in. The last card starts the reading.
- **Records:** the export says "Cards: your own, laid out by hand" and names no app deck; history records have `"draw": "own"`.

Reading history (`core/reading_history.gd`, `ui/history_dialog.gd`, "History…" beside Settings):
- **Saving:** every finished reading is saved as one JSON file in `user://history/`, named by date and question. `ReadingScreen.save_to_history()` runs on `reading_finished` and `critique_finished`. A retry or critique rewrites the same file (`history_path`); a Re-read gets its own. Settings → History ("Keep every finished reading", `AppSettings.keep_history`) turns it off.
- **Re-read** (bottom row, and in History): `ReadingSession.reread()` weighs the question again and reads the cards on the table with the model now in Settings. It calls `_begin_reading()` before `_classify()`, so a refusal that comes at once isn't overwritten. The seconds reported count from the verdict.
- **What a record holds:** the question, classification, the whole definition of the spread on the table (so readings from deleted added spreads reopen), the cards per position, deck, model, reading and critique. Dignities and patterns are not stored. `ReadingSession.restore()` works them out again from the cards, like any reading, and `ReadingScreen.open_record()` lays the reading out face up.
- **Tests:** they point the folder elsewhere (`App.history_folder`; the smoke test uses `user://test_smoke_history`).

Keys (`ReadingScreen._unhandled_key_input`, only while focus is on the reading screen and no card is shown large): Space or Enter takes the next step (`next_step()`: shuffle, deal, turn the next card) and Ctrl+Enter turns all. Shuffle, Cut, Deal and Turn all take no keyboard focus, so a focused button never swallows those keys. The smoke test runs reading 4 from the keyboard.

The UI is built in code (no hand-edited scenes beyond `scenes/main.tscn` and the deck viewer). `ReadingSession` (`llm/reading_session.gd`) runs a reading step by step and never touches nodes; `ui/reading_screen.gd` wires it to the views. Animations are scaled by `App.motion` (0 in the smoke test).

## Conventions

- All tradition data in JSON under `data/`; no correspondences hard-coded in GDScript.
- Keep the LLM client behind one small interface (`complete(messages, stream)`) so backends can be swapped.
- Ask before changing any decision in "Tradition and source decisions".
