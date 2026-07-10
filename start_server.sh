#!/bin/bash

# Binding server to host (override with --host <hostname> ):
HOST="0.0.0.0"

# ==============================================================================
# Script: start_server.sh
# Purpose: Automated launcher for llama.cpp server with model selection,
#          context management, and default configuration handling.
# Dependencies: Requires a built 'llama-server' binary, jq, and model files
#              defined in models.json.
# Usage: ./start_server.sh [OPTIONS] [EXTRA_FLAGS]
# ==============================================================================

# Enable strict error handling:
# -e: Exit immediately if a command exits with a non-zero status.
# -u: Treat unset variables as an error and exit.
# -o pipefail: The return value of a pipeline is the status of the last command
#              to exit with a non-zero status, or zero if no command exits with a non-zero status.
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration & Path Management
# -----------------------------------------------------------------------------

# Determine the directory where this script resides.
# Using 'cd' and 'pwd' ensures we get the absolute path regardless of where
# the script is called from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Set directory variables with fallback defaults using parameter expansion (: ${VAR:=default})
# This allows users to override these via environment variables if needed.
: ${MAIN_DIR:=$SCRIPT_DIR}           # Root directory of the project
: ${SOURCE_DIR:=$MAIN_DIR/llama.cpp} # Directory containing the llama.cpp source/build

CONFIG_FILE="$SCRIPT_DIR/models.json"

CONFIG_CONTEXT=""
CONFIG_OPTIONS=()

# -----------------------------------------------------------------------------
# Load Model Configuration from JSON
# -----------------------------------------------------------------------------
load_model_config() {
	local profile="$1"
	MODEL_PROFILE="$profile"

	local hf_model

	hf_model=$(jq -r ".models[\"$profile\"].model // empty" "$CONFIG_FILE")

	if [ -z "$hf_model" ]; then
		echo "Error: Profile '$profile' not found in $CONFIG_FILE or has no 'model' field"
		exit 1
	fi

	HF_MODEL="${hf_model}"

	CONFIG_CONTEXT=$(jq -r ".models[\"$profile\"].context // empty" "$CONFIG_FILE")

	if [ -z "$CONFIG_CONTEXT" ]; then
		CONFIG_CONTEXT=32768
	fi

	CONFIG_OPTIONS=()
	while IFS= read -r opt; do
		[ -n "$opt" ] && CONFIG_OPTIONS+=("$opt")
	done < <(jq -r ".models[\"$profile\"].options[]?" "$CONFIG_FILE")
}

# -----------------------------------------------------------------------------
# Argument Parsing
# -----------------------------------------------------------------------------
USE_MENU=false
LIST_MODELS=false
PRINT_ONLY=false
NEW_MODEL=false
MODEL_PROFILE=""
extra_flags=()

# Parse command-line arguments manually to support variable-length arguments
# and store unknown flags for later passing to llama-server.
while [[ $# -gt 0 ]]; do
	case "$1" in
	# -m or --model: Use a named profile from models.json
	-m | --model)
		MODEL_PROFILE="$2"
		shift 2
		;;
	# -c or --context: Override the default context size.
	-c | --context)
		CONTEXT_SIZE="$2"
		shift 2
		;;
	# -s or --select: Interactive model profile selection menu. Shows all profiles
	#                 with default marked. Enter loads default, or select by number.
	-s | --select)
		USE_MENU=true
		shift 1
		;;
	# -l or --list: Print available model profiles from models.json and exit.
	-l | --list)
		LIST_MODELS=true
		shift 1
		;;
	# -p or --print: Print the command that would be executed without running it.
	-p | --print)
		PRINT_ONLY=true
		shift 1
		;;
	# --host: Override the host binding address
	--host)
		HOST="$2"
		shift 2
		;;
	# -f or --force-download: Force download from HuggingFace even if local file exists
	-f | --force-download)
		echo "Note: -f flag is deprecated, download is always attempted"
		shift 1
		;;
	# -n or --new: Add a new model profile to models.json (interactive)
	-n | --new)
		NEW_MODEL=true
		shift 1
		;;
	# -h or --help: Display usage information.
	-h | --help)
		echo "Usage: $0 [-m|--model PROFILE] [-c|--context SIZE] [-s|--select] [-l|--list] [-p|--print] [-n|--new] [extra_flags...]"
		echo ""
		echo "Options:"
		echo "  -m, --model <profile>     Model profile key from models.json (e.g. qwen36, gemma4, LightOn)"
		echo "  -c, --context <num>       Override context size from profile"
		echo "  -s, --select              Interactive model profile selection menu"
		echo "  -l, --list                Validates models.json and lists available model profiles"
		echo "  -p, --print               Print the command without executing it"
		echo "  -n, --new                 Add a new model profile to models.json (interactive)"
		echo "  -h, --help                Display this help message"
		echo "  extra_flags               Any additional flags to pass to llama-server e.g. --tools all"
		echo ""
		echo "Model profile fields (in models.json):"
		echo "  name    - Profile key used with -m flag (e.g. qwen36, gemma4, LightOn)"
		echo "  model   - HuggingFace model ID, in local cache after first use"
		echo "  context - Context window size"
		echo "  comment - Short description of the model capabilities"
		echo "  options - Additional llama-server flags (array)"
		echo "  default - Mark this profile as the default (boolean)"
		echo ""
		echo "Defaults: If no options provided, loads the default profile from models.json."
		echo "To list the models in local cache: hf cache ls"
		exit 0
		;;
	# Catch-all: Any unrecognized flag is stored for the final execution.
	*)
		extra_flags+=("$1")
		shift 1
		;;
	esac
done

# -----------------------------------------------------------------------------
# Model Discovery from models.json
# -----------------------------------------------------------------------------
get_model_profiles() {
	jq -r '.models | keys[]' "$CONFIG_FILE" 2>/dev/null
}

get_model_info() {
	local profile="$1"
	local key="$2"
	jq -r ".models[\"$profile\"][\"$key\"] // empty" "$CONFIG_FILE"
}

get_default_profile() {
	jq -r '.models | to_entries[] | select(.value.default == true) | .key' "$CONFIG_FILE" 2>/dev/null
}

validate_config() {
	echo "Validating $CONFIG_FILE..."

	# 1. Check if valid JSON
	if ! jq '.' "$CONFIG_FILE" > /dev/null 2>&1; then
		echo "Error: $CONFIG_FILE is not a valid JSON file."
		exit 1
	fi

	# 2. Check if 'models' object exists and is not empty
	local models_count
	models_count=$(jq '.models | length' "$CONFIG_FILE" 2>/dev/null || echo 0)
	if [ "$models_count" -eq 0 ]; then
		echo "Error: No models found in $CONFIG_FILE (the 'models' object is empty or missing)."
		exit 1
	fi

	# 3. Check if every profile has a 'model' field
	local missing_model
	missing_model=$(jq -r '.models | to_entries | .[] | select(.value.model == null or .value.model == "") | .key' "$CONFIG_FILE")
	if [ -n "$missing_model" ]; then
		echo "Error: The following profiles are missing a 'model' field: $missing_model"
		exit 1
	fi

	# 4. Check if there is exactly one default profile
	local default_count
	default_count=$(jq '.models | to_entries | map(select(.value.default == true)) | length' "$CONFIG_FILE")
	if [ "$default_count" -ne 1 ]; then
		echo "Error: Expected exactly 1 default profile, but found $default_count in $CONFIG_FILE"
		exit 1
	fi

	# 5. Check if 'context' is a number (if present)
	local invalid_context
	invalid_context=$(jq -r '.models | to_entries | .[] | select(.value.context != null and (.value.context | type != "number")) | .key' "$CONFIG_FILE")
	if [ -n "$invalid_context" ]; then
		echo "Error: The following profiles have an invalid 'context' (must be a number): $invalid_context"
		exit 1
	fi

	# 6. Check if 'options' is an array (if present)
	local invalid_options
	invalid_options=$(jq -r '.models | to_entries | .[] | select(.value.options != null and (.value.options | type != "array")) | .key' "$CONFIG_FILE")
	if [ -n "$invalid_options" ]; then
		echo "Error: The following profiles have an invalid 'options' (must be an array): $invalid_options"
		exit 1
	fi

	echo "Configuration validation passed."
}

if ! command -v jq &>/dev/null; then
	echo "Error: jq is required but not installed."
	exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
	echo "Error: Config file not found at $CONFIG_FILE"
	exit 1
fi

validate_config

MODEL_PROFILES=($(get_model_profiles))
DEFAULT_PROFILE=$(get_default_profile)

# -----------------------------------------------------------------------------
# Handle List Mode (no server required)
# -----------------------------------------------------------------------------
if [ "$LIST_MODELS" = true ]; then
	echo "Available models in $CONFIG_FILE:"
	echo "--------------------------------"
	for profile in "${MODEL_PROFILES[@]}"; do
		model=$(get_model_info "$profile" "model")
		context=$(get_model_info "$profile" "context")
		comment=$(get_model_info "$profile" "comment")
		options=$(jq -r ".models[\"$profile\"].options | if . then map(\" \" + .) | join(\"\") else \"\" end" "$CONFIG_FILE")
		is_default=$(get_model_info "$profile" "default")
		default_marker=""
		if [ "$is_default" = "true" ]; then
			default_marker=" (default)"
		fi
		echo "[$profile]$default_marker"
		if [ -n "$comment" ]; then
			echo "  Comment:   $comment"
		fi
		echo "  Model:     $model"
		echo "  Context:   ${context:-32768}"
		echo "  Options:   ${options:- none}"
		echo ""
	done
	exit 0
fi

# -----------------------------------------------------------------------------
# Handle New Model Mode (no server required)
# -----------------------------------------------------------------------------
if [ "$NEW_MODEL" = true ]; then
	echo "Adding a new model profile to $CONFIG_FILE"
	echo "--------------------------------"

	# Prompt for profile name
	while true; do
		read -rp "Profile name (e.g. qwen36): " new_profile
		if [ -z "$new_profile" ]; then
			echo "Error: Profile name cannot be empty."
			continue
		fi
		if jq -e ".models[\"$new_profile\"]" "$CONFIG_FILE" > /dev/null 2>&1; then
			echo "Profile '$new_profile' already exists in $CONFIG_FILE."
			echo "  1) Update (overwrite) this profile"
			echo "  2) Choose a different name"
			echo "  3) Quit"
			read -rp "Choice [1/2/3]: " conflict_choice
			case "$conflict_choice" in
				1)
					echo "Updating profile '$new_profile'..."
					break
					;;
				2)
					continue
					;;
				*)
					echo "Aborted."
					exit 0
					;;
			esac
		else
			break
		fi
	done

	# Prompt for HuggingFace model ID
	while true; do
		read -rp "HuggingFace model ID (e.g. unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-Q4_K_M): " new_model
		if [ -z "$new_model" ]; then
			echo "Error: Model ID cannot be empty."
			continue
		fi
		break
	done

	# Prompt for context size
	read -rp "Context size [32768]: " new_context
	new_context="${new_context:-32768}"
	if ! [[ "$new_context" =~ ^[0-9]+$ ]]; then
		echo "Error: Context size must be a number."
		exit 1
	fi

	# Prompt for comment
	read -rp "Comment (short description, e.g. 'General purpose, text and image'): " new_comment

	# Prompt for options
	read -rp "Additional options (comma-separated, e.g. -fa on,-ctk q4_0): " new_options_raw
	options_json="[]"
	if [ -n "$new_options_raw" ]; then
		# Convert comma-separated to JSON array
		options_json=$(echo "$new_options_raw" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != ""))')
	fi

	# Prompt for default
	is_default="false"
	read -rp "Set as default? (y/N): " set_default
	if [[ "$set_default" =~ ^[yY]$ ]]; then
		is_default="true"
	fi

	# Build the new profile JSON
	new_profile_json=$(jq -n \
		--arg model "$new_model" \
		--argjson context "$new_context" \
		--arg comment "$new_comment" \
		--argjson options "$options_json" \
		--argjson default "$is_default" \
		'{"model": $model, "context": $context, "comment": $comment, "options": $options, "default": $default}')

	# If setting as default, clear default from all other profiles
	if [ "$is_default" = "true" ]; then
		jq --arg name "$new_profile" \
			'.models |= with_entries(if .key != $name then .value.default = false else . end)' \
			"$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
	fi

	# Add the new profile
	jq --arg name "$new_profile" \
		--argjson profile "$new_profile_json" \
		'.models[$name] = $profile' \
		"$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

	echo ""
	echo "Profile '$new_profile' added to $CONFIG_FILE:"
	jq ".models[\"$new_profile\"]" "$CONFIG_FILE"
	echo ""
	echo "Done. Start with: $0 -m $new_profile"
	echo "The model will be downloaded when the server is started if not in the local cache."
	echo ""
	exit 0
fi

cd "$SOURCE_DIR"

if [ ! -x "build/bin/llama-server" ]; then
	echo "Error: llama-server binary not found or not executable"
	echo "Please ensure it's built in $SOURCE_DIR/build"
	echo "Run build_llamacpp.sh to build."
	exit 1
fi

# -----------------------------------------------------------------------------
# Model Selection Logic
# -----------------------------------------------------------------------------
# Determine which model profile to load:
# 1. -m flag: Use specified profile
# 2. -s flag: Interactive menu (default marked, Enter loads default)
# 3. Otherwise: Use the default profile from models.json
if [ -n "$MODEL_PROFILE" ]; then
	load_model_config "$MODEL_PROFILE"
elif [ "$USE_MENU" = true ]; then
	echo "Selecting model profile..."
	echo "--------------------------------"

	for i in "${!MODEL_PROFILES[@]}"; do
		profile="${MODEL_PROFILES[$i]}"
		comment=$(get_model_info "$profile" "comment")
		if [ "$profile" = "$DEFAULT_PROFILE" ]; then
			if [ -n "$comment" ]; then
				echo "$((i + 1))) $profile (default) - $comment"
			else
				echo "$((i + 1))) $profile (default)"
			fi
		else
			if [ -n "$comment" ]; then
				echo "$((i + 1))) $profile - $comment"
			else
				echo "$((i + 1))) $profile"
			fi
		fi
	done

	echo ""
	echo "  Enter  → load default ($DEFAULT_PROFILE)"
	echo "  1-${#MODEL_PROFILES[@]}  → select profile"
	echo "  Any other key → quit"
	echo ""
	read -rp "Selection [Enter/$DEFAULT_PROFILE]: " selection

	if [ -z "$selection" ]; then
		load_model_config "$DEFAULT_PROFILE"
	elif [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#MODEL_PROFILES[@]}" ]; then
		profile="${MODEL_PROFILES[$((selection - 1))]}"
		load_model_config "$profile"
	else
		echo "Aborted."
		exit 0
	fi
else
	load_model_config "$DEFAULT_PROFILE"
fi

# -----------------------------------------------------------------------------
# Server Execution
# -----------------------------------------------------------------------------
CONTEXT_SIZE="${CONTEXT_SIZE:-$CONFIG_CONTEXT}"
START_OPTIONS=("${CONFIG_OPTIONS[@]}")

echo "Starting server..."
echo "Model:        $HF_MODEL"
COMMENT=$(jq -r ".models[\"$MODEL_PROFILE\"].comment // empty" "$CONFIG_FILE")
if [ -n "$COMMENT" ]; then
	echo "Comment:      $COMMENT"
fi
echo "Context Size: $CONTEXT_SIZE"
echo "Options:      ${START_OPTIONS[*]:-none}"
if [ ${#extra_flags[@]} -gt 0 ]; then
	echo "Extra Flags:  ${extra_flags[*]}"
fi
echo "--------------------------------"

CMD=(build/bin/llama-server
	--host "$HOST"
	-hf "$HF_MODEL"
	-c "$CONTEXT_SIZE"
	"${START_OPTIONS[@]}"
	"${extra_flags[@]}")

if [ "$PRINT_ONLY" = true ]; then
	echo "Command: ${CMD[*]}"
	exit 0
fi

exec "${CMD[@]}"
