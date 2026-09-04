# Beans Music

Beans Music is an open-source SwiftUI music player for iOS 15 and later. It brings several music platforms, local playlists, lyrics, downloads, and a highly configurable player into one native app.

This repository contains the public iOS client.

## Highlights

- NetEase Cloud Music, QQ Music, and Kugou Music browsing and search
- Account login, synced playlists, favorites, rankings, artists, albums, and recent plays
- Playback queue, shuffle, repeat, playback speed, sleep timer, background playback, and lock-screen controls
- Lyrics with translation, appearance controls, scrolling, and interactive seeking
- Multiple player layouts, Liquid Glass styling on supported systems, themes, wallpapers, and equalizer controls
- Local playlists, offline files, importable music sources, and native share/export flows
- Chinese and English localization

## Project Layout

```
Beans/
  BeansApp.swift              Application entry point
  RootView.swift              Tab navigation and mini player
  DiscoverView.swift          Home, recommendations, and rankings
  SearchView.swift            Platform search and result navigation
  LibraryView.swift           Synced and local music libraries
  ProfileView.swift           Account, appearance, backup, and settings
  PlayerView.swift            Full player and lyrics experience
  PlayerManager.swift         Queue, playback, history, and recovery
  NetEaseAPI.swift            NetEase integration
  QQMusicAPI.swift            QQ Music integration
  KugouMusicAPI.swift         Kugou integration
  UnblockService.swift        User-configured source resolution
  DownloadManager.swift       Audio download and export
  Theme.swift                 Theme and wallpaper state
  Models.swift                Shared models and enums
```

## Build

Requirements:

- macOS
- Xcode 26 or later
- XcodeGen

Generate the project and build an unsigned app:

```bash
brew install xcodegen
xcodegen generate
xcodebuild \
  -project Beans.xcodeproj \
  -scheme Beans \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build
```

The GitHub Actions workflow can build an unsigned IPA on demand. The workflow is configured for test builds by default and does not create a release unless explicitly enabled.

## Development Notes

- The project uses SwiftUI and keeps platform-specific networking inside the corresponding API files.
- User-configured music sources are stored locally and are not bundled with this repository.
- Do not commit credentials, cookies, API keys, personal files, build artifacts, or local configuration.
- Keep changes focused and verify `git diff --check` before opening a pull request.

## License

This project is distributed under the MIT License. See [LICENSE](LICENSE).

Music, trademarks, and platform services belong to their respective owners. Use the app responsibly and follow each platform's terms of service.
