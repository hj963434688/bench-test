# LLM 推理性能自动化测试工具

## 使用方法一：测试所有配置
配置文件：config/config-base.sh config/config-demo-slo.sh ...或添加额外配置文件
一键启动：bash run-total.sh 
## 使用方法二: 测试单个配置 
source config/setup_env.sh config/config-base.sh 
bash run-serve.sh
等待服务启动完成
bash run-binary.sh