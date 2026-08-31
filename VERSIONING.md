# 版本号规则（VERSION RULES）
- 修复 Bug  → 版本号 +0.0.1（例：1.0 → 1.0.1，1.3 → 1.3.1）
- 新增功能 → 版本号 +0.1 并清空补丁位（例：1.0.1 上新增功能 → 1.1，1.3.1 上新增功能 → 1.4）
- 每次构建（bump）同时递增 CURRENT_PROJECT_VERSION（build number）
- 当前版本：1.6（内部构建号 CURRENT_PROJECT_VERSION 由 CI 自动递增）
## Release 发布规则
- 每次发布新版本时，同步创建 GitHub Release：标题为「Beans Music 版本号」，tag 为 v加版本号（例：v1.0.1）
- Release 正文必须写明本次的「新增功能」与「修复内容」，来源为 CHANGELOG.md 中对应版本的条目
- 版本号由维护者在 project.yml 中手动修改（修 bug 加 0.0.1，加功能加 0.1），CI 不再自动改版本号，只递增内部构建号
