## 错误报告：vllm-deepseek-v3-1-bf16-efe9f2 Pod CrashLoopBackOff

**简要结论**：`run.sh` 中硬编码了 `cann-9.0.1` 路径，但今日（2026-08-04）新构建的 CI 镜像已将 CANN 升级至 9.1.0，导致路径不存在，Pod 启动即崩溃。

---

### 一、现象

```
vllm-project   vllm-deepseek-v3-1-bf16-efe9f2-0     0/1   CrashLoopBackOff   4 (17s ago)   4m14s
vllm-project   vllm-deepseek-v3-1-bf16-efe9f2-0-1   0/1   CrashLoopBackOff   4 (25s ago)   4m14s
```

Leader 和 Worker pod 均处于 CrashLoopBackOff 状态，退出码为 1。

---

### 二、直接报错

```
/root/.cache/tests/run.sh: line 27: /usr/local/Ascend/cann-9.0.1/share/info/ascendnpu-ir/bin/set_env.sh: No such file or directory
```

---

### 三、根因分析

#### 3.1 镜像已升级至 CANN 9.1.0

Pod 使用的镜像为：
```
swr.cn-southwest-2.myhuaweicloud.com/base_image/ascend-ci/vllm-ascend:nightly-ci-main-a3
```

检查镜像元数据：
```
Created:      2026-08-04T16:52:08Z   ← 当天刚构建
CANN_VERSION: 9.1.0
ASCEND_TOOLKIT_HOME: /usr/local/Ascend/cann-9.1.0
```

镜像于本次 CI run 触发前约1小时完成构建，CANN 版本从 9.0.1 升级至 9.1.0。

#### 3.2 run.sh 仍硬编码 cann-9.0.1

CI workflow `_e2e_nightly_multi_node.yaml` 的 **Prepare scripts** 步骤将代码仓库中的脚本复制到共享 PVC：

```yaml
- name: Prepare scripts
  run: |
    install -D tests/e2e/nightly/multi_node/scripts/run.sh /root/.cache/tests/run.sh
```

LWS 模板 `lws.yaml.jinja2` 中，Leader 和 Worker 容器的启动命令均为：

```yaml
command:
  - sh
  - -c
  - |
    bash /root/.cache/tests/run.sh
```

而 commit `b80d4e621a303d1a4077db5e4d80586d2446fb8f` 中的 `run.sh` 第27行：

```bash
# line 26
source /usr/local/Ascend/ascend-toolkit/set_env.sh
# line 27 ← 问题所在
source /usr/local/Ascend/cann-9.0.1/share/info/ascendnpu-ir/bin/set_env.sh
```

`cann-9.0.1` 为硬编码版本号，镜像升级后该路径不再存在，`set -euo pipefail` 使脚本在此处立即以非零码退出。

#### 3.3 完整调用链

```
GitHub Actions workflow 触发
  └── Build nightly-a3 image        # 构建新镜像，CANN 9.0.1 → 9.1.0
  └── multi-node / DeepSeek-V3.1-BF16.yaml
        ├── Prepare scripts
        │     └── install run.sh (含硬编码 cann-9.0.1) → PVC /root/.cache/tests/run.sh
        ├── Launch cluster
        │     └── kubectl apply lws.yaml (image=nightly-ci-main-a3, CANN 9.1.0)
        └── Pod 启动
              └── bash /root/.cache/tests/run.sh
                    └── line 27: source .../cann-9.0.1/...  ← 路径不存在 → exit 1
                          └── CrashLoopBackOff
```

---

### 四、影响范围

- 本次 run 中所有使用 `nightly-ci-main-a3` 镜像的多机测试用例均受影响（DeepSeek-V3.1-BF16、DeepSeek-V3.2-W8A8-EP、GLM5.2-W8A8-A3 等）
- 单节点测试若使用同一镜像且执行相同 `run.sh` 逻辑，同样会失败

---

### 五、修复建议

**根本修复**：去掉 `run.sh` 中的硬编码版本号，改用环境变量：

```bash
# 修改前
source /usr/local/Ascend/cann-9.0.1/share/info/ascendnpu-ir/bin/set_env.sh

# 修改后（推荐）
source /usr/local/Ascend/${CANN_VERSION}/share/info/ascendnpu-ir/bin/set_env.sh
```

镜像中已通过 ENV 注入 `CANN_VERSION=9.1.0`，使用该变量可使脚本自动适配后续版本升级。

**临时修复**：若急需恢复 CI，可将第27行版本号直接改为 `cann-9.1.0`，但不推荐作为长期方案。

**附加建议**：镜像构建完成后，在发布前增加一个冒烟测试步骤，验证 `run.sh` 中所有 `source` 路径在新镜像内均可访问，避免镜像版本与脚本路径再次脱节。
