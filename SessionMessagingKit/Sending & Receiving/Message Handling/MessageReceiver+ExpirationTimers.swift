// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUIKit
import SessionUtilitiesKit

extension MessageReceiver {
    // TODO: Remove this when disappearing messages V2 is up and running
    internal static func handleExpirationTimerUpdate(
        _ db: Database,
        threadId: String,
        threadVariant: SessionThread.Variant,
        message: ExpirationTimerUpdate
    ) throws {
        guard !Features.useNewDisappearingMessagesConfig else { return }
        guard
            // Only process these for contact and legacy groups (new groups handle it separately)
            (threadVariant == .contact || threadVariant == .legacyGroup),
            let sender: String = message.sender
        else { throw MessageReceiverError.invalidMessage }
        
        // Generate an updated configuration
        //
        // Note: Messages which had been sent during the previous configuration will still
        // use it's settings (so if you enable, send a message and then disable disappearing
        // message then the message you had sent will still disappear)
        let maybeDefaultType: DisappearingMessagesConfiguration.DisappearingMessageType? = {
            switch (threadVariant, threadId == getUserHexEncodedPublicKey(db)) {
                case (.contact, false): return .disappearAfterRead
                case (.legacyGroup, _), (.group, _), (_, true): return .disappearAfterSend
                case (.community, _): return nil // Shouldn't happen
            }
        }()

        guard let defaultType: DisappearingMessagesConfiguration.DisappearingMessageType = maybeDefaultType else { return }
        
        let defaultDuration: DisappearingMessagesConfiguration.DefaultDuration = {
            switch defaultType {
                case .unknown: return .unknown
                case .disappearAfterRead: return .disappearAfterRead
                case .disappearAfterSend: return .disappearAfterSend
            }
        }()
        
        let localConfig: DisappearingMessagesConfiguration = try DisappearingMessagesConfiguration
            .filter(id: threadId)
            .fetchOne(db)
            .defaulting(to: DisappearingMessagesConfiguration.defaultWith(threadId))
        
        let remoteConfig: DisappearingMessagesConfiguration = localConfig.with(
            // If there is no duration then we should disable the expiration timer
            isEnabled: ((message.duration ?? 0) > 0),
            durationSeconds: (
                message.duration.map { TimeInterval($0) } ??
                defaultDuration.seconds
            ),
            type: defaultType
        )
        
        let timestampMs: Int64 = Int64(message.sentTimestamp ?? 0) // Default to `0` if not set
        
        // Only actually make the change if SessionUtil says we can (we always want to insert the info
        // message though)
        let canPerformChange: Bool = SessionUtil.canPerformChange(
            db,
            threadId: threadId,
            targetConfig: {
                switch threadVariant {
                    case .contact:
                        let currentUserPublicKey: String = getUserHexEncodedPublicKey(db)
                        
                        return (threadId == currentUserPublicKey ? .userProfile : .contacts)
                        
                    default: return .userGroups
                }
            }(),
            changeTimestampMs: timestampMs
        )
        
        // Only update libSession if we can perform the change
        if canPerformChange {
            // Contacts & legacy closed groups need to update the SessionUtil
            switch threadVariant {
                case .contact:
                    try SessionUtil
                        .update(
                            db,
                            sessionId: threadId,
                            disappearingMessagesConfig: remoteConfig
                        )
                
                case .legacyGroup:
                    try SessionUtil
                        .update(
                            db,
                            groupPublicKey: threadId,
                            disappearingConfig: remoteConfig
                        )
                    
                default: break
            }
        }
        
        // Only save the updated config if we can perform the change
        if canPerformChange {
            // Finally save the changes to the DisappearingMessagesConfiguration (If it's a duplicate
            // then the interaction unique constraint will prevent the code from getting here)
            try remoteConfig.save(db)
        }
        
        // Add an info message for the user
        let currentUserPublicKey: String = getUserHexEncodedPublicKey(db)
        _ = try Interaction(
            serverHash: nil, // Intentionally null so sync messages are seen as duplicates
            threadId: threadId,
            authorId: sender,
            variant: .infoDisappearingMessagesUpdate,
            body: remoteConfig.messageInfoString(
                threadVariant: threadVariant,
                senderName: (sender != currentUserPublicKey ? Profile.displayName(db, id: sender) : nil),
                isPreviousOff: false
            ),
            timestampMs: timestampMs,
            wasRead: SessionUtil.timestampAlreadyRead(
                threadId: threadId,
                threadVariant: threadVariant,
                timestampMs: (timestampMs * 1000),
                userPublicKey: currentUserPublicKey,
                openGroup: nil
            )
        ).inserted(db)
    }
    
    public static func updateContactDisappearingMessagesVersionIfNeeded(
        _ db: Database,
        messageVariant: Message.Variant?,
        contactId: String?,
        version: FeatureVersion?
    ) {
        guard
            let messageVariant: Message.Variant = messageVariant,
            let contactId: String = contactId,
            let version: FeatureVersion = version
        else {
            return
        }
        
        guard [ .visibleMessage, .expirationTimerUpdate ].contains(messageVariant) else { return }
        
        _ = try? Contact
            .filter(id: contactId)
            .updateAllAndConfig(
                db,
                Contact.Columns.lastKnownClientVersion.set(to: version)
            )
        
        guard Features.useNewDisappearingMessagesConfig else { return }
        
        if contactId == getUserHexEncodedPublicKey(db) {
            switch version {
                case .legacyDisappearingMessages:
                    TopBannerController.show(warning: .outdatedUserConfig)
                case .newDisappearingMessages:
                    TopBannerController.hide()
            }
        }
        
    }
    
    internal static func handleExpirationTimerUpdate(
        _ db: Database,
        threadId: String,
        threadVariant: SessionThread.Variant,
        message: ExpirationTimerUpdate,
        proto: SNProtoContent
    ) throws {
        guard 
            let sender: String = message.sender,
            let timestampMs: UInt64 = message.sentTimestamp,
            Features.useNewDisappearingMessagesConfig
        else {
            return
        }
        
        let localConfig: DisappearingMessagesConfiguration = try DisappearingMessagesConfiguration
            .fetchOne(db, id: threadId)
            .defaulting(to: DisappearingMessagesConfiguration.defaultWith(threadId))
        
        let durationSeconds: TimeInterval = (proto.hasExpirationTimer ? TimeInterval(proto.expirationTimer) : 0)
        let disappearingType: DisappearingMessagesConfiguration.DisappearingMessageType? = (proto.hasExpirationType ?
            .init(protoType: proto.expirationType) :
            .unknown
        )
        let remoteConfig: DisappearingMessagesConfiguration = localConfig.with(
            isEnabled: (durationSeconds != 0),
            durationSeconds: durationSeconds,
            type: disappearingType
        )
        
        switch threadVariant {
            case .legacyGroup:
                if localConfig != remoteConfig {
                    _ = try remoteConfig.save(db)
                    
                    try SessionUtil
                        .update(
                            db,
                            groupPublicKey: threadId,
                            disappearingConfig: remoteConfig
                        )
                }
                fallthrough
            case .contact:
                _ = try DisappearingMessagesConfiguration.insertControlMessage(
                    db,
                    threadId: threadId,
                    threadVariant: threadVariant,
                    authorId: sender,
                    timestampMs: Int64(timestampMs),
                    serverHash: message.serverHash,
                    updatedConfiguration: remoteConfig,
                    isPreviousOff: !localConfig.isEnabled
                )
            default:
                 return
        }
    }
}
