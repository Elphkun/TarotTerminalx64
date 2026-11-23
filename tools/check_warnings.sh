#!/usr/bin/env bash
# Lists GDScript warnings in every tracked script, as the editor would show them.
# Godot only prints warnings from the command line when they are errors, so this
# writes a temporary override.cfg raising every default-on warning to an error,
# checks each script, and always removes the file again.
#
#   tools/check_warnings.sh            default warnings (what the editor shows)
#   tools/check_warnings.sh --strict   also the opt-in typing warnings (untyped, unsafe)
#
# Set GODOT to the Godot binary if it is not the one below. Run from the project folder.

GODOT="${GODOT:-/c/Users/elphk/Godot/Godot_v4.7.2-stable_win64_console.exe}"
cd "$(dirname "$0")/.." || exit 2
if [ -e override.cfg ]; then
    echo "override.cfg already exists; not touching it." >&2
    exit 2
fi
trap 'rm -f override.cfg' EXIT

WARNINGS="unassigned_variable unassigned_variable_op_assign unused_variable unused_local_constant
unused_private_class_variable unused_parameter unused_signal shadowed_variable
shadowed_variable_base_class shadowed_global_identifier unreachable_code unreachable_pattern
standalone_expression standalone_ternary incompatible_ternary unsafe_void_return
static_called_on_instance missing_tool redundant_static_unload redundant_await assert_always_true
assert_always_false integer_division narrowing_conversion int_as_enum_without_cast
int_as_enum_without_match enum_variable_without_default empty_file deprecated_keyword
confusable_identifier confusable_local_declaration confusable_local_usage
confusable_capture_reassignment confusable_temporary_modification property_used_as_function
constant_used_as_function function_used_as_property"
if [ "$1" = "--strict" ]; then
    WARNINGS="$WARNINGS untyped_declaration inferred_declaration unsafe_property_access
unsafe_method_access unsafe_cast unsafe_call_argument return_value_discarded missing_await"
fi

{
    echo "[debug]"
    for warning in $WARNINGS; do
        echo "gdscript/warnings/$warning=2"
    done
} > override.cfg

found=0
for script in $(git ls-files '*.gd'); do
    output=$("$GODOT" --headless --path . --check-only --script "res://$script" 2>&1)
    # Each warning prints as a "Parse Error" line followed by an "at: ... (res://file:line)" line.
    while IFS= read -r line; do
        case "$line" in
            *"Parse Error:"*)
                message="${line#*Parse Error: }"
                message="${message% (Warning treated as error.)}"
                ;;
            *"at: GDScript::reload ("*)
                if [ -n "$message" ]; then
                    where="${line#*GDScript::reload (}"
                    echo "${where%)}: $message"
                    message=""
                fi
                ;;
        esac
    done <<< "$output"
done | sort -u | tee /dev/stderr | { count=$(wc -l); echo "$count warning(s)"; [ "$count" -eq 0 ]; }
