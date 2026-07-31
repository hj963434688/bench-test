#!/bin/bash
# 容器配置
: "${IMAGE:=harbor.sourcefind.cn:5443/dcu/admin/base/vllm:0.18.1-ubuntu22.04-dtk26.04-py3.10-}"
: "${CONTAINER_NAME:=bench}"
: "${WORKDIR:=/data/benchtest}"
: "${LOG_DIR:=./logs}"

# 模型与服务
: "${MODEL_PATH:=/data/models/Qwen3.6-27B}"
: "${MODEL_NAME:=Qwen3.6-27B}"
: "${PORT:=8009}"
: "${TP:=2}"
: "${BACKEND:=vllm}"
: "${CMD:=}"

if [[ -n "$CMD" ]]; then
    CMD="$CMD"
else
    CMD=$(cat <<'EOF'
export HIP_VISIBLE_DEVICES=0,1,2,3,4,5,6,7
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
fi

echo "-------> run-serve $MODEL_PATH $IMAGE"
VLLM_ARGS="-tp $TP --port $PORT  --served-model-name $MODEL_NAME"
SGLANG_ARGS="--model-path $MODEL_PATH --tp $TP --port $PORT  --served-model-name $MODEL_NAME"

EXPORT_LINES=$(echo "$CMD" | grep '^export ')
CMD=$(echo "$CMD" | grep -v '^export ' | grep -v '^[[:space:]]*#' | sed -e '/^[[:space:]]*$/d' -e ':a;N;$!ba;s/\\\n//g' -e 's/\n/ /g')
BACKEND=$(echo "$CMD" | awk '{print $1}')
case "$BACKEND" in
    sglang)
        CMD="$CMD $SGLANG_ARGS"
        ;;
    vllm)
        set -- $CMD
        CMD="$1 $2 $MODEL_PATH ${@:4}"
        CMD="$CMD $VLLM_ARGS"
        ;;
    *)
        echo "Error: Unrecognized backend '$BACKEND'. Must start with 'sglang' or 'vllm'." >&2
        exit 1
        ;;
esac

CMD="$EXPORT_LINES"$'\n'"$CMD"
echo $CMD

mkdir -p $LOG_DIR
docker run -d \
    --privileged \
    --net=host \
    --device=/dev/kfd --device=/dev/dri --device=/dev/mkfd \
    --ipc=host --shm-size=512G \
    --group-add video \
    --cap-add=SYS_PTRACE \
    --security-opt seccomp=unconfined \
    -u root --ulimit stack=-1:-1 --ulimit memlock=-1:-1 \
    -v /opt/hyhal:/opt/hyhal:ro \
    -v $WORKDIR:$WORKDIR \
    -v $MODEL_PATH:$MODEL_PATH \
    --name="$CONTAINER_NAME" \
    "$IMAGE" \
    /bin/bash -c "$CMD 2>&1 | tee $WORKDIR/$LOG_DIR/serve.log "