# GitStride iOS 开发与使用

GitStrideiOS 是 iPhone / iPad 原生客户端，最低支持 iOS / iPadOS 17。它与 macOS 版本共用项目数据、GitHub 操作和自动化服务源码，使用独立移动端页面。

## 构建

在 `GitStride.xcodeproj` 中选择 `GitStrideiOS` scheme。

```bash
xcodebuild -project GitStride.xcodeproj -scheme GitStrideiOS \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

模拟器编译使用 `-destination 'generic/platform=iOS Simulator'`。真机运行需要在 Signing & Capabilities 中选择自己的开发团队，并确认 Bundle ID 的签名配置。

`GITSTRIDE_OAUTH_CLIENT_ID` 使用现有公开 OAuth App ID；自行分发时配置自己的 Client ID 并启用 Device Flow。自动化地址使用 `GITSTRIDE_AUTOMATION_BASE_URL`。客户端不需要 Client Secret，不包含 CLI 或 Sparkle。

## 使用入口

- **我的工作**：显示关注项目中的工作，支持筛选、搜索和批量状态修改、归档。
- **项目**：选择个人账号或组织、创建项目、关注项目，进入项目工作区。
- **设置**：OAuth 登录与退出、自动化配置和连接管理、版本与许可证。

项目默认使用列表。更多操作菜单可以切换看板、保存视图、调整显示字段与看板列、刷新和管理项目。搜索和筛选在布局之间保留。保存视图、字段显示和关注偏好保存在本机，不同步到其他设备，也不修改 GitHub 的保存视图。

点击条目查看正文，通过属性按钮编辑状态、日期、迭代、指派人、标签、里程碑和关系。更多操作提供正文编辑、刷新、在 GitHub 打开及归档。新建入口支持 Issue、草稿和添加已有条目；提交后的进度与失败重试显示在待同步更改中。

按里程碑或父议题筛选时显示交付统计。统计覆盖当前项目该交付范围内的 Issue，不受其他筛选或隐藏看板列影响。

## 自动化与刷新

自动化继续由现有 Worker 执行。客户端前台接收 WebSocket 事件并刷新；进入后台停止事件连接，回到前台重连并刷新。设置中的授权、恢复已有连接、暂停、恢复及删除操作复用现有服务。

本版不提供项目系统提醒，不请求通知权限，也不启动 My Work 轮询监控。

## 当前范围

已接入列表、看板和详情编辑；完整多列表格与 Roadmap 时间轴尚未迁移，日期与迭代仍可在详情中编辑。缓存用于启动展示和只读回退；待同步操作沿用现有内存状态，不提供离线写入或跨应用重启恢复。

## 运行与发布确认

编译不替代真实账号和设备验证。使用专用 GitHub 测试项目确认登录、浏览、创建编辑、批量操作与自动化；界面调整依据运行截图确认。普通开发不运行 UI 测试。

TestFlight 分发还需要开发者签名、App Store Connect 中的 iOS 平台配置、相应的隐私与商店资料，以及在 Xcode Organizer 中验证 Archive。源码中的构建配置不代表已完成上传或商店审核。
