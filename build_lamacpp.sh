#!/bin/bash

# ==============================================================================
# Script: build_lamacpp.sh
# Purpose: Build llama.cpp with HIP or Vulkan support.
# Dependencies: Requires ROCm/HIP or Vulkan platform and internet access for git.
# Usage: ./build_lamacpp.sh [hip|vulkan]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
MAIN_DIR="$SCRIPT_DIR"
SOURCE_DIR="${MAIN_DIR}/llama.cpp"
BUILD_DIR="${SOURCE_DIR}/build"

# Default backend
GPU_BACKEND="${1:-vulkan}"

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
else
	echo "Error: Invalid backend '$GPU_BACKEND'. Use 'hip' or 'vulkan'."
	exit 1
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
