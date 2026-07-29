#!/bin/bash
set -o pipefail

# 配置
TASKS_DIR="./tasks"          # 存放配置文件的目录
: "${REBUILD_CONTAINER:=false}"  # 是否重新构建容器
echo "------->start test: "
ls $TASKS_DIR

# 检查 tasks 目录
config_files=()
config_files=($(find "$TASKS_DIR" -maxdepth 1 -type f ! -name ".*" | sort))

# 等待端口
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

# 清理容器
cleanup() {
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}

for conf_file in "${config_files[@]}"; do
    source "$conf_file"
    
    mkdir -p "$LOG_DIR"
    cp "$conf_file" "$LOG_DIR/config.sh"

    # 构建容器（或复用）
    if [[ "$REBUILD_CONTAINER" == "false" ]] && docker ps --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
        echo "Container $CONTAINER_NAME exists, reusing."
    else
        echo "Removing and rebuilding container..."
        cleanup
        bash run-serve.sh 2>&1 | tee "$LOG_DIR/shell-serve.log"
    fi

    # 等待端口
    if ! wait_for_port "$PORT"; then
        echo "Port wait failed, skip this config."
        cleanup
        sleep 30
        continue
    fi

    # 执行测试
    if docker exec "$CONTAINER_NAME" bash -c "cd $WORKDIR && source $conf_file && bash run-binary.sh" \
        2>&1 | tee "$LOG_DIR/shell-test.log"; then
        echo "Test succeeded for $conf_file"
    else
        echo "Test failed for $conf_file"
    fi

    # 清理容器
    cleanup
    sleep 30
    echo "------------------------------------------"
done
