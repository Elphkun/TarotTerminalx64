#!/usr/bin/env bash
# Stops a build from carrying the builder's own server address or API key. Looks for:
#   - the endpoint's host and the API key in this user's llm.json (the app's settings);
#   - Tailscale addresses and names, whatever llm.json says now.
# A host on this computer or a well-known public API is not private. Prints the files
# that match, never the address or key. Exit 1 when anything matches.
#
#   bash tools/check_private.sh [folder]     the project (default), or a built folder
set -uo pipefail

cd "$(dirname "$0")/.."
WHERE="${1:-.}"
[ -d "$WHERE" ] || { echo "check_private: no folder $WHERE" >&2; exit 2; }
LLM_JSON="${LLM_JSON:-${APPDATA:-}/Godot/app_userdata/TarotTerminal/llm.json}"
# Files are compared byte by byte: the exe is binary.
export LC_ALL=C

# The string field $1 of llm.json, or nothing.
field() {
	tr -d '\r' < "$LLM_JSON" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}

# Plain text as a pattern. (Git Bash's grep crashes on -F together with -i.)
escape() {
	printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'
}

# Files under $WHERE that match; "$@" is the grep pattern. Card images can't hold text.
search() {
	grep -rlai "$@" "$WHERE" \
		--exclude-dir=.git --exclude-dir=.godot --exclude-dir=build --exclude=CLAUDE.local.md \
		--exclude=check_private.sh --exclude=*.jpg --exclude=*.jpeg --exclude=*.png --exclude=*.webp
	[ $? -le 1 ] || { echo "check_private: the search failed" >&2; exit 2; }
}

found=""
note() {
	if [ -n "$2" ]; then
		found=1
		echo "PRIVATE: $1 is in:" >&2
		echo "$2" | sed 's/^/  /' >&2
	fi
}

if [ -f "$LLM_JSON" ]; then
	host="$(field endpoint | sed -E 's#^[a-zA-Z]+://##; s#/.*$##; s#^[^@]*@##')"
	case "$host" in
		\[*) host="${host#\[}"; host="${host%%\]*}" ;;
		*) host="${host%%:*}" ;;
	esac
	case "$host" in
		""|localhost|127.*|::1|0.0.0.0|api.openai.com|api.anthropic.com) ;;
		*) hits="$(search -wE -e "$(escape "$host")")" || exit 2; note "your server's address" "$hits" ;;
	esac
	key="$(field api_key)"
	if [ "${#key}" -ge 8 ]; then
		hits="$(search -E -e "$(escape "$key")")" || exit 2
		note "your API key" "$hits"
	fi
fi
hits="$(search -E -e 'fd7a:115c:a1e0:|[a-z0-9-]+\.ts\.net')" || exit 2
note "a Tailscale address" "$hits"

[ -z "$found" ] || exit 1
echo "check_private: nothing private in $WHERE"
