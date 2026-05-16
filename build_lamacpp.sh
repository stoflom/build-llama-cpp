#!/bin/bash

# ==============================================================================
# Script: build_lamacpp.sh
# Purpose: Build llama.cpp with HIP or Vulkan support.
# Dependencies: Requires ROCm/HIP or Vulkan platform and internet access for git.
# Usage: ./build_lamacpp.sh [OPTIONS] [hip|vulkan]
# Options:
#   -h, --help    Show this help message and exit
#   -o, --output  Set output directory (default: llama.cpp/build)
# ==============================================================================

set -euo pipefail

# Default options
GPU_BACKEND="vulkan"

# -----------------------------------------------------------------------------
# Print Help Message
# -----------------------------------------------------------------------------
show_help() {
    cat << 'EOF'
Usage: build_lamacpp.sh [OPTIONS] [BACKEND]

Build llama.cpp with GPU acceleration support.

Arguments:
  BACKEND     Build backend to use (default: vulkan)
               hip      - Build with ROCm/HIP support
               vulkan   - Build with Vulkan support

Options:
  -h, --help              Show this help message and exit
  -o, --output DIR        Set the build output directory
                          (default: llama.cpp/build)

Examples:
  # Build with Vulkan (default)
  ./build_lamacpp.sh

  # Build with HIP/ROCm
  ./build_lamacpp.sh hip

  # Custom output directory
  ./build_lamacpp.sh -o /custom/path llama.cpp/build

Dependencies:
  - Git (for cloning/updating source)
  - CMake (version 3.14+)
  - GCC or Clang compiler
  - ROCm/HIP toolkit (for HIP backend)
  - Vulkan SDK (for Vulkan backend)

Source Code:
  Ensure llama.cpp is cloned (should be in a subdirectory to the script):
  git clone https://github.com/ggerganov/llama.cpp.git
EOF
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;

        -o|--output)
            BUILD_DIR="$2"
            shift 2
            ;;
        hip|vulkan)
            GPU_BACKEND="$1"
            shift
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            echo "Use --help for usage information." >&2
            exit 1
            ;;
    esac
done

# Set main directory and source directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
MAIN_DIR="$SCRIPT_DIR"
SOURCE_DIR="${MAIN_DIR}/llama.cpp"

# Default build directory if not specified
BUILD_DIR="${BUILD_DIR:-${MAIN_DIR}/llama.cpp/build}"

# CMake options based on backend
if [[ "$GPU_BACKEND" == "vulkan" ]]; then
	CMAKE_OPTIONS=(
		-DGGML_VULKAN=ON
	)
	echo "Configuring build for Vulkan..."
elif [[ "$GPU_BACKEND" == "hip" ]]; then
	# gfx1103 = AMD 780M
	CMAKE_OPTIONS=(
		-DGGML_HIP=ON
		-DAMDGPU_TARGETS=gfx1103
		-DCMAKE_CXX_FLAGS="-fpermissive"
		-DGGML_HIP_UMA=ON
		-DGGML_HIP_FLASH_ATTN=ON
	)
	echo "Configuring build for HIP/ROCm..."
fi

# -----------------------------------------------------------------------------
# Check Dependencies
# -----------------------------------------------------------------------------
# Assumes llama.cpp is cloned in a subdirectory:
#   git clone https://github.com/ggerganov/llama.cpp.git
if [ ! -d "$SOURCE_DIR" ]; then
	echo "Error: Source directory not found at $SOURCE_DIR"
	exit 1
fi

# -----------------------------------------------------------------------------
# Fetch and Update Source
# -----------------------------------------------------------------------------
cd "$SOURCE_DIR"

echo "Updating source code..."
if ! git fetch origin; then
	echo "Error: Failed to fetch from remote."
	exit 1
fi
if ! git pull --ff-only origin master; then
	echo "Error: Failed to pull. You likely have local changes or a merge conflict."
	exit 1
fi

# -----------------------------------------------------------------------------
# Clean and Build
# -----------------------------------------------------------------------------
echo "Cleaning build directory..."
rm -rf "${BUILD_DIR}"

echo "Running CMake configuration..."
cmake -B "${BUILD_DIR}" "${CMAKE_OPTIONS[@]}"

echo "Starting compilation..."
cmake --build "${BUILD_DIR}" --config Release -j$(nproc)

echo "Build completed successfully."
