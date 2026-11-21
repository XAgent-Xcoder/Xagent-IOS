# app

AgentPort 的 Flutter 应用：Dart 界面 + Swift 原生通道（iOS 版）。

本目录在 dsh-go 的 `app/` 基础上修改（去掉 `android/` 与 Kotlin 原生层），`ios/` 由 `flutter create --platforms=ios` 生成。Dart 客户端代码基于上游修改；原生层只实现 iOS 需要的少量平台通道（通知、深链、分享、文件、WebView、诊断等），其余 Android 专属通道返回安全默认值。

构建、签名、测试和许可见仓库根目录的 [README.md](../README.md)。
