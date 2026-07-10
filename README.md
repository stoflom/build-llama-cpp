#  Llama.cpp on Fedora with AMD Hardware

My Configuration:

- Fedora 44 (latest workstation edition)
- AMD Ryzen 9 PRO 8945HS
- 64GB RAM, VRAM  configured to AUTO in BIOS
- AMD ROCm etc. see the llama.cpp documentation for the current HIP/ROCm build requirements.

By default the script builds GPU support on Vulkan rather than ROCm/HIP. On my setup, performance is similar but Vulkan seems more stable.

## BIOS

I find that setting `PERFORMANCE` mode in bios, and GPU VRAM to `auto` causes the GPU to run better as well
as cooler!

## Overview

Local LLM inference using llama.cpp on AMD Radeon iGPU, text, code generation and visual modes e.g. OCR.

## Available Scripts

- `build_llamacpp.sh` - Build llama.cpp with Vulkan (default) or ROCm/HIP support
- `start_server.sh` - Start llama-server with model selection from `models.json`
- `ocr-ai.py` - Perform OCR on PDF documents using a selected model

## Model Comparison

- **Qwen3.6 35B** (default) - Better for general purpose tasks
- **Qwen3.6 27B** - Better for coding complex tasks but much slower

## Getting Started

### Requirements

- llama.cpp (auto-cloned by `build_llamacpp.sh` into `./llama.cpp`, or clone manually first)
- jq (for parsing `models.json`)
- Internet connection (for automatic model downloads from Hugging Face)
- Python3, cmake, git, make

**Note:** Default backend is Vulkan. Use `./build_llamacpp.sh hip` for AMD ROCm/HIP support. For NVIDIA or pre-built binaries, see llama.cpp documentation.

#### Build Script Options

```
Usage: build_llamacpp.sh [OPTIONS] [BACKEND]

Build llama.cpp with GPU acceleration support.

Arguments:
  BACKEND     Build backend to use (default: vulkan)
               hip      - Build with ROCm/HIP support
               vulkan   - Build with Vulkan support

Options:
  -h, --help              Show this help message and exit
  -o, --output DIR        Set the build output directory
                          (default: ./llama.cpp/build)

Examples:
  ./build_llamacpp.sh                  # Vulkan (default)
  ./build_llamacpp.sh hip              # ROCm/HIP
  ./build_llamacpp.sh -o build-vulkan  # Custom output dir
```
### Dependencies

#### HIP / ROCm (AMD GPU)

```bash
sudo dnf install rocm-hip rocm-opencl rocm-runtime rocm-smi rocminfo rocm-devel
```

- `rocwmma-devel` is **not** supported on `gfx1103` (Ryzen 8945HS).
- Ensure your user has access to the graphics hardware:
  ```bash
  sudo usermod -aG video,render $USER
  ```
  (Log out and back in for group changes to take effect.)
- Optional: set `HSA_OVERRIDE_GFX_VERSION=11.0.2` in your shell profile if the GPU is not recognized by ROCm (may not be needed on newer setups).

### Vulkan (any GPU)

```bash
sudo dnf install vulkan-headers vulkan-loader-devel vulkan-tools spirv-tools glslc glslang mesa-vulkan-drivers virglrenderer
```

- Supports AMD, Intel, and NVIDIA GPUs — no proprietary drivers required.
- On Fedora, `libglvnd` libraries are included by default, so no extra setup is needed.

The script clones llama.cpp into `./llama.cpp` if not present, then always fetches and builds the latest master. Re-run to update and rebuild.

## Starting the Server

### Models Configuration

The `models.json` config file defines named profiles with their own parameters. Each profile has a unique identifier to be used with `-m`. The default profile is marked with `"default": true`. Current profiles:

- **qwen36** - Qwen3.6 35B-A3B (General purpose, text and image) [default]
- **qwen36-27** - Qwen3.6 27B (Complex reasoning but slow)
- **gemma4** - Gemma 4 26B-A4B (General purpose, text and image)
- **LightOn** - LightOnOCR 2.1B (OCR specialist, text and image)

### Model Loading

Models are configured via the `model` field in `models.json` using HuggingFace format `org/repo:quant`. The local hf cache is checked first, falling back to download if not found.

#### Local HF Cache
If the model is not in the local hf cache it will be downloaded or updated. The local cache is managed with the `hf` (huggingface-hub) tool from Huggingface, see (https://huggingface.co/docs/huggingface_hub/en/guides/cli) and `hf cache --help`. To list contents of cache

```
hf cache ls --format json | jq .
```

### Starting the Server

To start the server use one of the models configured in models.json.

```bash
# Start server (default model)
./start_server.sh

#or list available model profiles
./start_server.sh --list

# Or select a model interactively
./start_server.sh --select
```

## Options

Usage: `start_server.sh [-m|--model PROFILE] [-c|--context SIZE] [-s|--select] [-l|--list] [-p|--print] [-n|--new] [--host HOST] [--port PORT] [extra_flags...]`

- `-m, --model <profile>` - Model profile key (e.g. qwen36, gemma4, LightOn)
- `-c, --context <num>` - Override context size from profile
- `-s, --select` - Interactive model selection menu
- `-l, --list` - Validate `models.json` and list available profiles
- `-p, --print` - Print command without executing
- `-n, --new` - Add a new model profile interactively (prompts for name, HF model ID, context, comment, options)
- `--host <addr>` - Override host binding address (default: 0.0.0.0)
- `--port <port>` - Override listening port (default: 8080)
- `-f, --force-download` - Force download from HuggingFace
- `-h, --help` - Display this help message

Any extra flags are passed through to llama-server.

# Adding Models to models.json

Use the `--new` flag to add a profile interactively:

```bash
./start_server.sh --new
```

This will prompt for the profile name, HuggingFace model ID, context size, comment, options, and whether to set it as default.

Alternatively, edit `models.json` manually to add a new profile e.g.:

```json
{
  "models": {
    "your-model": {
      "default": false,
      "model": "org/repo:filename",
      "context": 32768,
      "comment": "General purpose, text and image",
      "options": ["-fa on"]
    }
  }
}
```

**Fields:**

- `your-model` - Unique identifier used with `-m` flag
- `default` - Set `true` for one model only (used when no flags provided)
- `model` - HuggingFace repo and filename in format `org/repo:filename`
- `context` - Context window size in tokens
- `comment` - Short description of model capabilities (displayed in listings and menus)
- `options` - Additional llama-server flags

# Examples script use:

## Text or Coding

```bash
# Start with default model (qwen36)
./start_server.sh

# Add a new model profile interactively
./start_server.sh --new

# List available profiles (default marked)
./start_server.sh --list

# Interactive selection (Enter loads default)
./start_server.sh --select

# Start with a specific model profile
./start_server.sh --model gemma4
./start_server.sh -m qwen36

# Combine with other options
./start_server.sh --model gemma4 --context 32768
./start_server.sh -m qwen36 -c 16384

# Pass extra flags to llama-server
./start_server.sh --model gemma4 --port 9090

# Start on a different host and port
./start_server.sh --host 127.0.0.1 --port 9090
```

## For OCR with LightOnOCR model

```bash
#using the LightOnOCR model (https://arxiv.org/pdf/2601.14251) configured in models.json
./start_server.sh -m LightOn

#then to convert scanned document in pdf format using a python script:
./ocr-ai.py input.pdf output.md

# optional: specify individual pages or page ranges (comma-separated), retries and backoff, page markers, or custom URL
./ocr-ai.py --pages "1,3,5-10" --dpi 200 --retries 3 --backoff 2 --page-marker input.pdf output.md

# if no --pages is specified, all pages are processed
./ocr-ai.py input.pdf output.md

# or see help
./ocr-ai.py -h
```

**NOTE: the LightOnOCR model is optimized for scans at 200dpi using normal fonts. For small fonts, math or handwritten text use 300dpi. This applies to the scanner as well as the `--dpi` parameter of the script.**

Other visually capable models (e.g. Qwen3.6) also work well for OCR with the same python script.

# Troubleshooting

If the model fails to load the problem is normally insufficient GPU RAM. On my setup I have 64GB shared RAM, half of which made available to GPU (VRAM) by the os. This means I can load models with 30G parameters but limited context of 8192, or smaller models with larger context. You can also try reducing the llama-server memory usage by harsher quantization. I find a smaller batch size (default=2048) e.g. `-b 512` works better.

# Working with coding agents (Pi, OpenCode)

Qwen3.6 35B (default) works well for general purpose tasks with a context of 65536. Qwen3.6 27B is better for complex coding tasks but much slower. Gemma4 26B is also useful but more demanding. On ROCm/HIP, GPU hangs can occur after extended use — this appears to be driver instability rather than memory pressure. Smaller models and OCR workloads are very stable.
