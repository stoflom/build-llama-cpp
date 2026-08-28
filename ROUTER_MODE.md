# Router Mode

Router mode allows a harness to select which model gets loaded.

To configure different parameters per model in router mode, an INI file is used.

## models.ini file

```ini
# Global settings applied to all models unless explicitly overridden
[*]
flash-attn = true
batch-size = 1024
ctx-size = 131072
# KV Cache Quantization parameters
cache-type-k = q4_0
cache-type-v = q4_0
# Default sampling guardrails
temp = 1.0
top-k = 20
top-p = 0.95
min-p = 0.0
presence-penalty = 0.0
repeat-penalty = 1.0

# General purpose dense model
[qwen38]
model = unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_XL
# Inherits all global values

# General purpose text and image model
[qwen36]
model = unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-Q4_K_M
# Inherits all global values

# Google Gemma 4 model profile
[gemma4]
model = unsloth/gemma-4-26B-A4B-it-GGUF:UD-Q4_K_XL
# Inherits all global values

# OCR specialist (Overrides parameters to restrict context and lower temperature)
[LightOn]
model = staghado/LightOnOCR-2-1B-Q8_0-GGUF
ctx-size = 16384
temp = 0.2
top-k = 0
top-p = 0.9

# Lightweight agent / fast logic model
[qwen35]
model = unsloth/Qwen3.5-4B-GGUF:UD-Q4_K_XL
ctx-size = 16384
temp = 0.7
top-k = 0
top-p = 0.9
```

## Starting the server in router mode

```bash
llama-server --models-preset <path>/models.ini --models-max 1
```

The `--models-max` switch limits the server to load only one model at a time.

## Using router mode with the pi CLI

Install the plugin:

```bash
pi install npm:pi-llama-cpp
```

Then configure pi in `~/.pi/agents/models.json` as follows:

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
