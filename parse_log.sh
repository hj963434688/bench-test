#!/bin/bash
set -e

# ==================== 配置 ====================
# 指定日志目录（可修改）
LOG_DIR="./logs"

# 默认模型名称（如果文件名中未包含，则使用此值）
DEFAULT_MODEL_NAME="Qwen3-32B"
DEFAULT_TP=2

# 要提取的指标（按顺序，需与日志中的文字完全一致）
# 注意：如果在某些日志中找不到，会填充 "NA"
METRICS="Mean TTFT (ms),Mean TPOT (ms),Output token throughput (tok/s),Total token throughput (tok/s),P99 TTFT (ms),P99 TPOT (ms),Acceptance rate (%),Acceptance length"

# 输出CSV文件
OUTPUT_CSV="${LOG_DIR}/total_summary.csv"

# ==================== 解析指标列表 ====================
declare -a all_metrics=()
IFS=',' read -r -a user_metrics <<< "$METRICS"
for item in "${user_metrics[@]}"; do
    item="$(echo "$item" | xargs)"
    [[ -n "$item" ]] && all_metrics+=("$item")
done

# ==================== 构建表头 ====================
headers="Model Name,TP,Input Length,Output Length,Requests"
for metric in "${all_metrics[@]}"; do
    headers="$headers,$metric"
done
echo "$headers" > "$OUTPUT_CSV"

# ==================== 解析函数（提取行尾数字） ====================
parse_log_file() {
    local log_file="$1"
    local values=""
    for metric in "${all_metrics[@]}"; do
        # 使用 awk 进行子串匹配（忽略大小写），提取行尾数字
        val=$(awk -v k="$metric" 'BEGIN{IGNORECASE=1} index($0, k) {for(i=NF;i>=1;i--) if($i~/^[0-9.]+$/){print $i; exit}}' "$log_file")
        [[ -z "$val" ]] && val="NA"
        values="${values}${values:+,}$val"
    done
    echo "$values"
}

# ==================== 从文件名提取参数 ====================
extract_params() {
    local filename="$1"
    local model_name="$DEFAULT_MODEL_NAME"
    local input_len="" output_len="" batch_size=""
    # 例如：Qwen3-32B_in256_out256_req1_20260723_172156.log
    # 用下划线分割
    IFS='_' read -r -a parts <<< "$filename"
    for part in "${parts[@]}"; do
        if [[ "$part" == in* ]]; then
            input_len="${part#in}"
        elif [[ "$part" == out* ]]; then
            output_len="${part#out}"
        elif [[ "$part" == req* ]]; then
            batch_size="${part#req}"
        elif [[ "$part" =~ ^[A-Za-z0-9-]+$ ]] && [[ -z "$model_name_override" ]]; then
            # 如果第一部分像模型名（不包含下划线），尝试使用它
            # 但简单起见，我们只保留第一个非空部分作为模型名
            :
        fi
    done
    # 如果未提取到，使用默认值
    [[ -z "$model_name" ]] && model_name="$DEFAULT_MODEL_NAME"
    # 如果未提取到 input/output/batch，则跳过该文件（或设置为空）
    if [[ -z "$input_len" || -z "$output_len" || -z "$batch_size" ]]; then
        echo "WARNING: Cannot parse filename $filename, skipping..." >&2
        return 1
    fi
    # 输出
    echo "$model_name,$input_len,$output_len,$batch_size"
}

# ==================== 遍历所有 .log 文件 ====================
if [[ ! -d "$LOG_DIR" ]]; then
    echo "Error: Directory $LOG_DIR does not exist." >&2
    exit 1
fi

log_files=("$LOG_DIR"/*.log)
if [[ ${#log_files[@]} -eq 1 && ! -f "${log_files[0]}" ]]; then
    echo "No .log files found in $LOG_DIR" >&2
    exit 0
fi

echo "Parsing log files in $LOG_DIR ..."
for log_file in "${log_files[@]}"; do
    [[ -f "$log_file" ]] || continue
    filename=$(basename "$log_file")
    echo "Processing $filename ..."

    # 提取参数
    params=$(extract_params "$filename")
    if [[ $? -ne 0 ]]; then
        continue
    fi
    IFS=',' read -r model_name input_len output_len batch_size <<< "$params"

    # 解析指标
    all_values=$(parse_log_file "$log_file")

    # 写入CSV
    echo "$model_name,$DEFAULT_TP,$input_len,$output_len,$batch_size,$all_values" >> "$OUTPUT_CSV"

    # 打印摘要
    echo ">> Extracted: requests=$batch_size, input=$input_len, output=$output_len"
    IFS=',' read -r -a val_array <<< "$all_values"
    for idx in "${!all_metrics[@]}"; do
        echo "   ${all_metrics[$idx]}: ${val_array[$idx]}"
    done
    echo "------------------------------------------"
done

echo "All logs parsed. Results saved to $OUTPUT_CSV"