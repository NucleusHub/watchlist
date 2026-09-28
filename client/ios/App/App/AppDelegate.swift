import UIKit
import Capacitor

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        hideWebFormAccessoryBar()
        return true
    }

    // Hides the bar WebKit shows above the keyboard for web inputs (prev/next
    // arrows + checkmark). @capacitor/keyboard only swizzles WKContentView, but
    // current WebKit makes the WKWebView itself first responder and returns a
    // WKFormAccessoryView from its inputAccessoryView, so patch both classes.
    private func hideWebFormAccessoryBar() {
        func swizzle(_ className: String, _ selector: Selector, _ block: Any) {
            guard let cls = NSClassFromString(className),
                  let method = class_getInstanceMethod(cls, selector) else { return }
            let imp = imp_implementationWithBlock(block)
            if !class_addMethod(cls, selector, imp, method_getTypeEncoding(method)) {
                method_setImplementation(method, imp)
            }
        }

        let noAccessory: @convention(block) (AnyObject) -> Bool = { _ in false }
        swizzle("WKContentView", NSSelectorFromString("requiresAccessoryView"), noAccessory)

        let nilView: @convention(block) (AnyObject) -> UIView? = { _ in nil }
        for name in ["WKContentView", "WKWebView"] {
            swizzle(name, #selector(getter: UIResponder.inputAccessoryView), nilView)
        }

        for name in ["WKContentView", "WKWebView"] {
            let selector = #selector(getter: UIResponder.inputAssistantItem)
            guard let cls = NSClassFromString(name),
                  let original = class_getMethodImplementation(cls, selector) else { continue }
            typealias Getter = @convention(c) (AnyObject, Selector) -> UITextInputAssistantItem
            let callOriginal = unsafeBitCast(original, to: Getter.self)
            let emptyGroups: @convention(block) (AnyObject) -> UITextInputAssistantItem = { obj in
                let item = callOriginal(obj, selector)
                item.leadingBarButtonGroups = []
                item.trailingBarButtonGroups = []
                return item
            }
            swizzle(name, selector, emptyGroups)
        }
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration",
                                          sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}
