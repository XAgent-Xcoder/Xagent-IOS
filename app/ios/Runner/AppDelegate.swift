import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var dshGoChannels: DshGoChannels?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // 通知 tap 转发给 Dart（dsh/notify/taps 事件流）。
    UNUserNotificationCenter.current().delegate = self
    return ok
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    dshGoChannels = DshGoChannels(messenger: engineBridge.applicationRegistrar.messenger())
    DshGoChannels.shared = dshGoChannels
  }

  // 通知被点开：载荷从通知的 userInfo 取（冷启动后内存已丢但 UNNotificationRequest 还在），
  // 推回 Dart 的 taps 事件流。深链走 SceneDelegate（scene 模式下 application(_:open:) 不触发）。
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletion completion: @escaping () -> Void
  ) {
    let payload = response.notification.request.content.userInfo
    dshGoChannels?.emitTap(payload: payload)
    completion()
  }

  // 后台保活：切后台时上报 CallKit 外呼锁定后台执行时间，让 Dart 侧 WebRTC / Control WS
  // 持续运行（根治锁屏/切后台断连）；回前台结束呼叫归还额度。
  override func applicationDidEnterBackground(_ notification: Notification) {
    super.applicationDidEnterBackground(notification)
    VoIPKeepAlive.shared.requestKeepAlive()
  }

  override func applicationWillEnterForeground(_ notification: Notification) {
    super.applicationWillEnterForeground(notification)
    VoIPKeepAlive.shared.releaseKeepAlive()
  }
}
