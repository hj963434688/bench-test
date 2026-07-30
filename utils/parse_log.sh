#!/bin/bash
set -e

# ==================== 可配置参数（支持环境变量覆盖） ====================
: "${LOG_DIR:=./save_dir}"
: "${DEFAULT_MODEL_NAME:=}"                           # 若文件名无法解析，则使用此默认值（空表示不设默认）
: "${DEFAULT_TP:=2}"
: "${METRICS:=Mean TTFT (ms),Mean TPOT (ms),Output token throughput (tok/s),Total token throughput (tok/s),P99 TTFT (ms),P99 TPOT (ms),Acceptance rate (%),Acceptance length}"
: "${OUTPUT_CSV:=${LOG_DIR}/total_summary.csv}"

mkdir -p "$LOG_DIR"

# ==================== 解析指标 ====================
declare -a all_metrics=()
IFS=',' read -r -a user_metrics <<< "$METRICS"
for item in "${user_metrics[@]}"; do
    item="$(echo "$item" | xargs)"
    [[ -n "$item" ]] && all_metrics+=("$item")
done

# ==================== 表头 ====================
headers="Folder,Model Name,TP,Input Length,Output Length,Requests"
for metric in "${all_metrics[@]}"; do
    headers="$headers,$metric"
done
echo "$headers" > "$OUTPUT_CSV"

# ==================== 解析函数 ====================
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

# ==================== 从文件名提取参数 ====================
extract_params() {
    local filename="$1"
    # 提取模型名：取第一个 "_in" 之前的部分
    local model_name="${filename%%_in*}"
    # 如果未提取到（没有 _in），则使用默认值或整个文件名（不含扩展）
    if [[ "$model_name" == "$filename" ]]; then
        model_name="${DEFAULT_MODEL_NAME:-$(basename "$filename" .log)}"
    fi
    local input_len="" output_len="" batch_size=""
    # 提取 input, output, requests
    if [[ "$filename" =~ _in([0-9]+)_out([0-9]+)_req([0-9]+) ]]; then
        input_len="${BASH_REMATCH[1]}"
        output_len="${BASH_REMATCH[2]}"
        batch_size="${BASH_REMATCH[3]}"
    else
        echo "WARNING: Cannot parse input/output/req from $filename, skipping..." >&2
        return 1
    fi
    echo "$model_name,$input_len,$output_len,$batch_size"
}

# ==================== 收集并按时间排序所有 .log 文件 ====================
if [[ ! -d "$LOG_DIR" ]]; then
    echo "Error: Directory $LOG_DIR does not exist." >&2
    exit 1
fi

echo "Parsing log files under $LOG_DIR (sorted by modification time)..."
found_any=false

# 使用 find 递归查找所有 .log 文件（深度≥2），排除非基准文件，按修改时间排序
while IFS= read -r log_file; do
    [[ -z "$log_file" ]] && continue
    found_any=true

    # 提取文件夹名（一级子目录名）
    folder_name=$(basename "$(dirname "$log_file")")
    filename=$(basename "$log_file")
    echo "Processing $folder_name/$filename ..."

    params=$(extract_params "$filename")
    if [[ $? -ne 0 ]]; then
        continue
    fi
    IFS=',' read -r model_name input_len output_len batch_size <<< "$params"
    all_values=$(parse_log_file "$log_file")
    echo "$folder_name,$model_name,$DEFAULT_TP,$input_len,$output_len,$batch_size,$all_values" >> "$OUTPUT_CSV"
    echo "    >> Extracted: requests=$batch_size, input=$input_len, output=$output_len"
    IFS=',' read -r -a val_array <<< "$all_values"
    for idx in "${!all_metrics[@]}"; do
        echo "       ${all_metrics[$idx]}: ${val_array[$idx]}"
    done
done < <(find "$LOG_DIR" -mindepth 2 -type f -name "*.log" ! -name "serve.log" ! -name "shell-*.log" -printf "%T@ %p\n" | sort -n | cut -d' ' -f2-)

if [[ "$found_any" == false ]]; then
    echo "No valid benchmark log files found in subdirectories of $LOG_DIR." >&2
else
    echo "All logs parsed. Results saved to $OUTPUT_CSV"
fi