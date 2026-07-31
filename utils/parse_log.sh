#!/bin/bash
set -e

: "${SAVE_DIR:=./result}"
: "${DEFAULT_TP:=2}"
: "${METRICS:=Mean TTFT (ms),Mean TPOT (ms),Output token throughput (tok/s),Total token throughput (tok/s),P99 TTFT (ms),P99 TPOT (ms),Acceptance rate (%),Acceptance length}"
: "${OUTPUT_CSV:=${SAVE_DIR}/total_summary.csv}"

mkdir -p "$SAVE_DIR"

# 解析指标
declare -a all_metrics=()
IFS=',' read -r -a user_metrics <<< "$METRICS"
for item in "${user_metrics[@]}"; do
    item="$(echo "$item" | xargs)"
    [[ -n "$item" ]] && all_metrics+=("$item")
done

# 表头
headers="Folder,Model Name,TP,Input Length,Output Length,Requests"
for metric in "${all_metrics[@]}"; do
    headers="$headers,$metric"
done
echo "$headers" > "$OUTPUT_CSV"

# 解析函数
parse_log_file() {
    local log_file="$1"
    local values=""
    for metric in "${all_metrics[@]}"; do
        val=$(awk -v k="$metric" 'BEGIN{IGNORECASE=1} index($0, k) {for(i=NF;i>=1;i--) if($i~/^[0-9.]+$/){print $i; exit}}' "$log_file")
        [[ -z "$val" ]] && val="NA"
        values="${values}${values:+,}$val"
    done
    echo "$values"
}

# 按时间排序遍历所有 .log 文件（排除 serve.log, shell-*.log）
find "$SAVE_DIR" -mindepth 2 -type f -name "*.log" ! -name "serve.log" ! -name "shell-*.log" -printf "%T@ %p\n" | sort -n | cut -d' ' -f2- | while read -r log_file; do
    folder=$(basename "$(dirname "$log_file")")
    filename=$(basename "$log_file")
    
    # 分割目录名，取第一个字段为模型名，查找 tpN
    IFS='_' read -r -a parts <<< "$folder"
    model_name="${parts[0]}"
    tp="$DEFAULT_TP"
    for part in "${parts[@]}"; do
        if [[ "$part" =~ ^tp([0-9]+)$ ]]; then
            tp="${BASH_REMATCH[1]}"
            break
        fi
    done
    
    # 解析 input/output/requests（文件名中的 inN_outN_reqN）
    if [[ "$filename" =~ in([0-9]+)_out([0-9]+)_req([0-9]+) ]]; then
        input_len="${BASH_REMATCH[1]}"
        output_len="${BASH_REMATCH[2]}"
        requests="${BASH_REMATCH[3]}"
    else
        echo "WARNING: Cannot parse filename $filename, skipping" >&2
        continue
    fi
    
    all_values=$(parse_log_file "$log_file")
    echo "$folder,$model_name,$tp,$input_len,$output_len,$requests,$all_values" >> "$OUTPUT_CSV"
    echo "  Extracted: $folder | $model_name | TP=$tp | input=$input_len output=$output_len requests=$requests"
done

echo "All logs parsed. Results saved to $OUTPUT_CSV"