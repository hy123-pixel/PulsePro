# PulsePro

`PulsePro` 是一个基于 macOS 的日志与网络请求查看工具，用来配合 `Pulse` / `PulseCN` 进行本地日志查看、远程日志接收和网络请求分析。

> ⚠️ 当前仓库**仅供个人学习与功能研究用途**，主要用于本地开发、界面实验和远程日志调试验证。
>
> - **当前阶段以学习、实验和功能验证为主**

## 当前仓库结构

本仓库以 **Xcode 工程** 作为主入口：

- `App/`：应用入口、远程服务、store 控制器
- `Views/`：实时日志、网络检查、设置等界面
- `Resources/`：图标、entitlements 等资源
- `PulsePro.xcodeproj/`：主工程文件

## 运行方式

请直接打开：

```text
PulsePro.xcodeproj
```

运行 scheme：

```text
PulsePro
```

## 依赖说明

当前工程依赖 `PulseCN` 远程仓库的 `main` 分支：

```text
https://github.com/hy123-pixel/PulseCN (branch: main)
```

## 功能概览

- 实时日志查看
- 网络请求检查
- 远程连接 iPhone / iPad 发送的日志
- 请求详情分析（Info / Request / Response / Query / Headers / Cookies / Timing / cURL）

## 开发说明

- `PulsePro` 依赖 `PulseCN` 的 **main** 线路
- `PulseCN` 为官方仓库的fork版本，本地仅针对官方增加了汉化版本
- `.gitignore` 已忽略构建缓存、SwiftPM 缓存、Xcode 用户数据等无用文件

## 当前目标

当前仓库主要聚焦于：

- 远程日志接收与展示
- 网络请求检查与分析页增强
- macOS 端调试体验优化
- 与 `PulseCN` 主线配套联调

## 许可证

本仓库当前采用 MIT License。详见 [LICENSE.md](./LICENSE.md)。
