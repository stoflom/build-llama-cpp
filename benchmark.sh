CMD=(llama.cpp/build/bin/llama-bench -hf unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-Q4_K_M -p 512 -n 256 "$@")
echo "CMD: ${CMD[*]}"
exec "${CMD[@]}"
