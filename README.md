<div align="center">

<img src="Sources/ClashBar/Resources/Brand/clashbar-icon.png" width="300" alt="ClashBar Logo" />

# ClashBar

原生 macOS 菜单栏代理客户端（SwiftUI + AppKit），以 `mihomo` 为 Core。

<p>
  <img alt="Platform" src="https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square&logo=apple" />
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.2-F05138?style=flat-square&logo=swift" />
  <img alt="Build" src="https://img.shields.io/badge/Build-SwiftPM-0A84FF?style=flat-square" />
  <img alt="i18n" src="https://img.shields.io/badge/i18n-zh--Hans%20%7C%20en-34C759?style=flat-square" />
  <a href="https://t.me/clashbars" target="_blank" rel="noopener noreferrer">
    <img alt="Telegram" src="https://img.shields.io/badge/Telegram-@clashbars-26A5E4?style=flat-square&logo=telegram&logoColor=white" />
  </a>
</p>

</div>

![ClashBar](./imgs/clashbar.png)

---

## 👋 ClashBar 是什么

ClashBar 是一个原生 macOS 菜单栏代理客户端，基于 `mihomo` Core，专注「轻量、稳定、可观测」的日常代理管理体验。  
你可以在菜单栏里完成配置切换、节点选择、规则刷新、连接排查和系统代理控制，不需要打开复杂主窗口。 ✨

---

## ✨ 功能总览

| 模块         | 核心能力                                   | 你能做什么                     |
| ------------ | ------------------------------------------ | ------------------------------ |
| 🟢 Core 控制 | 启动 / 停止 / 重启                         | 快速恢复代理状态，减少断网等待 |
| 🧩 配置管理  | 本地导入、远程导入、批量更新、重载配置     | 在多个订阅和配置文件间切换     |
| 🚦 模式切换  | `Rule` / `Global` / `Direct`               | 按场景切换流量策略             |
| 🌍 节点运维  | Proxy Group 切换、延迟测试、Provider 更新  | 选择更快更稳的线路             |
| 📊 可观测性  | 实时速率、连接数、内存、活动连接、日志过滤 | 快速定位“慢/断/不通”的原因     |
| 🔐 系统集成  | 系统代理开关、开机启动                     | 与 macOS 深度集成，更安全省心  |
| 🌐 多语言    | 简体中文 / English                         | 团队或个人都能无障碍使用       |

---

## 🚀 快速上手（用户版）

1. 打开 ClashBar，点击菜单栏图标进入主面板。 🖱️
2. 在 `Proxy` 页面选择现有配置，或导入本地 / 远程配置。 📥
3. 点击 `Start` 启动 Core，必要时使用 `Restart`。 ▶️
4. 选择代理模式：`Rule` / `Global` / `Direct`。 🎛️
5. 进入 Proxy Group 切换节点并做一次延迟测试。 📶
6. 确认可用后开启系统代理，开始正常使用。 ✅

---

## 🗺️ 功能地图

- 🧭 **Proxy**：实时速率、连接数、内存、配置入口、系统代理开关
- 📚 **Rules**：规则统计、规则刷新、Provider 更新
- 🌐 **Activity**：连接过滤、关闭单连接、关闭全部连接
- 🪵 **Logs**：日志级别过滤、关键词搜索、日志复制
- ⚙️ **System**：语言、状态栏样式、allow-lan/ipv6/log-level、端口设置

---

## 🎯 典型使用场景

- 🏠 日常办公：按网络环境快速切换配置和节点，保持稳定在线。
- 🧪 问题排查：结合 `Activity + Logs` 定位连接异常、规则命中异常。
- 🔁 订阅维护：批量更新远程配置源后，一键重载并验证延迟。
- 🛡️ 安全优先：敏感信息放 Keychain，日志输出自动脱敏。

---

## 📁 数据目录

- `~/Library/Application Support/clashbar/config`
- `~/Library/Application Support/clashbar/logs`
- `~/Library/Application Support/clashbar/state`

配置扫描规则：

- 仅识别 `.yaml` / `.yml`
- 按文件名排序
- 未选中配置时默认选中第一个

---

## ❓ 常见问题

- 为什么开启系统代理失败？  
  请在 macOS 系统设置中批准 ClashBar 所需权限后重试。

- 为什么切换节点后网络没有变化？  
  建议先做延迟测试，再确认当前模式是否为 `Rule` / `Global`，必要时 `Restart` Core。

- 为什么远程配置更新后看不到变化？  
  先执行远程更新，再使用 `重载配置` 刷新列表并重新选择目标配置。

- 为什么有些请求没有按预期走代理？  
  到 `Rules` 查看规则命中情况，并结合 `Activity` 与 `Logs` 交叉排查。

---

## 🙌 反馈与支持

欢迎通过 Issue / PR 提交反馈（功能建议、文档修正、稳定性问题都欢迎）。 💬

## 🙏 致谢

特别感谢 [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) 项目，为 ClashBar 提供稳定强大的 Core 能力。

## ✨ Star 数

[![Star History Chart](https://api.star-history.com/svg?repos=Sitoi/ClashBar&type=date&legend=top-left)](https://www.star-history.com/#Sitoi/ClashBar&type=date&legend=top-left)
