#!/bin/bash
set -e

# 统一日志函数（前缀+时间戳）
log() { echo "[run-binary] $(date '+%Y-%m-%d %H:%M:%S') - $*" >&2; }

# ==================== 环境变量默认值 ====================
: "${MODEL_PATH:=/data1/models/Qwen3.5-27B}"
: "${MODEL_NAME:=Qwen3.5-27B}"
: "${PORT:=8000}"
: "${TP:=2}"
: "${BACKEND:=vllm}"
: "${DATA_TYPE:=float16}"
: "${CASE_PAIR:=[[256,256]]}"
: "${BATCH_SIZES:=[1,4,8,16,32,64]}"
: "${LOG_DIR:=./logs}"
: "${METRICS:=Mean TTFT (ms),Mean TPOT (ms),Output token throughput (tok/s),Total token throughput (tok/s)}"

# 搜索专用参数
: "${SEARCH_METRICS:=}"
: "${SEARCH_THRESHOLDS:=}"
: "${SEARCH_START_BATCH:=1}"
: "${SEARCH_MAX_BATCH:=1024}"

IFS=',' read -r -a tp_list <<< "$TP"
TP=${tp_list[0]}

mkdir -p "$LOG_DIR"
timestamp=$(date +%Y%m%d_%H%M%S)
output_csv="$LOG_DIR/${MODEL_NAME}_bench_${timestamp}.csv"

# ==================== 解析指标 ====================
headers="Model Name,TP,Input Length,Output Length,batch_size"
declare -a all_metrics=()
if [[ -n "$METRICS" ]]; then
    IFS=',' read -r -a user_metrics <<< "$METRICS"
    for item in "${user_metrics[@]}"; do
        item="$(echo "$item" | xargs)"
        if [[ -n "$item" ]]; then
            all_metrics+=("$item")
            headers="$headers,$item"
        fi
    done
fi
echo "$headers" > "$output_csv"

# ==================== 解析阈值 ====================
declare -A THRESHOLD_MAP
if [[ -n "$SEARCH_METRICS" && -n "$SEARCH_THRESHOLDS" ]]; then
    IFS=',' read -r -a search_metrics_arr <<< "$SEARCH_METRICS"
    IFS=',' read -r -a search_thresholds_arr <<< "$SEARCH_THRESHOLDS"
    for i in "${!search_metrics_arr[@]}"; do
        metric="$(echo "${search_metrics_arr[i]}" | xargs)"
        threshold="$(echo "${search_thresholds_arr[i]}" | xargs)"
        THRESHOLD_MAP["$metric"]="$threshold"
    done
fi

# ==================== 解析函数 ====================
parse_output() {
    local output="$1"
    local values=""
    for metric in "${all_metrics[@]}"; do
        # 使用 awk 进行不区分大小写的子串匹配，取行尾第一个数字
        val=$(echo "$output" | awk -v k="$metric" 'BEGIN{IGNORECASE=1} index($0, k) {for(i=NF;i>=1;i--) if($i~/^[0-9.]+$/){print $i; exit}}')
        [[ -z "$val" ]] && val="NA"
        values="${values}${values:+,}$val"
    done
    echo "$values"
}

# ==================== 检查阈值 ====================
check_thresholds() {
    local values_str=$1
    IFS=',' read -r -a val_array <<< "$values_str"
    for i in "${!all_metrics[@]}"; do
        local metric="${all_metrics[$i]}"
        if [[ -n "${THRESHOLD_MAP[$metric]}" ]]; then
            local val="${val_array[$i]}"
            local threshold="${THRESHOLD_MAP[$metric]}"
            if [[ "$val" == "NA" ]]; then
                log "Metric $metric is NA"
                return 1
            fi
            if awk -v a="$val" -v b="$threshold" 'BEGIN{exit !(a > b)}'; then
                log "Metric $metric = $val > $threshold (not satisfied)"
                return 1
            else
                log "Metric $metric = $val <= $threshold (satisfied)"
            fi
        fi
    done
    return 0
}

# ==================== 单次测试执行 ====================
run_one_test() {
    local batch_size=$1
    local input_len=$2
    local output_len=$3
    local log_file="$LOG_DIR/${MODEL_NAME}_in${input_len}_out${output_len}_req${batch_size}_${timestamp}.log"
    local json_file="${MODEL_NAME}_in${input_len}_out${output_len}_req${batch_size}_${timestamp}.json"
    if [[ "$BACKEND" == "sglang" ]]; then
        cmd="python3 -m sglang.bench_serving  --served-model-name $MODEL_NAME --model $MODEL_PATH --dataset-name random-ids --num-prompts $batch_size --random-input-len $input_len --random-output-len $output_len --port $PORT --random-range-ratio 1 --output-file $LOG_DIR/$json_file"
    elif [[ "$BACKEND" == "vllm" ]]; then
        cmd="vllm bench serve  --model $MODEL_NAME --tokenizer $MODEL_PATH  --dataset-name random --num-prompts $batch_size --trust-remote-code --random-input-len $input_len --random-output-len $output_len --port $PORT --ignore-eos  --save-result --result-dir $LOG_DIR --result-filename $json_file"
    else
        log "Unsupported backend: $BACKEND" >&2
        exit 1
    fi

    log "Executing: $cmd"
    output=$(echo $cmd 2>&1 | tee "$log_file")
    # output=$(eval $cmd 2>&1 | tee "$log_file")

    all_values=$(parse_output "$output")
    echo "$MODEL_NAME,$TP,$input_len,$output_len,$batch_size,$all_values" >> "$output_csv"
    
    # 打印总结
    IFS=',' read -r -a val_array <<< "$all_values"
    summary=""
    for idx in "${!all_metrics[@]}"; do
        summary="${summary}${summary:+, }${all_metrics[$idx]}=${val_array[$idx]}"
    done
    log "Summary: batch_size=$batch_size, input=$input_len, output=$output_len | $summary"

    echo "$all_values"   # 供搜索模式捕获
}

# ==================== 检查阈值 ====================
check_thresholds() {
    local values_str=$1
    IFS=',' read -r -a val_array <<< "$values_str"
    for i in "${!all_metrics[@]}"; do
        local metric="${all_metrics[$i]}"
        if [[ -n "${THRESHOLD_MAP[$metric]}" ]]; then
            local val="${val_array[$i]}"
            local threshold="${THRESHOLD_MAP[$metric]}"
            [[ "$val" == "NA" ]] && return 1
            awk -v a="$val" -v b="$threshold" 'BEGIN{exit !(a > b)}' && return 1
        fi
    done
    return 0
}

# ==================== 搜索模式 ====================
run_search() {
    log "=== Starting search mode === Thresholds: $SEARCH_METRICS -> $SEARCH_THRESHOLDS"
    local combinations=$(echo "$CASE_PAIR" | sed 's/\[\[//g; s/\]\]//g; s/\],\[/\n/g')
    echo "$combinations" | while IFS=',' read -r input_len output_len; do
        input_len=$(echo "$input_len" | tr -d ' ')
        output_len=$(echo "$output_len" | tr -d ' ')
        log "Searching for max batch for input=$input_len, output=$output_len"

        local low=0
        local high=$SEARCH_MAX_BATCH
        local current=$SEARCH_START_BATCH
        local success_batch=0

        log "Phase 1: Exponential growth"
        while [[ $current -le $SEARCH_MAX_BATCH ]]; do
            log "Testing batch_size=$current"
            values_str=$(run_one_test $current $input_len $output_len)
            if check_thresholds "$values_str"; then
                log "Thresholds satisfied for batch=$current"
                success_batch=$current
                low=$current
                current=$((current * 2))
            else
                log "Thresholds NOT satisfied for batch=$current"
                high=$current
                break
            fi
        done

        if [[ $current -gt $SEARCH_MAX_BATCH ]]; then
            log "Maximum batch $SEARCH_MAX_BATCH satisfied, setting as result."
            success_batch=$SEARCH_MAX_BATCH
        else
            log "Phase 2: Binary search between $low and $high"
            while [[ $((high - low)) -gt 1 ]]; do
                mid=$(( (low + high) / 2 ))
                log "Testing batch_size=$mid"
                values_str=$(run_one_test $mid $input_len $output_len)
                if check_thresholds "$values_str"; then
                    low=$mid
                else
                    high=$mid
                fi
            done
            success_batch=$low
        fi

        log ">>> Max batch for input=$input_len, output=$output_len: $success_batch"
        log "------------------------------------------"
    done
}

# ==================== 固定模式 ====================
run_fixed() {
    log "Starting benchmark test with backend: $BACKEND ..."
    combinations=$(echo "$CASE_PAIR" | sed 's/\[\[//g; s/\]\]//g; s/\],\[/\n/g')
    batch_sizes_list=$(echo "$BATCH_SIZES" | sed 's/\[//g; s/\]//g; s/,/\n/g')

    # 使用进程替换避免管道子 shell 导致变量丢失
    while IFS=',' read -r input_len output_len; do
        input_len=$(echo "$input_len" | tr -d ' ')
        output_len=$(echo "$output_len" | tr -d ' ')
        while read -r batch_size; do
            run_one_test $batch_size $input_len $output_len > /dev/null
        done < <(echo "$batch_sizes_list")
    done < <(echo "$combinations")
}

# ==================== 主逻辑 ====================
if [[ -n "$SEARCH_METRICS" && -n "$SEARCH_THRESHOLDS" ]]; then
    log "SEARCH_METRICS set, enabling search mode. Thresholds: $SEARCH_METRICS -> $SEARCH_THRESHOLDS"
    run_search
else
    run_fixed
fi

log "All tasks completed. Logs and CSV are saved in $LOG_DIR."