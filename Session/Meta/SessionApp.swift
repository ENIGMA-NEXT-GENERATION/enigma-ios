// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit
import SessionMessagingKit
import SignalCoreKit
import SessionUIKit

public struct SessionApp {
    // FIXME: Refactor this to be protocol based for unit testing (or even dynamic based on view hierarchy - do want to avoid needing to use the main thread to access them though)
    static let homeViewController: Atomic<HomeVC?> = Atomic(nil)
    static let currentlyOpenConversationViewController: Atomic<ConversationVC?> = Atomic(nil)
    
    static var versionInfo: String {
        let buildNumber: String = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
            .map { " (\($0))" }
            .defaulting(to: "")
        let appVersion: String? = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            .map { "App: \($0)\(buildNumber)" }
        #if DEBUG
        let commitInfo: String? = (Bundle.main.infoDictionary?["GitCommitHash"] as? String).map { "Commit: \($0)" }
        #else
        let commitInfo: String? = nil
        #endif
        
        let versionInfo: [String] = [
            "iOS \(UIDevice.current.systemVersion)",
            appVersion,
            "libSession: \(SessionUtil.libSessionVersion)",
            commitInfo
        ].compactMap { $0 }
        
        return versionInfo.joined(separator: ", ")
    }
    
    // MARK: - View Convenience Methods
    
    public static func presentConversation(for threadId: String, action: ConversationViewModel.Action = .none, animated: Bool) {
        let maybeThreadInfo: (thread: SessionThread, isMessageRequest: Bool)? = Storage.shared.write { db in
            let thread: SessionThread = try SessionThread
                .fetchOrCreate(db, id: threadId, variant: .contact, shouldBeVisible: nil)
            
            return (thread, thread.isMessageRequest(db))
        }
        
        guard
            let variant: SessionThread.Variant = maybeThreadInfo?.thread.variant,
            let isMessageRequest: Bool = maybeThreadInfo?.isMessageRequest
        else { return }
        
        self.presentConversation(
            for: threadId,
            threadVariant: variant,
            isMessageRequest: isMessageRequest,
            action: action,
            focusInteractionInfo: nil,
            animated: animated
        )
    }
    
    public static func presentConversation(
        for threadId: String,
        threadVariant: SessionThread.Variant,
        isMessageRequest: Bool,
        action: ConversationViewModel.Action,
        focusInteractionInfo: Interaction.TimestampInfo?,
        animated: Bool
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.presentConversation(
                    for: threadId,
                    threadVariant: threadVariant,
                    isMessageRequest: isMessageRequest,
                    action: action,
                    focusInteractionInfo: focusInteractionInfo,
                    animated: animated
                )
            }
            return
        }
        
        homeViewController.wrappedValue?.show(
            threadId,
            variant: threadVariant,
            isMessageRequest: isMessageRequest,
            with: action,
            focusedInteractionInfo: focusInteractionInfo,
            animated: animated
        )
    }

    // MARK: - Functions
    
    public static func resetAppData(onReset: (() -> ())? = nil) {
        // This _should_ be wiped out below.
        Logger.error("")
        DDLog.flushLog()
        
        SessionUtil.clearMemoryState()
        Storage.resetAllStorage()
        ProfileManager.resetProfileStorage()
        Attachment.resetAttachmentStorage()
        AppEnvironment.shared.notificationPresenter.clearAllNotifications()

        onReset?()
        exit(0)
    }
    
    public static func showHomeView() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.showHomeView()
            }
            return
        }
        
        let homeViewController: HomeVC = HomeVC()
        let navController: UINavigationController = StyledNavigationController(rootViewController: homeViewController)
        (UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController = navController
    }
}
