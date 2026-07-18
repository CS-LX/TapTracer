# 项目运行日志与 Git 认证约束

本文记录 TapTap Preview 黑盒验收和 GitHub 推送时必须遵守的路径与安全约束。

## 1. TapTap Preview 日志

TapTap Preview 的 Web 运行日志必须优先从以下文件读取：

```text
/opt/log/dev/Web(Win32)_p_6lvc_1.0.0_user_script.log
```

同一 user script 日志的辅助入口和索引为：

```text
/opt/log/dev/user_script.log
/opt/log/runtime_index/current.jsonl
```

定位日志时优先使用以下条件：

- 文件名：`Web(Win32)_p_6lvc_1.0.0_user_script.log`；
- `topic=user_script`；
- `projectId=p_6lvc`；
- 完整渲染必须同时出现 `[RayTracer][H5]` 两行和 `[RayTracer] render complete`；
- 不能只依据 `[RayTracer] started` 判断渲染完成。

以下目录只作为本地 UrhoXRuntime/validate 运行记录，不是 TapTap Preview 完整渲染统计的首选来源：

```text
/home/Maker/logs/lua/
```

若 Preview 平台、项目 ID 或日志文件名发生变化，应先重新确认日志入口，再更新本约束。

## 2. GitHub 认证信息

GitHub 推送所需 token 位于项目的 secret 文件夹：

```text
/workspace/secret/github_token
```

相关 askpass 入口为：

```text
/workspace/secret/git-askpass.sh
```

安全要求：

- 只记录位置，不读取、打印、复制或写入 token 内容；
- 推送时可通过 `secret/git-askpass.sh` 或等价的非交互认证方式使用 token；
- 严禁将 `secret/` 下任何文件加入 Git 暂存区或提交；
- 提交前必须检查 `git status` 和 `git diff --cached`，确认没有 secret 内容；
- 不得把 token 写入 remote URL、提交信息、日志、文档示例或命令输出。
