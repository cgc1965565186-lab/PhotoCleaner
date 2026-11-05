# 净屿 · iPhone 相册整理

面向个人 iPhone 使用的 SwiftUI + PhotoKit 应用，最低支持 iOS 18。所有分析在设备本机完成，不上传媒体，不使用账号或分析服务。

- 相似照片检测基于感知哈希（dHash）与 BK-Tree 分组，查重全程不读取媒体内容
- 完全开源（MIT），核心算法带单元测试，欢迎 Fork 与 PR

## 快速上手

1. `git clone` 本仓库，用 Xcode 打开 `PhotoCleaner.xcodeproj`
2. 选中 PhotoCleaner target → Signing & Capabilities → 勾选「Automatically manage signing」，选择你自己的 Team（免费个人账号即可）
3. 连接 iPhone，选择设备后 ⌘R 运行
4. 首次运行在「整理」页点「开始智能扫描」

注意：项目未内置开发团队，克隆后需要完成第 2 步；免费账号签名的描述文件 7 天过期，过期后重新运行即可。

## 功能与结构

三个标签页，二级页面统一走导航栈推入：

- **整理**：设备容量与图库概况、智能扫描入口、整理清单（完全重复 / 视觉相似 / 同组连拍 / 截图 / 实况照片 / 视频），逐项推入对应结果页
- **图库**：全量媒体浏览，网格/列表切换，排序与筛选，多选批量删除；轻点缩略图进入详情页
- **设置**：权限状态、隐私说明、本地索引管理

- 重复检测：感知哈希（dHash）+ BK-Tree 候选分组；字节数、像素尺寸与哈希完全一致时判为完全重复
- 详情页：大图预览、完整元信息、加入待删清单
- 重复分组支持「仅保留建议项」一键选中
- PhotoKit 完整/有限访问状态处理；扫描只在用户主动触发后进行
- 扫描中断保留已完成部分，重新扫描复用本地索引

## 性能设计

- 文件大小来自照片库资源元数据（`PHAssetResource` 键值读取），**不读取媒体内容、不下载原始文件**，万级图库数秒内完成
- 相似检测只读系统缩略图（192px），4 路并发计算指纹
- 查重与分组在后台线程执行，主线程只接收批量结果
- 扫描进度按百分比节流，避免高频刷新视图
- 缩略图使用 `PHCachingImageManager` + 内存缓存，请求分辨率按屏幕缩放倍率换算

## 构建

用 Xcode 打开 `PhotoCleaner.xcodeproj`。项目部署目标为 iOS 18，使用自动签名与个人开发团队。

命令行真机构建：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
  -configuration Debug -destination 'platform=iOS,id=<设备UDID>' \
  -allowProvisioningUpdates -derivedDataPath /tmp/PhotoCleanerDevice build
```

安装与启动：

```sh
xcrun devicectl device install app --device <设备UDID> /tmp/PhotoCleanerDevice/Build/Products/Debug-iphoneos/PhotoCleaner.app
xcrun devicectl device process launch --device <设备UDID> app.codex.jingyu
```

### 已知环境补丁

Xcode 27.1 在 macOS 27.2 上启动 Swift 宏插件服务会因嵌套沙箱被拒（`sandbox-exec: sandbox_apply: Operation not permitted`），导致 `@Observable` / `@Model` 编译失败。项目已在 Debug/Release 配置加入 `OTHER_SWIFT_FLAGS = -Xfrontend -disable-sandbox` 绕过；升级 Xcode 27.2 及以上后可移除。

## 算法单元测试

```sh
swift test --disable-sandbox --scratch-path /tmp/PhotoCleanerPackageBuild
```

## 说明

相似度分组是审核提示。建议保留项不会自动勾选，应用不会自动删除照片，也不会清理系统缓存或其他应用的数据。免费开发者账号签名的描述文件 7 天过期，过期后重新构建安装即可。

本项目以 MIT 协议开源，详见 [LICENSE](LICENSE)。欢迎提交 Issue 与 Pull Request。
