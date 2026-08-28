# Router Mode

Router mode allows a harness to select which model gets loaded.

To configure different parameters per model in router mode, an INI file is used. Each section is one model; values in the global `[*]` section apply to all models unless overridden in a section. `ctx-size` defines the context window (per model or globally).

## models.ini file

The preset used by this repo (see `models.ini` next to this file):

```ini
# Router Mode Global settings applied to all models unless explicitly overridden
[*]
flash-attn = true
batch-size = 1024
ctx-size = 131072
# KV Cache Quantization parameters
cache-type-k = q4_0
cache-type-v = q4_0
# not more the 2 cpu threads (GPU memory contention)
threads = 2

# General purpose dense model
[qwen38]
hf-repo = unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_XL
# Inherits all global values
temp = 1.0
top-k = 20
top-p = 0.95
min-p = 0.0
presence-penalty = 0.0
repeat-penalty = 1.0
# MTP (2 doubles tokens generation rate )
spec-type = draft-mtp
spec-draft-n-max = 2
tools = all

# General purpose text and image model
[qwen36]
hf-repo = unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-Q4_K_M
# Inherits all global values
tools = all

# Google Gemma 4 model profile
[gemma4]
hf-repo = unsloth/gemma-4-26B-A4B-it-GGUF:UD-Q4_K_XL
# Inherits all global values
tools = all

# OCR specialist (Overrides parameters to restrict context and lower temperature)
[LightOn]
hf-repo = staghado/LightOnOCR-2-1B-Q8_0-GGUF
ctx-size = 16384
temp = 0.2
top-k = 0
top-p = 0.9

# Lightweight agent / fast logic model
[qwen35]
hf-repo = unsloth/Qwen3.5-4B-GGUF:UD-Q4_K_XL
ctx-size = 16384
temp = 0.7
top-k = 0
top-p = 0.9
tools = all
```

## Starting the server in router mode

```bash
# Directly:
llama-server --models-preset <path>/models.ini --models-max 1

# Or via the repo's start_server.sh (routing is the default profile in models.json):
./start_server.sh
./start_server.sh -r
```

The `--models-max` switch limits the server to load only one model at a time.

The `routing` profile in `models.json` carries the preset reference in its `options` (`--models-preset ../models.ini --models-max 1`). `start_server.sh` refuses to start in router mode unless the selected profile's `options` include a `--models-preset <ini>` entry, and exports `LLAMA_BASE_URL` for the agent. Note that `-c/--context` and the profile `context` field have no effect in router mode — the context size comes from `ctx-size` in the INI preset.

## Using router mode with the pi CLI

Install the plugin:

```bash
pi install npm:pi-llama-cpp
```

Then configure pi in `~/.pi/agent/models.json` as follows:

```json
{
  "providers": {
    "llama-cpp": {
      "baseUrl": "http://127.0.0.1:8080",
      "api": "openai-completions",
      "apiKey": "local",
      "models": [
        {
          "id": "llama-cpp-discover"
        }
      ]
    }
  }
}
```
