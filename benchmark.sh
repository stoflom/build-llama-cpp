CMD=(llama.cpp/build/bin/llama-bench -hf unsloth/Qwen3.5-35B-A3B-GGUF:UD-Q4_K_XL -p 512 -n 256 "$@")
echo "CMD: ${CMD[*]}"
exec "${CMD[@]}"
