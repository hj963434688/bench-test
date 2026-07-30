# LLM 推理性能自动化测试工具

## 使用方法一：测试所有配置
配置文件：config/config-base.sh config/config-demo-slo.sh
一键启动：bash run-total.sh 
## 使用方法二: 测试单个配置
source config/config-base.sh
bash run-serve.sh
等待服务启动完成
bash run-binary.sh


## 目录结构

```
benchtest/
├── readme              # 本使用手册
├── run-serve.sh        # 启动模型推理服务（Docker 容器）
├── run-binary.sh       # 执行性能压测脚本
├── run-total.sh        # 全流程自动化测试编排
├── parse_log.sh        # 日志解析与指标汇总
├── demo.sh             # 快速演示脚本
├── tasks/              # 测试配置文件目录
│   ├── config-1.sh
│   └── config-2.sh
├── bak/                # 备份的示例配置
│   ├── config-demo.sh
│   └── config-demo-slo.sh
└── logs/               # 测试日志与结果输出目录（自动生成）
```

---

## 一、工具概述

本工具集用于对大语言模型（LLM）推理服务进行**自动化性能压测**，支持以下特性：

- **后端框架**：vLLM、SGLang
- **测试模式**：固定压测模式 / 阈值搜索模式（二分查找最大并发）
- **指标提取**：TTFT、TPOT、Token 吞吐量、P99 延迟等
- **输出格式**：结构化日志 + CSV 汇总
- **容器化**：基于 Docker 运行

---

## 二、快速开始

### 2.1 整体流程

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌─────────────┐
│ 1. 编写配置  │  →  │ 2. 启动服务   │  →  │ 3. 执行压测   │  →  │ 4. 解析日志  │
│ (tasks/*.sh) │     │ (run-serve.sh)│     │(run-binary.sh)│     │(parse_log.sh)│
└─────────────┘     └──────────────┘     └──────────────┘     └─────────────┘
```

### 2.2 一键运行全流程

```bash
cd /data/hehj/benchtest
bash run-total.sh
```

该脚本会自动遍历 `tasks/` 目录下的所有配置文件，依次执行：启动服务 → 等待就绪 → 执行压测 → 清理容器。

---

## 三、配置文件说明

### 3.1 配置文件位置

在 `tasks/` 目录下创建 `.sh` 配置文件，例如 `tasks/config-1.sh`。

### 3.2 必需参数

| 参数 | 说明 | 示例值 |
|------|------|--------|
| `MODEL_PATH` | 模型权重路径 | `/data/models/Qwen3.6-27B` |
| `MODEL_NAME` | 模型名称 | `Qwen3.6-27B` |
| `PORT` | 服务端口 | `8000` |
| `TP` | Tensor Parallel 并行度 | `2` |
| `BACKEND` | 推理后端 | `vllm` 或 `sglang` |
| `LOG_DIR` | 日志输出目录 | `./logs` |

### 3.3 可选参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `DATA_TYPE` | 数据类型 | `float16` |
| `CASE_PAIR` | 输入/输出长度组合 | `[[256,256]]` |
| `BATCH_SIZES` | 并发请求数列表 | `[1,4,8,16,32,64]` |
| `METRICS` | 需要提取的指标 | `Mean TTFT (ms),Mean TPOT (ms),Output token throughput (tok/s),Total token throughput (tok/s)` |
| `IMAGE` | Docker 镜像名 | `harbor.sourcefind.cn:5443/dcu/admin/base/vllm:0.18.1-ubuntu22.04-dtk26.04-py3.10-` |
| `CONTAINER_NAME` | 容器名称 | `he-bench-` |
| `WORKDIR` | 容器内工作目录 | `/data/hehj/benchtest-` |
| `CMD` | 自定义启动命令 | 见下方默认值 |

### 3.4 配置文件示例

```bash
# tasks/config-1.sh
MODEL_PATH=/data/models/Qwen3.6-27B
MODEL_NAME=Qwen3.6-27B
PORT=8000
TP=2
BACKEND=vllm
LOG_DIR=./logs

# 测试用例：输入长度 256/512，输出长度 256/1024
CASE_PAIR=[[256,256],[512,1024]]

# 并发数列表
BATCH_SIZES=[1,4,8,16,32,64]

# 需要提取的指标
METRICS="Mean TTFT (ms),Mean TPOT (ms),Output token throughput (tok/s),Total token throughput (tok/s),P99 TTFT (ms),P99 TPOT (ms)"
```

---

## 四、脚本详解

### 4.1 run-serve.sh — 启动推理服务

**功能**：在 Docker 容器中启动模型推理服务。

**用法**：
```bash
# 直接运行（需先 source 配置文件）
source tasks/config-1.sh
bash run-serve.sh
```

**关键行为**：
- 根据 `BACKEND` 自动拼接启动参数（vLLM 或 SGLang）
- 自动挂载模型路径、日志目录到容器
- 配置 DCU 设备映射（`/dev/kfd`, `/dev/dri`, `/dev/mkfd`）
- 服务日志输出到 `$WORKDIR/$LOG_DIR/serve.log`

**自定义启动命令**：
通过设置 `CMD` 变量覆盖默认启动命令：
```bash
CMD=$(cat <<'EOF'
export HIP_VISIBLE_DEVICES=0,1,2,3,4,5,6,7
export VLLM_HCU_USE_FLASH_ATTN=1
vllm serve Qwen/Qwen3.6-27B \
    -tp 2 \
    --trust-remote-code \
    --max-num-batched-tokens 10240 \
    --speculative-config.method mtp \
    --speculative-config.num_speculative_tokens 3
EOF
)
```

---

### 4.2 run-binary.sh — 执行性能压测

**功能**：对已启动的推理服务进行性能压测，提取关键指标。

**用法**：
```bash
# 方式1：在容器内执行（由 run-total.sh 自动调用）
docker exec <container_name> bash -c "cd /data/hehj/benchtest && source config.sh && bash run-binary.sh"

# 方式2：本地执行（需先启动服务）
source tasks/config-1.sh
bash run-binary.sh
```

**环境变量参数**：

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `MODEL_PATH` | 模型路径 | `/data1/models/Qwen3.5-27B` |
| `MODEL_NAME` | 模型名称 | `Qwen3.5-27B` |
| `PORT` | 服务端口 | `8000` |
| `TP` | Tensor Parallel | `2` |
| `BACKEND` | 推理后端 | `vllm` |
| `DATA_TYPE` | 数据类型 | `float16` |
| `CASE_PAIR` | 输入/输出长度组合 | `[[256,256]]` |
| `BATCH_SIZES` | 并发数列表 | `[1,4,8,16,32,64]` |
| `LOG_DIR` | 日志目录 | `./logs` |
| `METRICS` | 提取指标 | `Mean TTFT (ms),Mean TPOT (ms),Output token throughput (tok/s),Total token throughput (tok/s)` |

**测试模式**：

#### 模式1：固定压测（默认）

按 `CASE_PAIR` 和 `BATCH_SIZES` 的组合逐一执行测试。

```bash
# 示例：测试 2 种输入输出长度 × 6 种并发数 = 12 组测试
CASE_PAIR=[[256,256],[512,1024]]
BATCH_SIZES=[1,4,8,16,32,64]
```

#### 模式2：阈值搜索模式

通过设置 `SEARCH_METRICS` 和 `SEARCH_THRESHOLDS` 启用，自动二分查找满足性能阈值最大并发数。

```bash
# 当 "Mean TTFT (ms)" <= 500 且 "Total token throughput (tok/s)" >= 1000 时认为通过
SEARCH_METRICS="Mean TTFT (ms),Total token throughput (tok/s)"
SEARCH_THRESHOLDS="500,1000"
SEARCH_START_BATCH=1
SEARCH_MAX_BATCH=1024
```

**搜索算法**：
1. **指数增长阶段**：从 `SEARCH_START_BATCH` 开始，每次翻倍测试，直到不满足阈值
2. **二分搜索阶段**：在最后一个满足和不满足的并发数之间二分查找最大可行值

**输出**：
- 每个测试用例生成独立的 `.log` 日志文件
- 所有结果汇总到 `$LOG_DIR/${MODEL_NAME}_bench_YYYYMMDD_HHMMSS.csv`

---

### 4.3 run-total.sh — 全流程自动化编排

**功能**：遍历 `tasks/` 目录下的所有配置文件，依次执行完整测试流程。

**用法**：
```bash
bash run-total.sh
```

**执行流程**：
1. 读取 `tasks/` 目录下所有非隐藏文件
2. 对每个配置文件：
   - 加载配置参数
   - 启动 Docker 容器（`run-serve.sh`）
   - 等待服务端口就绪（最多 120 次 × 30 秒 = 1 小时超时）
   - 执行压测（`run-binary.sh`）
   - 清理容器
   - 等待 30 秒后继续下一个配置

**跳过容器重建**：
```bash
REBUILD_CONTAINER=false bash run-total.sh
```

---

### 4.4 parse_log.sh — 日志解析与汇总

**功能**：扫描 `logs/` 目录下的所有 `.log` 文件，提取指标并生成汇总 CSV。

**用法**：
```bash
bash parse_log.sh
```

**输出**：
- `$LOG_DIR/total_summary.csv` — 所有测试用例的指标汇总

**CSV 格式**：
```
Model Name,TP,Input Length,Output Length,Requests,Mean TTFT (ms),Mean TPOT (ms),Output token throughput (tok/s),Total token throughput (tok/s),P99 TTFT (ms),P99 TPOT (ms),Acceptance rate (%),Acceptance length
Qwen3.6-27B,2,256,256,1,120.5,45.2,850.3,820.1,250.8,52.1,98.5,16.2
Qwen3.6-27B,2,256,256,4,180.3,48.7,3200.5,3100.2,380.5,55.3,97.8,16.5
...
```

**文件名解析规则**：
日志文件名格式：`{MODEL_NAME}_in{input_len}_out{output_len}_req{batch_size}_{timestamp}.log`

示例：`Qwen3.6-27B_in512_out1024_req32_20260729_160000.log`

---

### 4.5 demo.sh — 快速演示

**功能**：展示基本的 API 调用和测试命令参考。

**用法**：
```bash
source config.sh
bash demo.sh
```

> 注意：`demo.sh` 包含 API 调用示例和第三方工具（evalscope）的精度/性能测试命令，可根据需要修改。

---

## 五、常用操作

### 5.1 单次测试

```bash
# 1. 创建配置文件
cat > tasks/config-demo.sh << 'EOF'
MODEL_PATH=/data/models/Qwen3.6-27B
MODEL_NAME=Qwen3.6-27B
PORT=8000
TP=2
BACKEND=vllm
LOG_DIR=./logs
CASE_PAIR=[[256,256]]
BATCH_SIZES=[1,4,8]
EOF

# 2. 运行全流程
bash run-total.sh
```

### 5.2 自定义指标

```bash
# 只关注 TTFT 和吞吐量
METRICS="Mean TTFT (ms),Total token throughput (tok/s)"
```

### 5.3 阈值搜索（找最大并发）

```bash
# 找到满足 TTFT <= 500ms 的最大并发数
SEARCH_METRICS="Mean TTFT (ms)"
SEARCH_THRESHOLDS="500"
SEARCH_START_BATCH=1
SEARCH_MAX_BATCH=512
```

### 5.4 查看结果

```bash
# 查看汇总 CSV
cat logs/total_summary.csv

# 查看单个测试日志
cat logs/Qwen3.6-27B_in256_out256_req32_20260729_160000.log
```

---

## 六、指标说明

| 指标 | 说明 | 单位 |
|------|------|------|
| **Mean TTFT** | 首 token 延迟均值 | ms |
| **Mean TPOT** | 后续 token 延迟均值 | ms |
| **Output token throughput** | 输出 token 吞吐量 | tok/s |
| **Total token throughput** | 总 token 吞吐量 | tok/s |
| **P99 TTFT** | 首 token 延迟 P99 | ms |
| **P99 TPOT** | 后续 token 延迟 P99 | ms |
| **Acceptance rate** | 接受率（投机解码） | % |
| **Acceptance length** | 平均接受长度 | - |

---

## 七、故障排查

### 7.1 端口等待超时

**现象**：`Port $port did not become ready in time.`

**解决**：
- 检查模型路径是否正确
- 检查 Docker 镜像是否已拉取
- 检查 DCU 驱动是否正常
- 查看 `logs/shell-serve.log` 获取详细错误

### 7.2 测试失败

**现象**：`Test failed for $conf_file`

**解决**：
- 检查 `logs/shell-test.log` 获取压测日志
- 确认服务端口可访问：`curl http://localhost:$PORT/v1/chat/completions`
- 检查 `BACKEND` 参数是否与 Docker 镜像匹配

### 7.3 指标提取为 NA

**现象**：CSV 中某些指标值为 `NA`

**解决**：
- 检查日志文件中是否存在对应的指标名称
- 修改 `METRICS` 变量，确保与日志输出格式一致

---

## 八、注意事项

1. **DCU 环境**：本工具集针对 DCU 加速卡优化，需要安装对应的驱动和 Docker 运行时
2. **资源占用**：压测期间会大量占用 GPU 显存和计算资源，请确保服务器资源充足
3. **容器清理**：如果测试异常中断，手动清理残留容器：`docker rm -f $(docker ps -aq --filter name=he-bench-)`
4. **日志轮转**：大量测试会产生较多日志文件，建议定期清理 `logs/` 目录
