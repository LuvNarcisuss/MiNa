import UIKit
import React
import React_RCTAppDelegate
import ReactAppDependencyProvider

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        true
    }
}

final class SceneDelegate: RCTDefaultReactNativeFactoryDelegate, UIWindowSceneDelegate {
    var window: UIWindow?
    private var factory: RCTReactNativeFactory?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        #if DEBUG
        RCTBundleURLProviderAllowPackagerServerAccess(false)
        #endif
        dependencyProvider = RCTAppDependencyProvider()
        factory = RCTReactNativeFactory(delegate: self)
        window = UIWindow(windowScene: scene)
        factory?.startReactNative(withModuleName: "MiNa", in: window, connectionOptions: options)
    }

    override func bundleURL() -> URL? {
        Bundle.main.url(forResource: "main", withExtension: "jsbundle")
    }
}
