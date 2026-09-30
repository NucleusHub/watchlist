import UIKit
import Capacitor

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = ShakeWindow(windowScene: windowScene)
        let bridgeController = CAPBridgeViewController()
        WatchBridge.shared.bridgeProvider = { [weak bridgeController] in bridgeController?.bridge }
        window?.rootViewController = bridgeController
        window?.makeKeyAndVisible()

        SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }
}

// Shake to report a problem. Caught on the window because nothing past it
// sees the shake: UIApplication keeps it for shake-to-undo. The web app
// listens for "nativeshake" (src/composables/useReportSheet.js); no permission
// is needed, unlike DeviceMotionEvent in the web view.
class ShakeWindow: UIWindow {
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else { return super.motionEnded(motion, with: event) }
        (rootViewController as? CAPBridgeViewController)?.bridge?.triggerWindowJSEvent(eventName: "nativeshake")
    }
}
