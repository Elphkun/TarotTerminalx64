extends SceneTree
## Shrinks decks to JPEGs no taller than the app uses (DeckConverter), replacing the
## original images. Keep a backup: the originals are deleted.
##
## Usage: godot --headless --script tools/convert_decks.gd -- [options] [deck folders]
##   With no folders, every deck in the decks folder is converted.
##   --skip=NAME      leave the deck with this folder name alone (repeatable)
##   --height=1440    the tallest a card may be
##   --quality=90     JPEG quality, 1 to 100
##   --dry-run        say what would change, change nothing
##
## Quits with 1 if any deck had problems.


func _initialize() -> void:
	var converter: DeckConverter = DeckConverter.new()
	var skip: PackedStringArray = []
	var folders: PackedStringArray = []
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--skip="):
			skip.append(argument.trim_prefix("--skip="))
		elif argument.begins_with("--height="):
			converter.height = argument.trim_prefix("--height=").to_int()
		elif argument.begins_with("--quality="):
			converter.quality = clampf(argument.trim_prefix("--quality=").to_int() / 100.0, 0.01, 1.0)
		elif argument == "--dry-run":
			converter.dry_run = true
		elif not argument.begins_with("--"):
			folders.append(argument)
	if converter.height < 1:
		print("--height must be a positive number")
		quit(1)
		return
	if folders.is_empty():
		var decks_root: String = ProjectSettings.globalize_path(DeckLibrary.folder(AppSettings.load_from()))
		for name: String in DirAccess.get_directories_at(decks_root):
			folders.append(decks_root.path_join(name))

	var failed: int = 0
	var total_before: int = 0
	var total_after: int = 0
	for folder: String in folders:
		var name: String = folder.trim_suffix("/").get_file()
		if skip.has(name):
			print("%s: skipped" % name)
			continue
		var ok: bool = converter.convert(folder)
		total_before += converter.bytes_before
		total_after += converter.bytes_after
		print("%s: %d image(s) %s, %s -> %s" % [name, converter.converted,
				"would change" if converter.dry_run else "converted",
				String.humanize_size(converter.bytes_before), String.humanize_size(converter.bytes_after)])
		for problem: String in converter.problems:
			print("  problem: %s" % problem)
		if not ok:
			failed += 1
	print("")
	print("Total: %s -> %s%s" % [String.humanize_size(total_before),
			String.humanize_size(total_after), " (dry run: nothing written)" if converter.dry_run else ""])
	quit(1 if failed > 0 else 0)
