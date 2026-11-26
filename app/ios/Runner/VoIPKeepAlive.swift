// VoIPKeepAlive — 用 CallKit 上报"进行中的呼叫"锁定后台执行时间，根治切后台/锁屏断连。
//
// 背景：iOS 切后台/锁屏会挂起 App 的 Dart 事件循环，OS 直接拆掉 WebRTC DataChannel
// 与 Control WS 的 socket；App 未声明任何后台模式，几秒后被杀，回前台才由看门狗
// backoff 重连，被杀则彻底不重连。
//
// 做法：声明 `voip` 后台模式（Info.plist），切后台时用 CXProvider 上报一个进行中的
// 外呼并置为已连接，系统认为有 VoIP 通话在进行，保留进程与网络执行时间，Dart 侧
// 的 WebRTC / Control WS 得以持续运行、看门狗正常重连。回前台结束呼叫，归还额度。
// provider 失效时重建并（若仍在后台）重新上报。
//
// 注意：纯 CallKit 保活无需服务端 VoIP push，自成闭环。若日后要让"已被杀的进程"
// 也能被唤醒，需 relay 侧发 VoIP push（aps.category="voip"）+ 这里接
// registerForRemoteNotifications，那是服务端改动，另行处理。
import UIKit
import CallKit

final class VoIPKeepAlive: NSObject, CXProviderDelegate {
  static let shared = VoIPKeepAlive()

  private var provider: CXProvider?
  private let callUUID = UUID()
  private var active = false

  private override init() {
    super.init()
    makeProvider()
  }

  private func makeProvider() {
    let configuration = CXProviderConfiguration()
    configuration.supportsVideo = false
    configuration.supportedReasonForReset = .unsupported
    configuration.maximumActiveCalls = 1
    let provider = CXProvider(configuration: configuration)
    provider.delegate = self
    self.provider = provider
  }

  /// 切后台：上报一个进行中的外呼并置为已连接，锁定后台执行时间。
  func requestKeepAlive() {
    guard !active, let provider else { return }
    active = true
    reportOutgoingCall()
  }

  /// 回前台：结束呼叫，归还后台执行额度。
  func releaseKeepAlive() {
    guard active, let provider else { return }
    active = false
    provider.endCalls(with: [.outgoing, .incoming])
  }

  private func reportOutgoingCall() {
    guard let provider else { return }
    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: "xagent-keepalive")
    update.hasVideo = false
    provider.reportOutgoingCall(with: callUUID, updated: update)
    update.connectedTime = Date()
    provider.reportCallChanged(update)
  }

  // MARK: - CXProviderDelegate

  func providerDidInvalidated(_ provider: CXProvider) {
    makeProvider()
    if active { reportOutgoingCall() }
  }

  func provider(_ provider: CXProvider, resetFailedAttemptWithCallUUID callUUID: UUID, reason: CXProviderResetReason) {
    provider.endCalls(with: [.outgoing, .incoming])
    if active { reportOutgoingCall() }
  }
}
