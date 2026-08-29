# Beans Music 🎵

> 一款基于 **iOS 26 原生液态玻璃（Liquid Glass）** 的第三方音乐播放器（兼容 iOS 16+，低版本自动使用系统材质），聚合网易云音乐与 QQ 音乐，纯 SwiftUI 实现。
> 本软件完全开源，仅供学习研究使用。

[![GitHub Pages 预览](https://img.shields.io/badge/在线预览-GitHub%20Pages-blue)](https://xiaodou0416.github.io/Beans-Music/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-iOS%2016+-orange)]()
[![Swift](https://img.shields.io/badge/Swift-5-orange)]()

**👀 在线预览（HTML 介绍页）：** https://xiaodou0416.github.io/Beans-Music/

## 🧑‍💻 关于作者

- 作者本人**什么都不会**，连这篇介绍都是 **AI 写的** 🤡
- 本软件由 **OpenAI Codex** 编程助手开发，从需求分析、UI 设计到代码实现全程由 AI 完成
- **不喜勿喷**，纯新手小学生，欢迎温柔指教 🙏
- 软件完全开源（MIT License），欢迎任何人学习、修改、二次开发

## 📱 界面预览

<p align="center">
  <img src="docs/screenshots/home.png" width="320" alt="首页">
  <img src="docs/screenshots/home-light.png" width="320" alt="首页（浅色）">
</p>
<p align="center">
  <img src="docs/screenshots/lyrics.png" width="320" alt="歌词页">
  <img src="docs/screenshots/player.png" width="320" alt="播放封面页">
</p>
<p align="center">
  <img src="docs/screenshots/search.png" width="320" alt="搜索页面">
  <img src="docs/screenshots/library.png" width="320" alt="音乐库">
</p>
<p align="center">
  <img src="docs/screenshots/settings.png" width="320" alt="全局设置">
  <img src="docs/screenshots/theme-light.png" width="320" alt="主题设置（浅色）">
</p>

---


## 🎨 核心卖点：DIY 美化，你的播放器你做主

这不是一个"长什么样就什么样"的播放器——**从全局主题到播放器每一个组件，全部都可以自定义**。

**全局主题，一键换肤**
- 内置 9 套主题色：琥珀暖金 / 青碧湖绿 / 樱粉 / 星蓝 / 罗兰紫 / 赛博青 / 蜜桃粉 / 鎏金黑 / 翡翠绿
- 不满意？打开**色盘**，任意颜色随便选，整个 App 的强调色、按钮、进度条、文字高亮全部跟随
- 主题模式跟随系统 / 浅色 / 深色，深浅色两套观感分别适配

**壁纸库：你的背景你做主**
- 上传**多张**自定义壁纸，自动存入壁纸库，随时在库中切换替换，不用反复去相册
- 支持浅色 / 深色两套背景，暗色壁纸不再发黑
- 全局背景同步：主页、搜索、音乐库、「我的」一键同步同一套背景

**全局 UI 样式**
- 内置默认柔和、清透简洁、紧凑淡雅、描边高亮等样式
- 底栏、卡片、播放器、弹窗全部跟随，质感统一

**播放器底部布局：自由拖动**
- 进度条、控制按钮、指示线支持 **XY 自由拖动 + 缩放**，摆到任何你喜欢的位置
- 调整时有**悬浮窗实时预览**，边调边看效果，一键恢复默认
- 指示线位置、显示开关均可单独控制

**歌词：专业级 DIY**
- 颜色：当前行 / 未播放行 / 发光颜色，色盘任选；渐变起止色自由搭配
- 效果：发光强度、模糊起始距离与模糊强度、辉光全可调
- 排版：字号、行距、显示行数、对齐（居中 / 居左）、位置重心全可调
- 3D 立体倾斜：上下后仰 + 左右倾斜，营造空间感
- 长按多选复制歌词、歌词翻译、逐行跟随、点击跳转

**进度条与氛围**
- 4 种进度条样式：流光 / 辉光 / 极光 / 波浪，带渐变辉光效果
- DJ 节奏脉冲光效，随旋律律动
- 圆形封面模式 + 自动旋转，封面点击切换歌词视图

**一键备份你的全部设置**
- 主题、配色、歌词效果、播放器布局、音质等所有自定义配置
- 一键导出为 JSON 分享 / 一键导入恢复，换机不再重新调

---

## 🚀 双平台聚合，一个 App 听遍网易云 + QQ 音乐

- 网易云 / QQ 音乐一键切换：每日推荐、排行榜、推荐歌单、搜索、热门搜索全部跟随平台
- 网易云：扫码登录 + 应用内网页登录，同步歌单、收藏、听歌排行与 VIP / SVIP 标识
- QQ 音乐：扫码授权 + 网页登录 / Cookie 导入，同步歌单与 VIP 标识
- 双平台歌曲评论区、歌词、歌手主页互通

## 🎧 播放器：从封面里长出来的界面

- 动态封面取色：背景渐变、进度条、播放按钮、功能按钮、歌词高亮全部实时跟随专辑封面主色，切歌平滑过渡
- 抖音式上下滑动切歌，过渡动画丝滑；左右滑动也可切换
- 封面点击切换歌词视图（封面飞入左上角动画）、圆形封面模式 + 自动旋转
- 底部指示线上滑呼出评论区（网易云 + QQ 评论）

## ⚡ 播放能力拉满

- 5 档音质（标准 / 较高 / 极高 / 无损 / Hi-Res），无损与 Hi-Res 自动回落
- 免费听歌开关（灰色 / VIP / 版权歌曲自动匹配第三方音源）
- 第三方音源：内置聆澜 LX / CR / QT 三种预设，作为官方地址不可用时的备用来源
- 另内置统一音乐源 · GD Studio、忆音音源 · DreamMeting 两个 LX Music 预设
- 歌曲下载（低质量 128k / 高质量 320k，存到文件 App）
- 锁屏控制、控制中心、后台播放、播放队列与插队、倍速（0.5x~2.0x）、循环模式、±15 秒、睡眠定时
- 播放历史、网易云听歌排行（本周 / 所有时间）

## 📱 系统体验

- iOS 26 原生液态玻璃（Liquid Glass）TabBar，与系统 App 一致
- 封面页歌名与预览歌词颜色可分别自定义，默认继续跟随封面取色
- 首次进入 4 页引导（欢迎 / DIY 美化 / 双平台 / 免责确认）+ 版本更新说明弹窗 + 更新日志
- 软件使用说明、深浅色自适应

---

## 📂 工程结构

```
Beans/
├── BeansApp.swift                应用入口（首次使用引导页 + 免责确认）
├── RootView.swift                底部 Tab 液态玻璃导航 + 迷你播放器
├── DiscoverView.swift            发现页（每日推荐 / 排行榜 / 推荐歌单）
├── SearchView.swift              搜索（网易云 / QQ 切换 / 热搜）
├── LibraryView.swift             音乐库（歌单 / 本地音乐库 / 最近播放）
├── ProfileView.swift             我的（功能 / 听歌排行 / 使用说明 / 设置）
├── PlayerView.swift              播放器（动态取色 / 歌词 / 底部控制 / 设置）
├── PlayerManager.swift           播放核心（队列 / 倍速 / 定时 / 历史）
├── LoginView.swift               网易云登录（扫码 + 网页登录）
├── NetEaseWebLoginSheet.swift    网易云网页登录（WKWebView 读取 Cookie）
├── QQMusicAPI.swift / QQMusicAuth.swift / QQWebLoginSheet.swift  QQ 音乐接入
├── NetEaseAPI.swift / NetEaseCrypto.swift   网易云接口与加密（weapi / eapi）
├── AuthStore.swift / Models.swift   登录态与数据模型
├── Theme.swift / CoverPalette.swift   全局主题与封面取色
├── PlayerLayout.swift / PlayerAmbience.swift / DJVisualView.swift   布局与氛围
├── DownloadManager.swift / UnblockService.swift / UnblockSourceStore.swift   下载与音源
├── CommentsSheet.swift / ArtistHomeSheet.swift   评论与歌手主页
├── Changelog.swift / Components.swift / SongCell.swift   日志与组件库
└── Assets.xcassets                图标与资源
```

---

## 🔨 构建

GitHub Actions（`Build Unsigned IPA`）自动构建，产物发布到 [Releases](https://github.com/XIaodou0416/Beans-Music/releases)。

本地构建（需要 Mac + Xcode 26）：

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Beans.xcodeproj -scheme Beans -configuration Release \
  -sdk iphoneos -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/Beans.app Payload/
ditto -c -k --sequesterRsrc --keepParent Payload Beans-unsigned.ipa
```

## 📲 安装

未签名 IPA 需自行签名安装：Sideloadly / AltStore / 爱思助手，使用 Apple ID 签名（免费自签 7 天有效）。
- 支持 iOS 16+（iOS 26 上为原生液态玻璃，低版本自动使用系统材质）
- Bundle ID：`com.beans.app`

---

## ⚠️ 免责声明

- 本应用仅供个人学习研究使用，禁止用于商业及非法用途，如产生法律纠纷与作者无关
- 音乐 API 来源于 GitHub 开源项目（非官方版 API），本软件不提供任何音频存储服务
- 音乐版权归各平台所有，请支持正版；如需下载音频请在各平台官方渠道购买
- “QQ”、“QQ音乐”及企鹅形象等文字、图形和商业标识，其著作权或商标权归腾讯公司所有
- “网易云”、“网易云音乐”等文字、图形和商业标识，其著作权或商标权归网易公司所有
- 具体内容请参考各平台用户协议

## 📄 License

[MIT](LICENSE) © 2026 XIaodou0416

**开源说明：** 本项目为开源软件，代码公开透明，接受 Issue 反馈与 Fork 学习。非官方 API 属逆向学习范畴，请尊重各平台服务条款，合理使用。
