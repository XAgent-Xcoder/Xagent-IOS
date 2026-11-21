import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // scene 模式下深链 / file:// 走这里（不是 AppDelegate.application(_:open:)）。
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
      DshGoChannels.shared?.pushLink(context.url.absoluteString)
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
