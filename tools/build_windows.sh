#!/usr/bin/env bash
# Builds a self-contained Windows copy of TarotTerminal into build/windows/ (git-ignored):
#   TarotTerminal.exe   code, data/ and prompts/ (with the example readings) packed inside
#   decks/              every deck whose deck.json says "distributable": true
#   spreads/            empty, for added spreads, with README.md (docs/custom_spreads.md)
#   LICENSE.txt         MIT for the app, CC BY 4.0 for the author's decks
#   local/              for the user's own card meanings (meanings.json), with README.md
#                       (docs/card_meanings.md)
# Settings, the LLM endpoint and the user's own examples live in
# %APPDATA%\Godot\app_userdata\TarotTerminal\, not here.
#
#   bash tools/build_windows.sh [--debug] [--no-decks]
# --debug exports a debug build, which also writes TarotTerminal.console.exe for logs.
# --no-decks skips copying decks (they are only copied when newer anyway).
set -euo pipefail

GODOT="${GODOT:-/c/Users/elphk/Godot/Godot_v4.7.2-stable_win64_console.exe}"
cd "$(dirname "$0")/.."
OUT="build/windows"
MODE="--export-release"
COPY_DECKS=1
for arg in "$@"; do
	case "$arg" in
		--debug) MODE="--export-debug" ;;
		--no-decks) COPY_DECKS=0 ;;
		*) echo "unknown option: $arg" >&2; exit 2 ;;
	esac
done

mkdir -p "$OUT"
# build/ is inside the project: without this Godot would import the copied decks and
# pack them into the next build.
touch build/.gdignore
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless "$MODE" "Windows Desktop" "$OUT/TarotTerminal.exe"
[ -f "$OUT/TarotTerminal.exe" ] || { echo "export failed: no $OUT/TarotTerminal.exe" >&2; exit 1; }

mkdir -p "$OUT/spreads"
cp docs/custom_spreads.md "$OUT/spreads/README.md"
cp LICENSE "$OUT/LICENSE.txt"
mkdir -p "$OUT/local"
cp docs/card_meanings.md "$OUT/local/README.md"

if [ "$COPY_DECKS" = 1 ]; then
	mkdir -p "$OUT/decks"
	for deck in decks/*/; do
		name="$(basename "$deck")"
		if grep -qE '"distributable"[[:space:]]*:[[:space:]]*true' "$deck/deck.json" 2>/dev/null; then
			cp -ru "$deck" "$OUT/decks/"
			# Drop files the source deck no longer has (a deck converted from PNG to JPEG
			# would otherwise carry both, and the app warns about two files per card).
			for built in "$OUT/decks/$name"/*; do
				[ -e "$deck/$(basename "$built")" ] || rm -f "$built"
			done
			echo "deck: $name"
		else
			echo "deck: $name left out (not distributable)"
		fi
	done
fi

echo "Built $OUT ($(du -sh "$OUT" | cut -f1))"
