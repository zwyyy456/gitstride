# GitStride · 迹程

[English](README.md) · 简体中文

GitStride 是一款原生 macOS GitHub Projects 客户端。在菜单栏快速查看项目，在看板或表格中整理工作，直接编辑 Issue。

[官网](https://gitstride.hyperseek.tech/zh-cn) · [下载](https://gitstride.hyperseek.tech/zh-cn/download) · [使用文档](https://gitstride.hyperseek.tech/zh-cn/docs) · [GitHub Releases](https://github.com/zwyyy456/GitStride/releases)

## 功能

- **菜单栏与工作区**：快速查看项目，或打开完整窗口使用看板、表格、路线图、搜索和筛选。
- **我的工作与本地视图**：跨项目查看事项，保存当前 Mac 上的筛选和显示偏好。
- **Issue 编辑**：创建 Issue，管理负责人、标签、里程碑、父子 Issue 和依赖关系。
- **项目提醒**：App 运行期间，按设置提醒状态、分配和截止日期变化。
- **可选 PR 自动化**：根据关联 PR 的进展更新匹配的个人 Projects；服务在 App 退出后仍可运行。

支持英文和简体中文。GitHub 项目名称、自定义状态及用户内容保留原文。

## 快速开始

需要 **macOS 14（Sonoma）或更新版本**及 GitHub.com 账号。桌面端支持个人和组织 Projects，暂不支持 GitHub Enterprise Server。

1. [下载 GitStride](https://gitstride.hyperseek.tech/zh-cn/download)，解压 ZIP，将 App 移入“应用程序”。
2. 打开 App，在 **设置 → GitHub → 账户** 中登录，按提示完成 GitHub 设备授权。
3. 选择个人账号或组织，打开已有的 Project。

GitHub Release 版也可以复用 `gh` 登录，配置方法见[快速开始指南](https://gitstride.hyperseek.tech/zh-cn/docs/getting-started)。PR 自动化独立授权，浏览和编辑项目无需开启。

桌面 OAuth 请求 `repo project read:org offline_access`；其中 `repo` 包含私有仓库及代码读写权限。OAuth 凭据保存在 macOS 钥匙串，本地项目缓存可能包含未经加密的私有内容。完整说明见[隐私与权限](https://gitstride.hyperseek.tech/zh-cn/privacy)。

## 文档与支持

- [工作区与视图](https://gitstride.hyperseek.tech/zh-cn/docs/workspace)：看板、表格、搜索、快速创建和我的工作。
- [PR 自动化](https://gitstride.hyperseek.tech/zh-cn/docs/automation)：授权、状态规则及暂停或删除连接。
- [自托管](https://gitstride.hyperseek.tech/zh-cn/docs/self-hosting)：连接自己的自动化服务；部署步骤见 [Worker 文档](Automation/README.md)。
- [问题排查](https://gitstride.hyperseek.tech/zh-cn/support) · [仓库内使用指南（英文）](docs/usage.md)：路线图、命令面板及详细工作流。

报告问题请前往 [GitHub Issues](https://github.com/zwyyy456/GitStride/issues)，附上 App 版本、macOS 版本和复现步骤，并移除令牌及私有内容。

## 从源码构建

当前开发工具链为 Xcode 26.5。macOS 14 是 App 支持的最低系统版本，不是 Xcode 的版本要求。

```bash
git clone https://github.com/zwyyy456/GitStride.git gitstride
cd gitstride
xcodebuild -project GitStride.xcodeproj -scheme GitStride \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

要从 Xcode 运行，打开 `GitStride.xcodeproj`，选择 GitStride target，在 **Signing & Capabilities** 中选择自己的开发团队。Sparkle 使用强化运行时的库验证，因此未签名的编译检查通过，不代表 App 能直接在本机启动。

`GITSTRIDE_OAUTH_CLIENT_ID` 是桌面 OAuth App 的公开 Client ID。如果你要发行自己的版本，请注册 OAuth App、启用 Device Flow，并在两个 App target 中设置对应的 Client ID。不要嵌入 Client Secret。`GitStrideAppStore` scheme 仅支持 OAuth 登录，不包含 Sparkle；该构建目标不代表应用已在 Mac App Store 上架。

更多信息见 [验证命令](docs-index.md#5-常用验证命令)、[工程架构](architecture.md) 和 [发布指南（英文）](docs/releasing.md)。Worker 开发另外需要 Node.js 22 或更新版本，参见 [Automation/README.md](Automation/README.md)。

## 项目来源与许可证

GitStride 起源于 [yogesharc/GitBoard](https://github.com/yogesharc/GitBoard)，现由 [zwyyy456](https://github.com/zwyyy456) 独立维护并进行了大量重构。项目保留原作者的版权声明，并列明当前维护者的版权声明。

本项目采用 [MIT 许可证](LICENSE)，App 安装包内也包含许可证。GitStride 与 GitHub, Inc. 无关联关系。

## iOS 开发版

`GitStrideAppStore` target 和 scheme 同时支持原生 macOS 与 iOS / iPadOS 17+，在 Xcode 中选择对应的运行设备即可。功能范围与构建方式见 [iOS 开发与使用](docs/ios.md)。此开发目标不代表已在 App Store 上架。
