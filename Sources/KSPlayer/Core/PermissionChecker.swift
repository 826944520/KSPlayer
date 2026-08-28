//
//  PermissionChecker.swift
//  KSPlayer
//
//  Created by Architecture Team on 2026/08/28.
//  权限检查器 - 隐私合规
//

import Foundation
import AVFoundation
import Photos
import UserNotifications
import CoreLocation

@MainActor
final class PermissionChecker: ObservableObject {
    static let shared = PermissionChecker()

    @Published private(set) var cameraPermission: PermissionStatus = .notDetermined
    @Published private(set) var microphonePermission: PermissionStatus = .notDetermined
    @Published private(set) var photoLibraryPermission: PermissionStatus = .notDetermined
    @Published private(set) var notificationPermission: PermissionStatus = .notDetermined
    @Published private(set) var locationPermission: PermissionStatus = .notDetermined

    private init() {}

    // MARK: - Check Availability

    func checkAvailability() async {
        cameraPermission = await checkPermission(.camera)
        microphonePermission = await checkPermission(.microphone)
        photoLibraryPermission = await checkPermission(.photoLibrary)
        notificationPermission = await checkPermission(.notification)
        locationPermission = await checkPermission(.location)

        DependencyContainer.shared.makeLogger().info("Permission check completed")
    }

    // MARK: - Request Permission

    func requestPermission(_ type: PermissionType) async -> PermissionStatus {
        switch type {
        case .camera:
            return await requestCamera()
        case .microphone:
            return await requestMicrophone()
        case .photoLibrary:
            return await requestPhotoLibrary()
        case .notification:
            return await requestNotification()
        case .location:
            return await requestLocation()
        }
    }

    // MARK: - Individual Permissions

    private func requestCamera() async -> PermissionStatus {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            return .denied
        }
        return .authorized
    }

    private func requestMicrophone() async -> PermissionStatus {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            return .denied
        }
        return .authorized
    }

    private func requestPhotoLibrary() async -> PermissionStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)

        switch status {
        case .authorized, .limited:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    private func requestNotification() async -> PermissionStatus {
        let settings = await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])

        return settings ? .authorized : .denied
    }

    private func requestLocation() async -> PermissionStatus {
        // 仅在需要时请求，提供场景化说明
        let status = await CLLocationManager().requestAuthorization(
            withDescription: "需要定位权限以根据您的位置推荐附近的内容"
        )

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    // MARK: - Check Status

    private func checkPermission(_ type: PermissionType) async -> PermissionStatus {
        switch type {
        case .camera:
            return await checkCamera()
        case .microphone:
            return await checkMicrophone()
        case .photoLibrary:
            return await checkPhotoLibrary()
        case .notification:
            return await checkNotification()
        case .location:
            return await checkLocation()
        }
    }

    private func checkCamera() async -> PermissionStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    private func checkMicrophone() async -> PermissionStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    private func checkPhotoLibrary() async -> PermissionStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch status {
        case .authorized, .limited:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    private func checkNotification() async -> PermissionStatus {
        let settings = await UNUserNotificationCenter.current()
            .notificationSettings()

        return settings.authorizationStatus == .authorized ? .authorized : .denied
    }

    private func checkLocation() async -> PermissionStatus {
        let status = CLLocationManager().authorizationStatus

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
}

// MARK: - Permission Types

enum PermissionType {
    case camera
    case microphone
    case photoLibrary
    case notification
    case location
}

enum PermissionStatus {
    case authorized
    case denied
    case notDetermined

    var isAuthorized: Bool {
        if case .authorized = self { return true }
        return false
    }

    var isDenied: Bool {
        if case .denied = self { return true }
        return false
    }

    var isNotDetermined: Bool {
        if case .notDetermined = self { return true }
        return false
    }
}

// MARK: - CLLocationManager Extension

extension CLLocationManager {
    func requestAuthorization(withDescription description: String) async -> CLAuthorizationStatus {
        // iOS 14+ 提供场景化说明
        if #available(iOS 14, *) {
            // TODO: 显示说明对话框，然后请求权限
            return authorizationStatus
        } else {
            // iOS 13 及以下直接请求
            return authorizationStatus
        }
    }
}