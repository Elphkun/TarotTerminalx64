# Changelog

## 0.2.0 (2026-11-24)

### Added
- **Re-read** reads the same cards again, so you can compare models: change the model in
  Settings, then press Re-read (beside New reading, or in History). Each reading is kept.
- History shows which model wrote each reading.
- While the reader weighs your question, the cards glow and a timer runs. This is when a
  model loads, and it used to look stuck.

### Fixed
- Ordinary questions ("Will I find love?") could open with a refusal or a line about harm
  before the reading. The rule behind it now goes only with a question that could not be
  weighed.
- A model that answered the question instead of weighing it skipped the harm check without
  a word. It is now asked again, and if it still can't say, a note under the reading says so.
- With your own cards, positions could be filled before the harm check had finished. They
  now wait for it.
- A reading reopened from the history keeps its own spread layout when saved again, even if
  the spread has changed since.

### For builders
- `tools/build_windows.sh` stops if your own server address or API key would end up in the
  build.

## 0.1.0 (2026-11-23)

First public release.
