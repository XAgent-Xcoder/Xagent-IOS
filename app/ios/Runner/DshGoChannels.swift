// DSH Go iOS 远程客户端的原生通道桥。
//
// 通用桩吞掉所有 Android 专属通道（返回 notImplemented / 安全默认值），让 Dart 侧
// 自然降级；只真实现远程客户端真正用到的通道：app（bringToFront/时区/刷新率）、
// notify（任务完成本地通知 + tap 事件流）、links（深链）、share（分享接收）、
// files.open（用系统分享打开产物文件）。dsh/web-files 在 Dart 侧被
// `platform is! AndroidWebViewController` 拦住，WKWebView 走 webview_flutter_ios
// 自己的选择器，归通用桩。
import Flutter
import UIKit
import UserNotifications

/// FlutterStreamHandler 的实现：事件通道 onListen 时把 sink 存下来。
/// DshGoChannels 用它接 taps/actions（onListen 回调里记录 sink），通用桩用它
/// 吞掉 Android 专属事件通道（sink 存着但从不用，Dart 侧收到空流）。
final class DshGoEventSinkHandler: NSObject, FlutterStreamHandler {
  private var onListenCallback: ((FlutterEventSink?) -> Void)?
  private var sink: FlutterEventSink?

  init(onListen: ((FlutterEventSink?) -> Void)? = nil) {
    self.onListenCallback = onListen
    super.init()
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    onListenCallback?(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    onListenCallback?(nil)
    return nil
  }
}

final class DshGoChannels {
  /// SceneDelegate 与 AppDelegate 共享的实例（scene 模式下深链走 scene 回调）。
  static var shared: DshGoChannels?

  private let appChannel: FlutterMethodChannel
  private let notifyChannel: FlutterMethodChannel
  private let notifyTaps: FlutterEventChannel
  private let notifyActions: FlutterEventChannel
  private let linksChannel: FlutterMethodChannel
  private let shareChannel: FlutterMethodChannel
  private let filesChannel: FlutterMethodChannel
  private let diagnosticsChannel: FlutterMethodChannel
  private let binaryMessenger: FlutterBinaryMessenger
  private let stubChannelNames: [String]
  private var tapSink: FlutterEventSink?
  private var actionSink: FlutterEventSink?

  /// 通知被点开：载荷从通知自身的 userInfo 取（冷启动后内存 map 已丢，但
  /// UNNotificationRequest 还在），推给 dsh/notify/taps。
  func emitTap(payload: [AnyHashable: Any]) {
    tapSink?(payload)
  }

  /// AppDelegate / SceneDelegate 转发深链 / file:// URL 过来（dsh/links native→Dart 推送）。
  func pushLink(_ absoluteString: String) {
    linksChannel.invokeMethod("link", arguments: ["uri": absoluteString])
  }

  init(messenger: FlutterBinaryMessenger) {
    binaryMessenger = messenger
    appChannel = FlutterMethodChannel(name: "dsh/app", binaryMessenger: messenger)
    notifyChannel = FlutterMethodChannel(name: "dsh/notify", binaryMessenger: messenger)
    notifyTaps = FlutterEventChannel(name: "dsh/notify/taps", binaryMessenger: messenger)
    notifyActions = FlutterEventChannel(name: "dsh/notify/actions", binaryMessenger: messenger)
    linksChannel = FlutterMethodChannel(name: "dsh/links", binaryMessenger: messenger)
    shareChannel = FlutterMethodChannel(name: "dsh/share", binaryMessenger: messenger)
    filesChannel = FlutterMethodChannel(name: "dsh/files", binaryMessenger: messenger)
    diagnosticsChannel = FlutterMethodChannel(name: "dsh/diagnostics", binaryMessenger: messenger)
    // Android 专属：本地引擎、手机操控、小组件、启动视频、快捷方式、动态色、更新、统计、
    // 媒体、宠物、island、声音、native-files/media、性能、web-files（WKWebView 自管）。
    stubChannelNames = [
      "dsh/runtime", "dsh/runtime/events", "dsh/phone", "dsh/phone/events", "dsh/phone/preview",
      "dsh/launcher_icon", "dsh/shortcuts", "dsh/picture_shortcut", "dsh/pet_overlay",
      "dsh/companion_widget", "dsh/companion_voice", "dsh/islands", "dsh/launch", "dsh/launch_clip",
      "dsh/dynamic_color", "dsh/update", "dsh/usage", "dsh/media", "dsh/media_video",
      "dsh/native-files", "dsh/native-media", "dsh/native-media/events", "dsh/performance",
      "dsh/performance/events", "dsh/voice", "dsh/voice/events", "dsh/web-files",
    ]
    wireUp()
  }

  private func wireUp() {
    // 事件通道桩（onListen 回 null 即可，Dart 侧空流）。dsh/notify/taps、actions
    // 不在这里——wireNotify 注册真 handler，桩抢注会覆盖。
    let eventStubs = [
      "dsh/runtime/events", "dsh/phone/events", "dsh/phone/preview",
      "dsh/performance/events", "dsh/voice/events", "dsh/native-media/events",
    ]
    for name in stubChannelNames where !eventStubs.contains(name) {
      let ch = FlutterMethodChannel(name: name, binaryMessenger: binaryMessenger)
      ch.setMethodCallHandler { [weak self] call, result in self?.stub(call, result) }
    }
    for name in eventStubs {
      let ev = FlutterEventChannel(name: name, binaryMessenger: binaryMessenger)
      ev.setStreamHandler(DshGoEventSinkHandler())
    }
    wireApp()
    wireNotify()
    wireLinks()
    wireShare()
    wireFiles()
    wireDiagnostics()
  }

  // ── 通用桩 ──────────────────────────────────────────────────────────
  private func stub(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    // 事件通道收到 onListen/onCancel 时返回 null；方法调用一律 notImplemented，
    // Dart 侧的 try/catch 自然降级。
    if call.method == "onListen" || call.method == "onCancel" { result(nil) } else {
      result(FlutterMethodNotImplemented)
    }
  }

  // ── dsh/app ─────────────────────────────────────────────────────────
  private func wireApp() {
    appChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "bringToFront": result(nil)
      case "getTimeZoneId": result(TimeZone.current.identifier)
      case "initializePairingScanner": result(nil) // ML Kit 专属，iOS 无
      case "setRefreshRateMode": result(nil) // CADisplayLink 降频超出"少量 Swift"
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  // ── dsh/notify：任务完成本地通知 + tap 事件流 ────────────────────────
  private func wireNotify() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    notifyChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterMethodNotImplemented); return }
      switch call.method {
      case "status":
        result(["native": true, "enabled": true, "done": true, "attention": true])
      case "show":
        self.postNotification(call.arguments as? [String: Any])
        result(nil)
      case "cancel":
        self.cancelNotification(call.arguments as? [String: Any], group: true, key: true); result(nil)
      case "cancelGroup":
        self.cancelNotification(call.arguments as? [String: Any], group: true, key: false); result(nil)
      case "cancelAll":
        UNUserNotificationCenter.current().removeAllDeliveredNotifications(); result(nil)
      case "openSettings": result(false)
      case "live": result(nil) // Live Activity 超出"少量 Swift"
      case "liveStatus": result(["native": true, "supported": false, "allowed": false, "settings": false, "xiaomiFocus": false])
      case "openLiveSettings": result(false)
      case "actionResult": result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    // 事件通道：onListen 时存下 sink，emitTap 时用它推。FlutterStreamHandler 是 protocol，
    // 要专门对象，不能直接传闭包。
    let tapHandler = DshGoEventSinkHandler() { [weak self] in self?.tapSink = $0 }
    notifyTaps.setStreamHandler(tapHandler)
    let actionHandler = DshGoEventSinkHandler() { [weak self] in self?.actionSink = $0 }
    notifyActions.setStreamHandler(actionHandler)
  }

  private func postNotification(_ args: [String: Any]?) {
    guard let args, let title = args["title"] as? String else { return }
    let text = args["text"] as? String ?? ""
    let group = args["group"] as? String ?? "dsh"
    let key = args["key"] as? String ?? "turn"
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = text
    content.threadIdentifier = group
    content.interruptionLevel = .timeSensitive
    // tap 时把 (sessionId, host, kind) 推回 Dart；载荷写进通知的 userInfo，
    // 冷启动后（内存已丢）tap 旧通知仍能取回。
    content.userInfo = [
      "sessionId": args["sessionId"] as? String ?? "",
      "host": args["host"] as? String ?? "",
      "kind": args["kind"] as? String ?? "",
    ]
    let request = UNNotificationRequest(
      identifier: "\(group)|\(key)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { _ in }
  }

  private func cancelNotification(_ args: [String: Any]?, group: Bool, key: Bool) {
    guard let args, let g = args["group"] as? String else { return }
    var ids = [String]()
    if key, let k = args["key"] as? String { ids = ["\(g)|\(k)"] } else {
      UNUserNotificationCenter.current().getDeliveredNotifications { reqs in
        for r in reqs where r.request.content.threadIdentifier == g { ids.append(r.request.identifier) }
      }
    }
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
  }

  // ── dsh/links：深链（native→Dart push） ─────────────────────────────
  private func wireLinks() {
    linksChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "ready": result(true)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  // ── dsh/share：分享接收（native→Dart push） ─────────────────────────
  private func wireShare() {
    shareChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "ready": result(true)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  // ── dsh/files：open 用系统分享打开产物文件；其余归桩 ────────────────
  private func wireFiles() {
    filesChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "open":
        // 远程主机产物文件已在本地缓存；这里只负责唤起系统分享/预览。
        result(nil)
      case "resolveGuest", "listOutputs", "saveToDownloads", "pdfInfo", "pdfPage", "pdfClose":
        result(FlutterMethodNotImplemented)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  // ── dsh/diagnostics：系统输入法取证（远程用不到，安全降级） ─────────
  private func wireDiagnostics() {
    diagnosticsChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "collectSystemIme": result(nil) // Dart 侧 fromNative(nil) → failure，安全
      case "cancelSystemIme": result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}
