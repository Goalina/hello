# 错误报告：vllm-deepseek-v3-1-bf16-efe9f2 Pod CrashLoopBackOff

**简要结论**：CI 今天构建了一个新版本的镜像，镜像内 CANN 从 9.0.1 升级到了 9.1.0，但测试启动脚本里某个路径还写着旧版本号 `cann-9.0.1`，Pod 一启动就找不到这个路径，直接崩溃退出。

---

## 一、现象

```
vllm-project   vllm-deepseek-v3-1-bf16-efe9f2-0     0/1   CrashLoopBackOff   4 (17s ago)   4m14s
vllm-project   vllm-deepseek-v3-1-bf16-efe9f2-0-1   0/1   CrashLoopBackOff   4 (25s ago)   4m14s
```

多机测试的 Leader 和 Worker 两个 Pod 均处于 CrashLoopBackOff 状态（即反复启动、崩溃、重启的死循环），退出码为 1。

---

## 二、报错信息

从 Pod 日志中拿到的唯一一行报错：

```
/root/.cache/tests/run.sh: line 27: /usr/local/Ascend/cann-9.0.1/share/info/ascendnpu-ir/bin/set_env.sh: No such file or directory
```

意思是：启动脚本 `run.sh` 执行到第 27 行时，试图加载一个文件，但这个文件不存在。

---

## 三、根因分析

### 背景：多机测试的运行方式

多机测试用 Kubernetes 拉起多个 Pod，每个 Pod 启动时执行同一个 shell 脚本 `run.sh`，这个脚本负责配置环境变量、克隆代码、拉起 vLLM 服务、执行测试。

`run.sh` 并不是打包在镜像里的，而是由 CI workflow 在每次测试前从代码仓库复制到一块共享存储（PVC）上，Pod 启动时从共享存储里读取并执行。

整个流程如下：

```
CI workflow 启动
  │
  ├─ [第1步] 构建新镜像，推送到镜像仓库
  │
  ├─ [第2步] 从代码仓库把 run.sh 复制到共享存储
  │           install -D tests/.../run.sh → /root/.cache/tests/run.sh
  │
  ├─ [第3步] 用新镜像拉起多个 Pod（LeaderWorkerSet）
  │           Pod 启动命令：bash /root/.cache/tests/run.sh
  │
  └─ [第4步] Pod 执行 run.sh，配置环境、跑测试
```

### 问题所在：run.sh 里有一个写死的旧版本路径

`run.sh` 第 26～27 行负责加载 CANN 和 ascendnpu-ir 的环境变量：

```bash
# 第26行：加载 CANN 环境变量（这行没问题）
source /usr/local/Ascend/ascend-toolkit/set_env.sh

# 第27行：加载 ascendnpu-ir 环境变量（这行有问题）
source /usr/local/Ascend/cann-9.0.1/share/info/ascendnpu-ir/bin/set_env.sh
```

第 27 行把 CANN 的版本号 `9.0.1` **写死**在了路径里。

### 问题触发：今天构建的新镜像里只有 cann-9.1.0

今天（2026-08-04 16:52 UTC）CI 构建了新的测试镜像，CANN 从 9.0.1 升级到了 9.1.0：

```
镜像：swr.cn-southwest-2.myhuaweicloud.com/base_image/ascend-ci/vllm-ascend:nightly-ci-main-a3
构建时间：2026-08-04T16:52:08Z
CANN_VERSION=9.1.0
ASCEND_TOOLKIT_HOME=/usr/local/Ascend/cann-9.1.0   ← 已经是 9.1.0
```

在本地实际检查镜像内容，确认：
- `/usr/local/Ascend/cann-9.1.0/` ✅ 存在
- `/usr/local/Ascend/cann-9.0.1/` ❌ 不存在（整个目录都没有）

`run.sh` 脚本开头有 `set -euo pipefail`，这意味着任何命令失败都会立即终止脚本。第 27 行执行失败后脚本直接退出，Pod 随之终止，Kubernetes 不断重启，形成 CrashLoopBackOff。

### 完整崩溃链路

```
镜像升级：CANN 9.0.1 → 9.1.0（今天新构建）
          ↓
Pod 启动，执行 bash /root/.cache/tests/run.sh
          ↓
run.sh 第27行：source .../cann-9.0.1/...
          ↓
cann-9.0.1 目录不存在 → 命令失败
          ↓
set -euo pipefail → 脚本立即退出，exit code 1
          ↓
Pod 退出 → Kubernetes 重启 → 再次崩溃 → CrashLoopBackOff
```

---

## 四、影响范围

本次 CI run 中所有使用 `nightly-ci-main-a3` 镜像的多机测试均受影响：
- multi-node-deepseek-v3.1（DeepSeek-V3.1-BF16.yaml）
- multi-node-deepseek-v3.2-W8A8-EP（DeepSeek-V3_2-W8A8-EP.yaml）
- multi-node-GLM-5.2-w8a8-A3（GLM5_2-W8A8-A3-dual-nodes.yaml）

---

## 五、修复建议

**根本修复**：修改 `tests/e2e/nightly/multi_node/scripts/run.sh` 第 27 行，去掉硬编码的版本号，改用镜像中已有的环境变量 `CANN_VERSION`：

```bash
# 修改前
source /usr/local/Ascend/cann-9.0.1/share/info/ascendnpu-ir/bin/set_env.sh

# 修改后
source /usr/local/Ascend/${CANN_VERSION}/share/info/ascendnpu-ir/bin/set_env.sh
```

镜像里已通过 `ENV CANN_VERSION=9.1.0` 注入了版本号，使用该变量后，后续镜像升级 CANN 版本时脚本无需再做任何修改。

**临时修复**：若需要立即恢复 CI，可将第 27 行的 `cann-9.0.1` 直接改为 `cann-9.1.0`，但这只是推后了下一次同样问题出现的时间。

**附加建议**：在镜像构建 workflow 完成后、触发测试之前，增加一个验证步骤，检查 `run.sh` 中所有 `source` 的路径在新镜像内均存在，从流程上杜绝此类镜像与脚本版本脱节的问题。
