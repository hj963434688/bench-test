# !/bin/bash

source config.sh
curl http://0.0.0.0:${PORT}/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{
        "model": "'"${MODEL_NAME}"'",
        "max_tokens": 256,
        "messages": [
            {"role": "system", "content": "你是一个有用的助手"},
            {"role": "user", "content": "甲乙两班共有学生98人，甲班比乙班多6人，求两班各有多少人？"}
        ]
    }'

python3 -m sglang.bench_serving  --served-model-name $MODEL_NAME --model $MODEL_PATH --dataset-name random-ids --port $PORT \
    --num-prompts $batch_size --random-input-len $input_len --random-output-len $output_len  --random-range-ratio 1

vllm bench serve  --model $MODEL_NAME --tokenizer $MODEL_PATH  --dataset-name random --port $PORT \
    --num-prompts $batch_size --random-input-len $input_len --random-output-len $output_len  --ignore-eos


modelscope download --dataset AI-ModelScope/MATH-500
#精度测试
data_path=/data2/MATH-500
evalscope eval --model $MODEL_NAME --api-url http://0.0.0.0:$PORT/v1/chat/completions \
    --eval-type server --api-key EMPTY  --datasets math_500 \
    --dataset-args '{"math_500": {"local_path": "/data1/datasets/AI-ModelScope/MATH-500", "subset_list": ["Level 1", "Level 2", "Level 3", "Level 4", "Level 5"]}}'  \
    --generation-config '{"max_tokens":16384, "temperature": 0, "top_p": 1, "timeout": 600000}' \
    --eval-batch-size 64
#性能测试

# 精度测试2
evalscope eval \
    --model $MODEL_NAME  \
    --api-url http://0.0.0.0:$PORT/v1 \
    --eval-type server \
    --generation-config temperature=0.6,top_p=0.95,n=2 \
    --eval-batch-size 32 \
    --stream \
    --timeout 60000 \
    --datasets math_500 \
    --dataset-args '{"math_500": {"local_path": "/data/datasets/AI-ModelScope/MATH-500", "few_shot_num": 0, "few_shot_random": false, "metrics_list": ["Pass@1"]}}'