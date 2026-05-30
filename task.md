# 当前任务

## 目标

- 增加手机端可发布版本：iOS/Android 原生壳接收 Markdown 文件，复用同一份本地 HTML 渲染层快速只读预览。
- 沿用桌面版图标。
- 声明 iOS 文档类型和 Android intent filter，让应用进入系统 Markdown 打开方式/默认打开器选择。
- 补齐 Android 签名 release APK/AAB、iOS 隐私清单、发布脚本和 release-readiness 验证。

## 非目标

- 本轮不做移动端编辑、实时文件监听、打印和商店上架。
- 本轮不重构桌面端 Rust 渲染主线。

## 验收场景

- [x] 场景 1：iOS 工程可生成，Swift 源码可解析。证据：`./scripts/verify.sh` 中 `xcodegen generate` 和 `xcrun --sdk iphoneos swiftc -parse ...` 通过；本机 Xcode destination 报 iOS platform not installed，已跳过完整 iOS build。
- [x] 场景 2：Android debug 包可构建，manifest 包含 Markdown 打开入口。证据：`./scripts/verify.sh` 中 `gradle :app:assembleDebug` 通过。
- [x] 场景 3：共享渲染层离线可解析 Markdown。证据：Playwright 以 390x844 移动视口打开 `mobile/shared/preview.html`，渲染标题、任务列表、代码块和表格，无控制台错误。
- [x] 场景 4：移动渲染层拦截危险链接，外链走原生系统打开。证据：JS/iOS/Android 三层拦截 `javascript:` / `data:` / `vbscript:`，Playwright 点击 `javascript:` 链接未执行。
- [x] 场景 5：发布前剩余工作清单明确。证据：`mobile/RELEASE_CHECKLIST.md`。
- [x] 场景 6：Android release 可签名产物可生成。证据：`mobile/scripts/verify-release-readiness.sh` 通过，`app-release.apk` 和 `app-release.aab` 已生成且签名验证通过。
- [x] 场景 7：签名 release APK 可在 Android emulator 启动。证据：安装 `app-release.apk` 后 `MainActivity` 为 resumed activity，截图显示空状态页面。

## 执行记录

- [x] 已批量理解项目结构、同类实现、配置和测试入口。
- [x] 已完成实现。
- [x] 已运行最小相关验证。
- [x] 已检查 `git diff` / 新增文件清单，无调试代码、凭据或无关改动。

## 验证记录

```text
命令：./scripts/verify.sh
结果：通过。cargo test 7/7；iOS xcodegen 生成成功，Swift parse 通过，完整 iOS build 因本机 Xcode destination 报 platform not installed 被跳过；Android assembleDebug 成功。

命令：Playwright file:// mobile/shared/preview.html，390x844 移动视口注入样例 Markdown。
结果：通过。页面非空，标题、代码高亮、表格渲染可见，无 page error/console error。

命令：Playwright 点击 Markdown 中的 javascript: 链接。
结果：通过。`window.__bad` 未被设置，危险链接未执行。

命令：mobile/scripts/verify-release-readiness.sh
结果：通过。Android signed release APK/AAB 生成并验证，Android release 无 INTERNET 权限，iOS Info.plist / PrivacyInfo.xcprivacy 通过 lint，iOS 工程生成和 Swift parse 通过。

命令：Android emulator API 35 安装并启动 signed release APK。
结果：通过。`app.mdpreview.mobile/.MainActivity` 进入 resumed 状态，截图显示 MD Preview 空状态页面。
```

## 风险和假设

- iOS 系统不允许应用静默设为默认打开器，只能通过文档类型声明进入打开方式，由用户选择。
- Android 不同文件管理器/微信版本传递的 MIME 可能不同，本轮覆盖常见 Markdown MIME、text/plain、application/octet-stream 和扩展名。
- 当前机器没有可用 iOS destination，也没有连接 Android/iOS 真机；真机微信/企业微信入口需要按 `mobile/RELEASE_CHECKLIST.md` 验收。
- 本机已生成 Android upload keystore 和 `.env.mobile-release`，二者被 `.gitignore` 忽略，不进入 git。
