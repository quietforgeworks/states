# States

**看一眼菜单栏，就知道 Mac 正在忙什么。**

CPU 在忙、内存吃紧，还是电池快见底？States 把日常关心的系统指标放在一起，让你不用反复打开多个窗口，就能了解 Mac 的运行状态。

## 一处查看，心里有数

- 查看 CPU、内存、磁盘与网络流量。
- 了解电池、电源和当前设备可提供的温度读数。
- 按需导出系统与 SMC 指标 JSON，方便进一步检查。

传感器的可用性因机型而异，缺失或估算读数不代表实测零值。

## 下载与安装

**macOS 26 及以上，仅支持 Apple Silicon（arm64）。**

前往 [Releases](https://github.com/quietforgeworks/states/releases) 下载 `States-1.0.3-macOS-arm64.zip`，解压后将 `States.app` 放入“应用程序”。应用不包含在仓库的源码目录中。发布页同时提供完整源码 ZIP 和 SHA-256 校验文件。

当前应用为 ad-hoc 本地签名，未使用 Apple Developer ID 签名，未通过 Apple 公证，macOS 可能阻止首次打开。请核验来源和 SHA-256，不要全局关闭系统安全保护。尚未完成独立的全新 Mac 安装、升级和权限回归测试。

## 数据与隐私

系统指标来自本机接口；本次源码静态检查未发现网络上传或遥测请求实现。导出的 JSON 可能包含你不想公开的设备信息，分享前请检查。

完整的安装、指标限制、数据行为与构建要求见 [Source/README.md](Source/README.md)。

## 开源与构建

源码、构建脚本和完整说明位于 `Source/`。在符合要求的 Mac 上，可进入该目录后运行 `bash Build.command`。

本项目采用 [MIT 许可证](LICENSE)。依赖与来源说明见 [Source/THIRD-PARTY.md](Source/THIRD-PARTY.md)。
