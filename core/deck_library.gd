class_name DeckLibrary
extends RefCounted
## Finds the decks in the deck folders. Rescan whenever the folders may have changed.

## The project's decks/ folder. It is git-ignored (apart from its .gdignore, which stops
## Godot importing or exporting it), so private decks stay out of git and exports.
const PROJECT_FOLDER := "res://decks"


## The deck folder when none is configured: the project's decks/ folder when running from
## source, or a decks/ folder next to the executable in an exported build.
static func default_folder() -> String:
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join("decks")
	return ProjectSettings.globalize_path(PROJECT_FOLDER)


## The configured deck folder, or the default one.
static func folder(settings: AppSettings) -> String:
	return default_folder() if settings.deck_folder == "" else settings.deck_folder


## Folders to scan. One for now; a list so more can be added later.
static func folders(settings: AppSettings) -> PackedStringArray:
	return [folder(settings)]


## Every subfolder with at least one image or a deck.json, valid or not, sorted by name.
## A folder name found twice (in two deck folders) keeps the first.
static func scan(folder_list: PackedStringArray) -> Array[DeckInfo]:
	var decks: Array[DeckInfo] = []
	var seen: Dictionary = {}
	for folder_path: String in folder_list:
		var path: String = ProjectSettings.globalize_path(folder_path)
		if not DirAccess.dir_exists_absolute(path):
			continue
		for subfolder: String in DirAccess.get_directories_at(path):
			if seen.has(subfolder) or not _looks_like_deck(path.path_join(subfolder)):
				continue
			seen[subfolder] = true
			decks.append(DeckInfo.load_folder(path.path_join(subfolder)))
	decks.sort_custom(func(a: DeckInfo, b: DeckInfo) -> bool:
		return a.name.naturalnocasecmp_to(b.name) < 0)
	return decks


static func _looks_like_deck(path: String) -> bool:
	for file: String in DirAccess.get_files_at(path):
		if file == DeckInfo.DECK_FILE or DeckInfo.IMAGE_EXTENSIONS.has(file.get_extension().to_lower()):
			return true
	return false
