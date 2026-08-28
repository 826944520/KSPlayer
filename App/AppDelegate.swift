//
//  AppDelegate.swift
//  KSPlayer
//
//  Created by Architecture Team on 2026/08/28.
//  App 启动入口 - 移除强制闪屏页，优化启动性能
//

import Foundation
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 记录启动时间
        let launchStartTime = Date()

        // 配置依赖注入容器
        setupDependencyContainer()

        // 配置日志
        setupLogger()

        // 移除强制闪屏页，直接进入主界面
        setupWindow()

        // 异步预加载关键资源（不阻塞启动）
        Task {
            await preloadCriticalResources()

            // 记录启动时间
            let launchTime = Date().timeIntervalSince(launchStartTime)
            DependencyContainer.shared.makeLogger().info("App launched in \(String(format: "%.3f", launchTime))s")
        }

        return true
    }

    // MARK: - Setup Methods

    private func setupDependencyContainer() {
        // 初始化依赖注入容器（单例，懒加载）
        _ = DependencyContainer.shared
    }

    private func setupLogger() {
        let logger = DependencyContainer.shared.makeLogger()
        logger.info("KSPlayer starting...")
    }

    private func setupWindow() {
        window = UIWindow(frame: UIScreen.main.bounds)

        // 直接进入主界面，不显示闪屏页
        let mainViewController = MainTabBarController()
        window?.rootViewController = mainViewController
        window?.makeKeyAndVisible()
    }

    private func preloadCriticalResources() async {
        // 异步预加载，不阻塞启动
        await Preloader().preloadCriticalResources()
    }

    // MARK: - App Lifecycle

    func applicationWillResignActive(_ application: UIApplication) {
        // 暂停播放
        DependencyContainer.shared.makeRouter().route(.pausePlayback)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // 进入后台，保存播放状态
        // TODO: 保存当前播放进度
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // 从后台恢复
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // 恢复播放（如果之前在播放）
        // TODO: 检查是否需要恢复播放
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // 清理资源
        DependencyContainer.shared.cleanup()
    }
}

// MARK: - Main Tab Bar Controller

class MainTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()
    }

    private func setupTabs() {
        let playerVC = PlayerViewController()
        playerVC.tabBarItem = UITabBarItem(
            title: "播放",
            image: UIImage(systemName: "play.circle.fill"),
            selectedImage: nil
        )

        let settingsVC = SettingsViewController()
        settingsVC.tabBarItem = UITabBarItem(
            title: "设置",
            image: UIImage(systemName: "gearshape.fill"),
            selectedImage: nil
        )

        let historyVC = HistoryViewController()
        historyVC.tabBarItem = UITabBarItem(
            title: "历史",
            image: UIImage(systemName: "clock.fill"),
            selectedImage: nil
        )

        viewControllers = [
            UINavigationController(rootViewController: playerVC),
            UINavigationController(rootViewController: settingsVC),
            UINavigationController(rootViewController: historyVC)
        ]

        tabBar.tintColor = .blue
        tabBar.unselectedItemTintColor = .gray
    }
}

// MARK: - Placeholder View Controllers

class PlayerViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "播放器"

        // TODO: 集成 SwiftUI PlayerView
    }
}

class SettingsViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        title = "设置"
    }
}

class HistoryViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        title = "历史"
    }
}