export SAVE_DIR="./result"
# 模型服务参数配置
export MODEL_PATH="/data1/models/Qwen3.6-35B-A3B/"
export PORT=8009
export TP=2 # 2,4
export IMAGE="harbor.sourcefind.cn:5443/dcu/admin/base/vllm:0.18.1-ubuntu22.04-dtk26.04-py3.10"
export BACKEND="sglang"
export DATA_TYPE="bf16"
export CMD=$(cat <<'EOF'
# export HIP_VISIBLE_DEVICES=6,7
export VLLM_HCU_USE_FLASH_ATTN=1
export VLLM_HCU_USE_CUSTOM_TOPK_TOPP_SAMPLER=1

vllm serve Qwen/Qwen3.6-27B \
  -tp 2 \
  --trust-remote-code \
  --max-num-batched-tokens 10240 \
  --speculative-config.method mtp \
  --speculative-config.num_speculative_tokens 3
EOF
)
# 测试用例
export BATCH_SIZES="[1,4]"
export CASE_PAIR="[[256,256]]"
export METRICS="Mean TTFT (ms),Mean TPOT (ms),Output token throughput (tok/s),Total token throughput (tok/s)"
# export BATCH_SIZES="[1,4,8,16,32,64,128]"
# export CASE_PAIR="[[512,512],[4096,1024],[16384,1024]]"
# export METRICS="Mean TTFT (ms),Mean TPOT (ms),Output token throughput (tok/s),Total token throughput (tok/s),P99 TTFT (ms),P99 TPOT (ms),Acceptance rate (%),Acceptance length"

# 其他配置
tag="${IMAGE##*:}"
config_file_name=$(basename "${BASH_SOURCE[0]}" .sh)
export MODEL_NAME=$(basename "$MODEL_PATH")
export LOG_DIR="./${SAVE_DIR}/${MODEL_NAME}-${tag}-${config_file_name}"
export WORKDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export CONTAINER_NAME="bench-${MODEL_NAME}-${config_file_name}"

