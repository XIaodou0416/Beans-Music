# Beans 内嵌 CiliCili

上游：https://github.com/Rone89/cilicili

固定修订：`c61b0d33966c5d8e87ea20527b8ba48c702c10c1`（GPL-3.0-only）。

本次不是复刻截图：`Sources` 保留上游 Features、Services、Models、Storage、
DesignSystem、Utilities 的真实实现及目录结构。仅排除独立应用的 `JKBiliApp`
入口，由 `Integration` 提供 Beans 宿主桥接。上游原始 App 壳保留作出处参考，
Beans 实际入口不使用上游底部 TabView，因此不会出现两套底栏。

集成边界：

- Beans 继续拥有应用入口、音乐库、五个主标签、平台切换和主题。
- 哔哩哔哩推荐/热门、动态、直播、搜索、我的使用上游视图和 ViewModel。
- 视频、评论、播放器、弹幕、UP 主、收藏和登录使用上游完整链路。
- 详情路由由用户操作创建，播放状态不得反向创建页面；导航栈持有详情身份。
- 登录桥接仅在账号凭据实际改变时同步，凭据只写 Keychain，不写日志。
- 音乐和视频互斥播放；关闭视频不自动恢复音乐，不重置音乐队列。
- 保留 GPL 许可证，并随 IPA 提供对应源码版本和构建方法。

构建、测试和最终产物以 GitHub Actions 的对应提交为准，禁止发布 Release。

本版最低系统统一为 iOS 26.1，后续旧系统兼容另开版本。本次移除 Beans 原有
VideoPage、NativeComments、NativePlayer、UPPage、LivePage、CommentRow、
CiliCiliUI、NativeComponents、SearchResults；LoginSheet 只保留音乐账户存储
和跳转上游账号页的桥。旧代码可从 Git 父提交恢复，不作为运行时备用界面。

## 构建

使用 macOS、Xcode 26.5+ 和 XcodeGen：

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Beans.xcodeproj -scheme Beans -configuration Release \
  -sdk iphoneos -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

测试使用 scheme Beans 的 CiliCiliTests 和 BeansTests/BilibiliDetailTests。
工作流 `build-unsigned-ipa.yml` 同时上传 IPA、测试日志和 `git archive HEAD`
产生的对应源码。IPA 最低系统和内嵌 CiliCiliKit 动态库必须通过打包检查。

## 修改过的上游文件

- `App/RootTabView.swift`：将上游五个底部标签装入 Beans 顶部频道条，保留页面。
- `Features/Player/ActivePlaybackCoordinator.swift`：播放前通知 Beans 暂停音乐。
- `Storage/KeychainStore.swift`：Beans 命名空间，去除明文 UserDefaults 降级存储。
- `Features/Player/PlayerStateViewModel.swift`：释放本模块注册的锁屏回调，避免与音乐双重响应。
- `Features/Mine/MineOverlayNavigation.swift`：补齐上游遗漏的 watchLater 枚举分支。
- `Features/VideoDetail/VideoDetailSwiftUIContainer.swift`：给独立 UIHostingController 注入同一套依赖。
- `Features/Mine/MineDisplaySettingsSection.swift`：移除独立 App 专用的图标/全局外观/底栏配置。

`Integration` 是唯一新增宿主接口层；详情和评论组件不重绘。
