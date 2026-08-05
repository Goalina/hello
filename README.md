# Nightly 测试近期故障说明

近期 Nightly 测试连续出现三次故障，以下逐一说明原因及分类。

---

## 故障一：7月30日 — 代码问题 + 测试框架缺陷

**问题类型**：业务代码问题 + 测试框架问题

**现象**：夜间 Nightly 用例触发时资源不足，任务超时报错。

**影响范围**：
- multi-node (releases-v0.24.0rc, multi-node-deepseek-v3.1, DeepSeek-V3.1-BF16.yaml, 2) / DeepSeek-V3.1-BF16.yaml
- double-node (releases-v0.24.0rc, multi-node-deepseek-r1-w8a8-longseq, DeepSeek-R1-W8A8-longseq.yaml) / DeepSeek-R1-W8A8-longseq.yaml
- double-node (releases-v0.24.0rc, multi-node-qwen-disagg-pd, Qwen3-235B-disagg-pd.yaml, 2) / Qwen3-235B-disagg-pd.yaml

共 3 个多机任务失败。

**原因**：
- main 分支合入了存在问题的代码，导致 e2e 测试任务长时间挂死无法退出；
- 测试框架未对 e2e 测试设置超时时间，挂死的任务持续占用测试资源，无法自动释放；
- 夜间 Nightly 触发时，资源已被耗尽，新任务无法获取足够资源，最终超时报错。

**现状**：
1. 已为 e2e 测试添加超时时间限制（120min）；
2. 问题代码修复中。

---

## 故障二：8月4日 — 基础设施问题

**问题类型**：基础设施问题

**现象**：部分任务报错 `line 1: npu-smi: command not found`。

**影响范围**：
- single-node (releases-v0.23.0, qwen3-vl-235b-a22b-instruct-w8a8, linux-aarch64-nightly-a3-16) / qwen3-vl-235b-a22b-instruct-w8a8
- single-node (releases-v0.23.0, deepseek-r1-0528-w8a8, linux-aarch64-nightly-a3-16) / deepseek-r1-0528-w8a8

共 2 个单机任务失败。

**原因**：
- 节点 `172.22.5.24` 发生掉卡故障，经修复重启后，NPU 驱动挂载出现异常；
- 驱动异常导致 `npu-smi info` 命令无法正常执行，测试任务报错退出。

**现状**：8/4 当日已修复。

---

## 故障三：8月5日 — 镜像版本升级与脚本未同步

**问题类型**：CI代码问题

**现象**：多机测试所有 Pod 启动即崩溃（CrashLoopBackOff）。

**影响范围**：
- multi-node (main, multi-node-deepseek-v3.1, DeepSeek-V3.1-BF16.yaml, 2) / DeepSeek-V3.1-BF16.yaml
- multi-node (main, multi-node-deepseek-v3.2-W8A8-EP, DeepSeek-V3_2-W8A8-EP.yaml, 4) / DeepSeek-V3_2-W8A8-EP.yaml
- multi-node (main, multi-node-GLM-5.2-w8a8-A3, GLM5_2-W8A8-A3-dual-nodes.yaml, 2) / GLM5_2-W8A8-A3-dual-nodes.yaml
- double-node (main, multi-node-dpsk3.2-2node, DeepSeek-V3_2-W8A8-A3-dual-nodes.yaml, 2) / DeepSeek-V3_2-W8A8-A3-dual-nodes.yaml
- double-node (main, multi-node-qwen3-dp, Qwen3-235B-A22B.yaml, 2) / Qwen3-235B-A22B.yaml
- double-node (main, multi-node-GLM-5.1-w8a8-A3, GLM5_1-W8A8-A3-dual-nodes.yaml, 2) / GLM5_1-W8A8-A3-dual-nodes.yaml
- double-node (main, multi-node-qwen-disagg-pd, Qwen3-235B-disagg-pd.yaml, 2) / Qwen3-235B-disagg-pd.yaml
- double-node (main, multi-node-qwen-vl-disagg-pd, Qwen3-VL-235B-disagg-pd.yaml, 2) / Qwen3-VL-235B-disagg-pd.yaml
- double-node (main, multi-node-qwenw8a8-2node-eplb, Qwen3-235B-W8A8-EPLB.yaml, 2) / Qwen3-235B-W8A8-EPLB.yaml

共 9 个多机任务全部失败。

**原因**：
- PR #13480 将镜像构建依赖的 CANN 底包版本从 9.0.1 升级至 9.1.0；
- 多机测试的启动脚本 `run.sh`（`tests/e2e/nightly/multi_node/scripts/run.sh`）第 27 行将 CANN 版本号硬编码在路径中，未随镜像同步更新：
  ```bash
  source /usr/local/Ascend/cann-9.0.1/share/info/ascendnpu-ir/bin/set_env.sh
  ```
- 新镜像中只有 `cann-9.1.0` 目录，`cann-9.0.1` 完全不存在，脚本执行到该行时报错退出，触发 CrashLoopBackOff。

**现状**：测试框架代码待修正。
---
