#!/bin/bash
set -o pipefail
: "${TASKS_DIR:=./configs}"                       # 配置文件目录
echo "======= Start test ======="
ls "$TASKS_DIR"
config_files=($(find "$TASKS_DIR" -maxdepth 1 -type f ! -name ".*" ! -name "setup*" | sort))
# ==================== 等待端口 ====================
wait_for_port() {
    local port=$1
    local max_attempts=120
    local sleep_seconds=30
    echo "Waiting for port $port to be ready..."
    for ((i=1; i<=max_attempts; i++)); do
        if timeout 1 bash -c "echo >/dev/tcp/localhost/$port" 2>/dev/null; then
            echo "Port $port is ready."
            return 0
        fi
        echo "Attempt $i/$max_attempts: port $port not ready yet, waiting $sleep_seconds seconds..."
        sleep $sleep_seconds
    done
    echo "Error: Port $port did not become ready in time." >&2
    return 1
}

# ==================== 清理容器 ====================
cleanup() {
    echo "Cleaning up container: $CONTAINER_NAME and sleep 30"
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    sleep 30
}

# ==================== 主循环 ====================
for conf_file in "${config_files[@]}"; do
    echo "------------------- Processing configuration: $conf_file -----------------------"
    source "$conf_file"
    source configs/setup_env.sh "$conf_file"
    # continue
    cleanup
    bash run-serve.sh 2>&1 | tee "$LOG_DIR/shell-serve.log"

    if ! wait_for_port "$PORT"; then
        echo "Port wait failed, skip"
        cleanup
        continue
    fi

    # 执行测试
    if docker exec "$CONTAINER_NAME" bash -c "cd $WORKDIR &&  source configs/setup_env.sh "$conf_file" \
        &&  bash run-binary.sh" 2>&1 | tee "$LOG_DIR/shell-test.log"; then
        echo "Test succeeded for $conf_file"
    else
        echo "Test failed for $conf_file"
    fi

    # 清理容器（避免端口占用）
    cleanup
    echo "------------------- Processing configuration: $conf_file -----------------------"

done

echo "All tasks completed."