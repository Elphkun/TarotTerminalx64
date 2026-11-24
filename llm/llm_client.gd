class_name LlmClient
extends Node
## The one interface the rest of the app uses to talk to a language model.
## Backends (local OpenAI-compatible servers now, Claude/OpenAI later) extend this.
## It is a Node so it can wait on frames while a request runs; add it to the tree first.

## A piece of the answer, emitted as it streams in. Backends emit it; the base never does.
@warning_ignore("unused_signal")
signal token(text: String)
## A piece of the model's hidden reasoning, for models that stream it separately.
@warning_ignore("unused_signal")
signal reasoning(text: String)

## Why the last call failed, or "" if it succeeded.
var last_error: String = ""
## Token counts the server reported for the last call ({prompt_tokens, completion_tokens}),
## or empty if it reported none.
var last_usage: Dictionary = {}
## Why the last answer ended: "stop" when the model finished, "length" when it hit
## max_tokens or the server's context window, "" if the server did not say.
var last_finish_reason: String = ""
## The model that answered the last call, when known.
var last_model: String = ""


## Sends chat `messages` ([{role, content}]) and returns the full answer text.
## With `stream`, `token` fires for each piece as it arrives. Returns "" on failure
## and sets `last_error`. `options` may override temperature, max_tokens, model, thinking.
func complete(_messages: Array, _stream: bool = false, _options: Dictionary = {}) -> String:
	last_error = "complete() not implemented"
	return ""


## Abandons any request in flight; its complete() returns "" with last_error "cancelled".
func cancel() -> void:
	pass


## The models the server offers for chat, or [] (check last_error) if it cannot say.
func list_chat_models() -> PackedStringArray:
	last_error = "this backend cannot list models"
	return PackedStringArray()


## The context window (in tokens) the server has `model_name` loaded with, or -1 when
## it cannot say ("" means the configured model). Never sets last_error.
func loaded_context(_model_name: String = "") -> int:
	return -1


## Which API this client speaks to the server, for display ("Ollama", "OpenAI-compatible").
func backend_name() -> String:
	return ""


## True when the app sets the context window itself, so loaded_context() is the setting.
func sets_context_window() -> bool:
	return false


## Forgets anything remembered from the old settings (resolved model, addresses).
func settings_changed() -> void:
	pass
