# Router Mode

Router mode allows a harness to select which model gets loaded.

The INI section names are the model ids that clients request (`qwen38`, `qwen36`, `gemma4`, `LightOn`, `qwen35` in the preset below). When a client requests a model, the router loads it on demand with that section's parameters. `--models-max` caps how many models stay resident at once; with `--models-max 1`, requests for a different model are queued until the current one is unloaded.

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
# not more than 2 CPU threads (GPU memory contention)
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
# MTP (doubles token generation rate)
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

The `routing` profile in `models.json` carries the preset reference in its `options` (`--models-preset ../models.ini --models-max 1`). `start_server.sh` refuses to start in router mode unless the selected profile's `options` include a `--models-preset <ini>` entry. The preset path is relative to `llama.cpp/` (the directory the script runs the server from), so `../models.ini` resolves to the file next to this document. Note that `-c/--context` and the profile `context` field have no effect in router mode — the context size comes from `ctx-size` in the INI preset.

## Using router mode with the pi CLI

Current pi builds include llama.cpp router support built in — no plugin install needed. Configure the connection inside pi:

```text
/login llama.cpp
```

and enter the router URL (default `http://127.0.0.1:8080`) and an optional API key. The equivalent environment variables are `LLAMA_BASE_URL` and `LLAMA_API_KEY`.

No `models.json` configuration is required: load the model in pi with `/llama` (select an INI section name, e.g. `qwen38`) and choose which one the session uses with `/model`.

### Optional: per-model pi settings

If you need pi-specific settings for a model (context window, max tokens, reasoning, ...), declare it in `~/.pi/agent/models.json`. Any INI section name can be listed:

```json
{
  "providers": {
    "llama.cpp": {
      "baseUrl": "http://127.0.0.1:8080/v1",
      "api": "openai-completions",
      "apiKey": "llama",
      "models": [
        {
          "id": "qwen38",
          "contextWindow": 128000,
          "maxTokens": 8192,
          "reasoning": true,
          "thinkingLevelMap": {
            "off": "off",
            "minimal": null,
            "low": "low",
            "medium": "medium",
            "high": null,
            "xhigh": "xhigh",
            "max": null
          }
        }
      ]
    }
  }
}
```

Then load the model in pi with `/llama` and select it with `/model`.

`baseUrl` notes:

- `/v1` is the OpenAI-compatible route prefix. pi's `openai-completions` API appends `/chat/completions` to `baseUrl`, so it must end in `/v1` to hit `POST /v1/chat/completions`.
- llama-server also registers a root alias `POST /chat/completions` plus its own non-OpenAI routes, so `baseUrl` without `/v1` happens to work too — but `/v1` is the canonical form (it is what pi's built-in llama provider generates).
- The router management endpoints (model list, load, unload, SSE: `/models`, `/models/load`, `/models/unload`, `/models/sse`) live at the root, not under `/v1`.
