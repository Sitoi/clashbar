## v0.1.5

### 🐞 修复问题

- 修复 macOS 13 Intel 平台下的兼容性问题，提升应用在旧版 Intel 设备上的启动与界面稳定性

<details>
<summary><strong> ✨ 新增功能 </strong></summary>

- 新增无内核版本的 ClashBar 安装包，支持按需分发不内置 Mihomo 内核的应用版本
- 支持在未内置核心组件时提供首次启动引导，方便用户手动安装和配置 Mihomo 内核

</details>

<details>
<summary><strong> 🚀 优化改进 </strong></summary>

- 优化未内置内核场景下的启动流程，缺少托管内核时将延后自动启动并提供更清晰的提示信息
- 调整启动失败与 TUN 相关错误提示文案，帮助用户更快定位和处理手动安装内核后的运行问题
- 优化打包与发布流程，适配新的安装包结构并同步更新相关资源与文档

</details>
