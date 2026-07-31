#!/bin/bash
# 用法：source utils/setup_env.sh <配置文件路径>
# 功能：根据配置文件计算并导出所有公共环境变量
if [ -z "$1" ]; then
    echo "Usage: source utils/setup_env.sh <config_file_path>" >&2
    return 1
fi
CONF_FILE="$1"
if [ ! -f "$CONF_FILE" ]; then
    echo "Error: Config file $CONF_FILE not found" >&2
    return 1
fi
# 加载用户配置
source "$CONF_FILE"

# 设置默认值并计算派生变量
export SAVE_DIR="${SAVE_DIR:-./result}"
export MODEL_NAME="$(basename "$MODEL_PATH")"
export WORKDIR="${WORKDIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export LOG_DIR="./${SAVE_DIR}/${MODEL_NAME}_${IMAGE##*:}_$(basename "$CONF_FILE" .sh)_tp${TP}_$(md5sum "$CONF_FILE" | cut -c1-8)"
export CONTAINER_NAME="bench-${MODEL_NAME}-$(basename "$CONF_FILE" .sh)"

mkdir -p "$SAVE_DIR"
env_file="$SAVE_DIR/env_info.txt" # 开启系统信息搜集
[ -f "$env_file" ] || bash utils/export_dcu_env_info.sh -o "$env_file"

mkdir -p "$LOG_DIR"
cp "$CONF_FILE" "$LOG_DIR/config.sh"

# 可选：打印关键变量便于调试
echo "Environment variables set:"
echo "  SAVE_DIR=$SAVE_DIR"
echo "  MODEL_NAME=$MODEL_NAME"
echo "  LOG_DIR=$LOG_DIR"
echo "  CONTAINER_NAME=$CONTAINER_NAME"
echo "  TP=$TP"