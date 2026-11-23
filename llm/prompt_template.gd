class_name PromptTemplate
extends RefCounted
## Prompt text lives in res://prompts/*.txt so it can be edited without touching code.
## Placeholders are {{name}}. Single braces are left alone, so JSON examples survive.

const PROMPTS_DIR := "res://prompts"


## The template text of prompts/<name>.txt, or "" (with an error) if it is missing.
static func load_text(prompt_name: String) -> String:
	var path: String = PROMPTS_DIR.path_join(prompt_name + ".txt")
	if not FileAccess.file_exists(path):
		push_error("Missing prompt template %s" % path)
		return ""
	return FileAccess.get_file_as_string(path)


static func render(template: String, values: Dictionary) -> String:
	var text: String = template
	for key: String in values:
		text = text.replace("{{%s}}" % key, str(values[key]))
	return text


static func load_and_render(prompt_name: String, values: Dictionary = {}) -> String:
	return render(load_text(prompt_name), values).strip_edges()
