# Router Mode

Router mode turns `llama-server` into a multiplexer: it starts with **no model loaded** and, for each request, hands off to whichever model the client (an agent/harness like pi, or any API consumer) names. Models can be loaded, unloaded and swapped on demand without restarting the server.

## How routing works

- Each model has an **id**. With a preset file, the id is simply the INI **section name** (`qwen38`, `qwen36`, `gemma4`, `LightOn`, `qwen35` in this repo's preset).
- POST endpoints (chat/completions, completions, infill, ...) select the model with the `"model"` field in the JSON body; GET endpoints use a `?model=` query parameter.
- A requested model is loaded on demand (disable with `--no-models-autoload`; `?autoload=true|false` per request).
- `--models-max N` caps how many models stay resident at once (default 4, `0` = unlimited). When the limit is reached, requesting another model evicts the **least-recently-used idle** model to free a slot; if every loaded model is busy, the request joins a queue until one goes idle. With `--models-max 1`, only one model is resident, so successive `qwen38`/`qwen36` requests swap the loaded model (and wait while the swap happens).

Per-model settings - including which model file to load - come from an INI preset file passed at startup.

## The INI preset (`models.ini`)

The preset next to this file (`models.ini`, content mirrored below for reference) defines one section per model. Keys map 1:1 to `llama-server` CLI flags without the leading dashes: `ctx-size`, `n-gpu-layers`, `temp`, `top-k`, `hf-repo`, etc.

- `[*]` is a special global section: its values apply to every model unless a model section overrides them.
- Precedence: command-line flags > model section > `[*]`.
- `ctx-size` is set globally (131072) and tightened per model where needed (`LightOn`, `qwen35` use 16384).
- A section name is also the model id clients request, so keep it short and stable (`qwen38`, not the full repo name).

```ini
# Router Mode Global settings applied to all models unless explicitly overridden
[*]
flash-attn = true
batch-size = 1024
ctx-size = 131072
# KV Cache Quantization parameters (q8_0 is faster and more accurate, this is a compromise)
cache-type-k = q8_0
cache-type-v = q4_0
# not more than 2 CPU threads (GPU memory contention may be a problem when to many threads are running)
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

# Or via the repo's launcher (routing is the default profile in models.json):
./start_server.sh
./start_server.sh -r
```

`start_server.sh` runs `llama-server` from `llama.cpp/`, so a preset path like `../models.ini` resolves to the file next to this document. Router mode requires a `--models-preset <ini>` entry in the selected profile's `options`; the script aborts if it is missing.

Note: in router mode, `-c/--context` and the profile `context` field in `models.json` have no effect. Context sizes come from `ctx-size` in the INI preset.

## Using router mode with the pi CLI

Current pi builds include llama.cpp router support - no plugin or extra config needed.

1. `/login llama.cpp` - enter the router URL (default `http://127.0.0.1:8080`) and an optional API key. The equivalent environment variables are `LLAMA_BASE_URL` and `LLAMA_API_KEY`.
2. `/llama` - load/unload models by id (an INI section name, e.g. `qwen38`), or download new ones straight from Hugging Face.
3. `/model` - select which loaded model the current session uses.

### Optional: per-model pi settings

For pi-specific settings (context window, max tokens, reasoning levels, ...), declare the model in `~/.pi/agent/models.json` under the `llama.cpp` provider, keyed by the INI section name:

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
          "maxTokens": 16384,
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

Then load the model with `/llama` and select it with `/model` as above.

`baseUrl` notes:

- `/v1` is the OpenAI-compatible route prefix. pi's `openai-completions` API appends `/chat/completions` to `baseUrl`, so it must end in `/v1` to hit `POST /v1/chat/completions`.
- llama-server also registers a root alias `POST /chat/completions` plus its own non-OpenAI routes, so `baseUrl` without `/v1` happens to work too - but `/v1` is the canonical form (it is what pi's built-in llama provider generates).
- The router management endpoints (model list, load, unload, SSE: `/models`, `/models/load`, `/models/unload`, `/models/sse`) live at the root, not under `/v1`.
