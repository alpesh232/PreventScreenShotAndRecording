//
//  ScreenshotProtectionManager.swift
//  RetailApp
//
//  Created by Alpesh Desai on 23/02/26.
//

import UIKit

final class ScreenSecurityManager {

    struct Constants {
        static let pedding: CGFloat = 20
        static let backgroungColor = UIColor.black
        static let titleTextColor = UIColor.white
        static var prohibitedMessage = "Due to security reasons, taking screenshots/screen recording is prohibited"
    }

    static let shared = ScreenSecurityManager()
    private var window: UIWindow? {
        // Prefer key window from the foreground active scene
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }

        if let keyWindow = scenes
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            return keyWindow
        }

        // Fallback: any visible window in the first foreground scene
        if let anyVisible = scenes
            .flatMap({ $0.windows })
            .first(where: { !$0.isHidden }) {
            return anyVisible
        }

        // Last resort: any window from any scene
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first
    }
    
    public var isScreenShotEnabled = false {
        didSet {
            if isScreenShotEnabled {
                disableScreenshotProtection()
                stopScreenCaptureMonitoring()
            } else {
                guard let window  = window else { return }
                ScreenSecurityManager.shared.enableScreenshotProtection(for: window)
                ScreenSecurityManager.shared.startScreenCaptureMonitoring()
            }
        }
    }
    private weak var protectedWindow: UIWindow?
    private var secureTextField: UITextField?
    private var overlayWindow: UIWindow?
    private weak var originalSuperLayer: CALayer?
    private var isObservingCaptureChanges = false

    func enableScreenshotProtection(for window: UIWindow) {
        guard secureTextField == nil else { return }

        let field = UITextField()
        field.isSecureTextEntry = true

        let protectionView = UIView(frame: CGRect(x: 0, y: 0,
                                                  width: field.frame.size.width,
                                                  height: field.frame.size.height))
        protectionView.backgroundColor = Constants.backgroungColor

        let screenBounds = window.windowScene?.screen.bounds ?? window.bounds
        let label = UILabel(frame: CGRect(x: Constants.pedding, y: 0,
                                          width: screenBounds.width - (2 * Constants.pedding),
                                          height: screenBounds.height))
        label.text = Constants.prohibitedMessage
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = Constants.titleTextColor
        protectionView.addSubview(label)

        field.leftView = protectionView
        field.leftViewMode = .always

        window.addSubview(field)
        self.protectedWindow = window
        self.secureTextField = field

        originalSuperLayer = window.layer.superlayer
        originalSuperLayer?.addSublayer(field.layer)
        field.layer.sublayers?.last?.addSublayer(window.layer)
    }

    func disableScreenshotProtection() {
        guard let field = secureTextField, let window = self.window else { return }
        originalSuperLayer?.addSublayer(window.layer)
        field.layer.removeFromSuperlayer()
        field.removeFromSuperview()
        secureTextField = nil
        protectedWindow = nil
    }

    func startScreenCaptureMonitoring() {
        guard !isObservingCaptureChanges else { return }
        isObservingCaptureChanges = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenCaptureChanged),
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )
        checkScreenRecording()
    }

    func stopScreenCaptureMonitoring() {
        hideOverlay()
        isObservingCaptureChanges = false
        NotificationCenter.default.removeObserver(self, name: UIScreen.capturedDidChangeNotification, object: nil)
    }

    @objc private func screenCaptureChanged() {
        checkScreenRecording()
    }

    private func checkScreenRecording() {
        // Prefer a screen from the protected window, then overlay window, then any connected windowScene
        let screen: UIScreen? = protectedWindow?.windowScene?.screen
            ?? overlayWindow?.windowScene?.screen
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.screen
        if screen?.isCaptured == true {
            showOverlay()
        } else {
            hideOverlay()
        }
    }

    private func showOverlay() {
        guard overlayWindow == nil else { return }

        let work = { [weak self] in
            guard let self = self,
                  let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first else { return }

            let window = UIWindow(windowScene: windowScene)
            let screenBounds = windowScene.screen.bounds
            window.frame = screenBounds
            window.windowLevel = .alert + 1
            window.backgroundColor = Constants.backgroungColor

            let vc = UIViewController()
            vc.view.backgroundColor = Constants.backgroungColor
            window.rootViewController = vc

            window.isHidden = false
            self.overlayWindow = window
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func hideOverlay() {
        let work = { [weak self] in
            guard let self = self else { return }
            self.overlayWindow?.isHidden = true
            self.overlayWindow?.rootViewController = nil
            self.overlayWindow = nil
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

extension UIApplication {
    var firstKeyWindow: UIWindow? {
        // 1. Get connected scenes and filter for UIWindowScene
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        
        // 2. Filter for foreground active scenes
        let activeScene = windowScenes
            .filter { $0.activationState == .foregroundActive }
        
        // 3. Get the first active scene and its key window
        let keyWindow = activeScene.first?.keyWindow
        return keyWindow
    }
}
