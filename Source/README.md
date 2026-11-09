# States 1.0.6（build 7）

面向 macOS 的本地菜单栏系统监控工具，显示 CPU、内存、磁盘、网络流量、电池/电源和可用温度读数。

## 系统要求与分发状态

- **macOS 26 及以上，仅支持 Apple Silicon（arm64）Mac。**
- 当前下载包使用 ad-hoc 本地签名，**未使用 Apple Developer ID 签名，未通过 Apple 公证**。macOS 可能阻止首次打开；请先核验下载来源和 SHA-256。不要关闭系统安全保护或全局禁用 Gatekeeper。
- 这是直接下载分发的应用，不是 Mac App Store 安装包。Intel Mac 和较旧 macOS 不受此版本支持。
- 验证范围：尚未完成独立的全新 Mac 安装、升级和权限回归测试。

## 安装与使用

解压发布 ZIP，将 States.app 放入“应用程序”后打开，使用菜单栏图标查看状态和设置。默认采样间隔为 2 秒，可在设置中选择 1、2 或 5 秒，并暂停采样。登录时启动由用户在设置中选择。

## 指标与隐私

- 指标由本机系统接口获取。网络读数来自接口累计流量计数，不表示抓取或检查网络包内容。
- Codex 用量功能默认随应用启动：读取本机 CODEX_HOME（默认 ~/.codex）中 sessions / archived_sessions 的 Token 统计；不会将日志作为源码打包。额度通过已安装 Codex CLI 的 app-server 账户接口查询，CLI 可能联网；缺失 CLI 或登录信息时显示未知。今日统计按 Asia/Shanghai 日界线计算，并不代表跨设备账单。暂停监控会同时停止该功能。
- 项目未提供单独的遥测上传实现。
- 设置保存在本机偏好设置。通过“导出当前状态”会在用户选择的位置写出系统和 SMC 指标 JSON；分享前请检查内容。
- AppleSMC 温度与电源传感器的可用性因机型和系统而异。缺失读数或估算值不应解释为实测零值。应用不用于医疗、安全或精密计量用途。

## 升级与卸载

先退出旧版本，再替换应用。新版可能继续使用原偏好设置。移除 States.app 不会删除用户另行导出的 JSON 或所有系统偏好记录；卸载前可按需要关闭登录时启动。

## 源码、构建与测试

需要支持 macOS 26 SDK 的 Xcode/命令行工具和 Swift 6 工具链。在本源码目录运行：

```sh
./Build.command
swift test
```

构建脚本产出 ad-hoc 签名的应用。依赖 Apple 系统框架和项目内的 CSMC 接口代码，无外部 Swift 包依赖。2026-11-09 已在本地 Mac 隔离检出中通过 swift test（16 项）、release 构建及 States --self-test。尚未独立验证全新安装、CLI 账户查询与多机型传感器兼容性。

## 许可与来源

项目按 MIT 许可证发布，见 [LICENSE](LICENSE)。Apple 系统框架及第三方材料保留各自权利。

CSMC 源文件保留了对 exelban/stats 的 AppleSMC 协议研究引用，并声明为原创实现；这是现有源码说明，不代表已完成独立的代码来源或著作权审计。来源见 [THIRD-PARTY.md](THIRD-PARTY.md)。
