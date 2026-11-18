# Flutter 工具链安装与构建验证

Type: task
Status: resolved

## Question

本机未安装 Flutter / Dart。安装 Flutter SDK（稳定版），配置 iOS 与 Android 工具链，验证：

1. `flutter doctor` 全绿，或记录无法消除的项及原因。
2. 新建空项目，在 iOS 模拟器与 Android 模拟器 / 真机各跑一次。
3. 记录 Flutter / Dart / Xcode / Android SDK 版本、可用设备 / 模拟器、构建命令。

完成标准：上述验证通过，并把版本与命令写入票内 `## Answer`。执行前先向用户确认安装方式（官方归档 / FVM / Homebrew）。

## Answer

用户确认沿用现有安装（官方归档 `/Users/transon/flutter`，`~/.local/bin/flutter` 为其符号链接），未重装。

### 环境

| 项 | 版本 / 路径 |
|---|---|
| Flutter | 3.50.0 stable，framework `ab2912035e`，engine `371f77202a` |
| Dart | 3.14.0（DevTools 2.61.0） |
| 主机 | macOS 15.8.2 arm64 |
| Xcode | 26.3（Build 17C529），CocoaPods 1.17.0 |
| Android SDK | 36.0.0，`/Users/transon/Library/Android/sdk` |
| Android platform | `android-36`（构建时自动安装）、`android-37.0` |
| Build Tools | 36.0.0 |
| NDK | 28.2.13676358（Flutter 模板要求；从腾讯镜像手动安装） |
| JDK | OpenJDK 25.0.4（Android Studio 内置 JBR） |
| 许可证 | Android licenses 已全部接受 |

`flutter doctor -v` 结果：`No issues found!`（Flutter / Android toolchain / Xcode / Chrome / Network resources 全绿；Connected device 只列出 macOS 与 Chrome，iOS 模拟器与 Android 模拟器需手动启动）。

可用模拟器：

- iOS：iPhone 17 Pro（iOS 26.3，UDID `AB9602D3-C05D-4B05-91D1-6F8F2443745F`）等 11 台。
- Android：`Medium_Phone_API_37.0`（Android 17 / API 37，运行时设备号 `emulator-5554`）。

### 验证

临时空项目：`flutter create --platforms=ios,android --project-name toolchain_check toolchain_check`，位于 `/tmp`，验证后已删除。

iOS 模拟器（iPhone 17 Pro）：

```bash
flutter build ios --simulator --debug
xcrun simctl boot AB9602D3-C05D-4B05-91D1-6F8F2443745F
xcrun simctl install AB9602D3-C05D-4B05-91D1-6F8F2443745F build/ios/iphonesimulator/Runner.app
xcrun simctl launch AB9602D3-C05D-4B05-91D1-6F8F2443745F com.example.toolchainCheck
```

结果：`✓ Built build/ios/iphonesimulator/Runner.app`，进程启动（PID 59933），截图确认 Flutter counter 页面。

Android 模拟器（Medium_Phone_API_37.0）：

```bash
flutter emulators --launch Medium_Phone_API_37.0
flutter build apk --debug
~/Library/Android/sdk/platform-tools/adb install -r build/app/outputs/flutter-apk/app-debug.apk
~/Library/Android/sdk/platform-tools/adb shell am start -n com.example.toolchain_check/.MainActivity
```

结果：`✓ Built build/app/outputs/flutter-apk/app-debug.apk`（157,928,232 字节，`assembleDebug` 317.9s），安装成功，进程 PID 9792，截图确认 Flutter counter 页面。

### 环境注意

- `adb` 不在 `PATH`，需用 `~/Library/Android/sdk/platform-tools/adb`。
- 首次 Gradle 构建需下载 Gradle 9.5.0-all（240,667,887 字节）与依赖。直连/代理不稳定时 Gradle 会卡在解析阶段；本次临时项目在 `android/settings.gradle.kts` 与 `android/build.gradle.kts` 前置了阿里云 Maven 镜像，Gradle 发行版与 NDK 用 `curl` 从腾讯镜像下载。仓库工程在相同网络下构建时建议同样配置镜像或预热缓存。
- AGP 构建时自动补装 Android SDK Platform 36；NDK 28.2.13676358 为当前 Flutter 模板要求。
