# Beans Music IPA 构建说明

本项目为 SwiftUI 编写的 iOS 音乐播放器。**IPA（iOS 应用包）只能在 macOS 上使用 Xcode 编译**，本仓库提供两种构建方式。

## 方式一：GitHub Actions（推荐，无需本地 macOS）

1. 推送代码到 `main` 分支，或在 Actions 页面手动触发 **Build Unsigned IPA** 工作流（`workflow_dispatch`）
2. 工作流会自动：
   - 安装 XcodeGen 并生成 `Beans.xcodeproj`
   - 使用 `xcodebuild` 以 `CODE_SIGNING_ALLOWED=NO` 构建 Release 版
   - 打包为未签名 `Beans-<版本>.ipa` 并上传为构建产物（Artifacts）
   - 可选：发布 GitHub Release

## 方式二：本地 macOS 构建

```bash
# 1. 安装 xcodegen（一次即可）
brew install xcodegen

# 2. 生成工程并构建未签名 IPA
./build-ipa.sh unsigned
# 产物: Beans-1.6.5.1-unsigned.ipa

# 3. 需要签名分发（真机安装）时，先导出开发者团队 ID：
export DEVELOPMENT_TEAM=XXXXXXXXXX
./build-ipa.sh signed
# 产物: Beans-1.6.5.1-signed.ipa
```

## 安装未签名 IPA（测试）

未签名 IPA 无法直接双击安装，可用以下方式之一：

- **Xcode 侧载**：`xcodebuild -project Beans.xcodeproj -scheme Beans -destination 'generic/platform=iOS' -allowProvisioningUpdates`（需要开发者账号）
- **第三方工具**：使用 Sideloadly / AltStore 等工具在个人 Apple ID 下签名安装
- **越狱设备**：直接拷贝安装

## 工程结构

- `project.yml`：XcodeGen 工程定义（版本号、Bundle ID、Info.plist 配置）
- `Beans/`：全部 SwiftUI 源码与资源
- `.github/workflows/build-unsigned-ipa.yml`：CI 自动构建

## 说明

- Bundle ID：`com.beans.app`
- 版本：1.6.5.1（Build 38）
- 最低系统：iOS 15.0
