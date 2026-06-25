#  Llama.cpp on Fedora with AMD Hardware

My Configuration:

- Fedora 44 (latest workstation edition)
- AMD Ryzen 9 PRO 8945HS
- 64GB RAM, VRAM  configured to AUTO in BIOS
- AMD ROCm etc. see ROCM_BUILD.md and the llama.cpp documents.

By default the script now builds GPU support on Vulkan rather then ROCm/HIP. On my setup, performance is similar but Vulkan seems more stable.

## BIOS

I find that setting `PERFORMANCE` mode in bios, and GPU VRAM to `auto` causes the GPU to run better as well
as cooler!

## Overview

Local LLM inference using llama.cpp on AMD Radeon iGPU, text, code generation and visual modes e.g. OCR.

## Available Scripts

The following scripts are available for use:

- `build_lamacpp.sh` - Build llama.cpp with ROCm/HIP or Vulkan (default) support
- `start_server.sh` - Start llama-server with model selection from json configuration file (models.json).

# Getting Started

## Hardware and Software Requirements

- llama.cpp (built via `build_lamacpp.sh` source cloned from github in subdirectory llama.cpp/)
- jq (for parsing `models.json`)
- Internet connection (for automatic model downloads from Hugging Face)
- Python3
- cmake, git, make (build tools)

**Note:** The `build_lamacpp.sh hip` script builds llama.cpp with ROCm/HIP support for AMD GPUs, or Vulkan support with `./build_lamacpp.sh vulkan` (default). For NVIDIA GPUs or pre-built binaries, see llama.cpp documentation.

### Build Script Options

Use `./build_lamacpp.sh -h` or `--help` to view all options:

```
Usage: build_lamacpp.sh [OPTIONS] [BACKEND]

Options:
  -h, --help              Show this help message and exit
  -o, --output DIR        Set custom build output directory under llama.cpp subdirectory
```
## Dependencies

### HIP / ROCm (AMD GPU, default)

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
- On fedora, `libglvnd` libraries are included by default, so no extra setup is needed.

### To build llama.cpp:

```bash
# Clone latest llama.cpp (alternatively clone a stable release)
git clone https://github.com/ggerganov/llama.cpp.git

# Build for AMD ROCm/HIP
./build_lamacpp.sh hip

# Or build for Vulkan (default)
./build_lamacpp.sh vulkan

# Custom build directory
./build_lamacpp.sh -o build-vulkan   (output in ./llama.cpp/build-vulkan)
```

Vulkan performance is similar (320/22tps compared to 340/17tps) but maybe more stable.

The script can be run repeatedly to update and build llama.cpp with new (daily) updates.

# Starting the server

## Models configuration

The `models.json` config file defines named profiles with their own parameters. Each profile has a unique identifier to be used with `-m`. The default profile is marked with `"default": true` e.g. in sample `models.json`:

- **llama33** - Llama 3.3 8B  [default]
- **glm47** - GLM-4.7 23B
- **qwen35** - Qwen3.5 35B

## Model Loading

Models are configured via the `model` field in `models.json` using HuggingFace format `org/repo:quant`. The local hf cache is checked first, falling back to download if not found.

### Local hf cache
If the model is not in the local hf cache it will be downloaded or updated. The local cache is managed with the `hf` (huggingface-hub) tool from Huggingface, see (https://huggingface.co/docs/huggingface_hub/en/guides/cli) and `hf cache --help`.

## Starting the server

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

You can use the following options for `start_server.sh`:

- `-m, --model <profile>` - Use a named profile from `models.json`
- `-c, --context <num>` - Override context size from `models.json`
- `-s, --select` - Interactive model selection menu (Enter loads default)
- `-l, --list` - List available models configured in `models.json`
- `-p, --print` - Prints the command that will be executing without actually executing it
- `-f, --force-download` - Force download from HuggingFace even if local file exists
- `-h, --help` - Display help with all these options

any extra flags at the end, e.g. `-ngl 40` will be passed on to llama-server.

# Adding Models to models.json

Edit `models.json` to add a new profile e.g.:

```json
{
  "models": {
    "your-model": {
      "default": false,
      "model": "org/repo:filename",
      "context": 32768,
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
- `options` - Additional llama-server flags

# Examples script use:

## Text or Coding

```bash
# Start with default model (llama33)
./start_server.sh

# List available profiles (shows default marked)
./start_server.sh --list

# Interactive selection (default shown, Enter loads default)
./start_server.sh --select

# Start with a specific model profile
./start_server.sh --model glm47
./start_server.sh -m qwen35

# Combine with other options
./start_server.sh --model qwen35 --context 32768
./start_server.sh -m llama33 -c 16384

# Pass extra flags to llama-server
./start_server.sh --model glm47 --port 8080
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

Other visually capable models, e.g. Qwen3.5, also works well for OCR with the same python script.

# Troubleshooting

If the model fails to load the problem is normally insufficient GPU RAM. On my setup I have 64GB shared RAM, half of which made available to GPU (VRAM) by the os. This means I can load models with 30G parameters but limited context of 8192, or smaller models with larger context. You can also try reducing the llama-server memory usage by harsher quantization. I find a smaller batch size (default=2048) e.g. `-b 512` works better.

# Working with Pi coding agent (or OpenCode)

Pi seems fairly stable when running qwen35 with a context of 65536 in. Gemma4 is also useful but less stable. On the ROCm/HIP driver GPU Hangs tend to happen after a while. The problem does not seem related to memory constraints, rather instabilities in the driver. Smaller models are fine and OCR works very well.

Pi also works ok with qwen3.6-35B or 27B, but they are a lot slower.
