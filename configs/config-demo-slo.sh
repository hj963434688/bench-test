# 模型启动参数配置
export MODEL_PATH="/data1/models/Qwen3.6-27B"
export PORT=8009
export TP=2
export IMAGE="harbor.sourcefind.cn:5443/dcu/admin/base/sglang:0.5.10rc0-ubuntu22.04-dtk26.04-py3.10"
export BACKEND="sglang"
export DATA_TYPE="bf16"
export CMD=$(cat <<'EOF'
export SGLANG_USE_LIGHTOP=1
export SGLANG_USE_MARLIN_W16A16_MOE=1
export SGLANG_USE_FUSED_TOPK_SOFTMAX=1
export SGLANG_ROCM_USE_AITER_MOE=False
export SGLANG_USE_CAUSAL_CONV1D=1
export SGLANG_USE_CUDA_IPC_TRANSPORT=1
export SGLANG_USE_AITER_LINEAR_ATTN=1
export SGLANG_ENABLE_SPEC_V2=1

sglang serve\
    --model-path  /data/models/Qwen3.6-27B \
    --host 0.0.0.0 \
    --port 30000 \
    --served-model-name Qwen3.6-27B \
    --mm-attention-backend fa3 \
    --tp-size 2 --pp-size 1 \
    --attention-backend fa3 \
    --page-size 64 --pp-size 1  \
    --mem-fraction-static 0.9 \
    --keep-mm-feature-on-device \
    --reasoning-parser qwen3 \
    --tool-call-parser qwen3_coder \
    --speculative-algorithm EAGLE \
    --enable-piecewise-cuda-graph \
    --speculative-num-steps 3 \
    --speculative-eagle-topk 1 \
    --speculative-num-draft-tokens 4 \
    --chunked-prefill-size -1 \
    --mamba-scheduler-strategy extra_buffer \
    --cuda-graph-max-bs 64 \
    --kv-cache-dtype fp8_e5m2 
EOF
)

# 测试用例
export BATCH_SIZES="[1,4]"
export CASE_PAIR="[[256,256],[512,512]]"
export METRICS="Mean TTFT (ms),Mean TPOT (ms),Output token throughput (tok/s),Total token throughput (tok/s)"
# export BATCH_SIZES="[1,4,8,16,32,64,128]"
# export CASE_PAIR="[[512,512],[4096,1024],[16384,1024]]"
# export METRICS="Mean TTFT (ms),Mean TPOT (ms),Output token throughput (tok/s),Total token throughput (tok/s),P99 TTFT (ms),P99 TPOT (ms),Acceptance rate (%),Acceptance length"

export SEARCH_METRICS="Mean TTFT (ms),Mean TPOT (ms)"   # 监控的延迟指标，逗号分隔
export SEARCH_THRESHOLDS="2000,20"                      # 对应每个指标的阈值（毫秒）
export SEARCH_START_BATCH=1                             # 起始并发数
export SEARCH_MAX_BATCH=32                              # 最大尝试并发数
#搜索模式参数（若设置 SEARCH_METRICS 和 SEARCH_THRESHOLDS 则启用搜索，否则为固定模式）
                          