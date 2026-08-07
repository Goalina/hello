# Nightly-A3 #15217 失败分析

## 现象

- Workflow: Nightly-A3 #15217
- 触发时间: 2026-08-06 17:03 UTC
- 首个 Job `parse-trigger` 失败，后续所有 Job 被 skip

## 错误信息

```
Getting action download info
Failed to resolve action download info. Error: Service Unavailable
Retrying in 19.695 seconds
Failed to resolve action download info. Error: Service Unavailable
Retrying in 26.041 seconds
Error: Service Unavailable
Error: Failed to resolve action download info.   
```
调用github action api时报错

## 根因

GitHub Actions 服务在 2026年8月6日17:02 UTC 开始发生故障，导致 runner 无法从 GitHub API 下载 action 元信息（如 `actions/github-script@v9`）。

github官方原故障通报可见 https://www.githubstatus.com/

## 时间线

| 时间 (UTC) | 事件 |
|---|---|
| 08-06 15:22 | GitHub 开始调查 Actions 降级 |
| 08-06 17:02 | GitHub 确认 Actions 和 Pages 服务降级 |
| 08-06 17:05 | Runner 开始执行 `parse-trigger`，尝试下载 action |
| 08-06 17:08 | Runner 重试两次后失败，报 Service Unavailable |
| 08-06 17:08 | `parse-trigger` 失败，后续 Job 全部 skip |
| 08-06 23:13 | GitHub 部署修复，成功率恢复至 99% |
| 08-07 00:01 | GitHub 宣布自托管 runner 问题已全面修复 |

## 影响

- `parse-trigger` 失败后，所有依赖它的 Job（`setup-vars`、`build-image`、`multi-node-tests`、`double-node-tests`、`single-node-tests` 等）被 skip
- 整个 Nightly 流水线未执行

## 结论

本次失败由 GitHub Actions 服务故障引起，非集群 ARC Runner 或代码问题。修复后重新运行即可恢复。
