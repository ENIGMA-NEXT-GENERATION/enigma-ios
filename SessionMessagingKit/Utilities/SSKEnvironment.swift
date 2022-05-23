// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

@objc
public class SSKEnvironment: NSObject {
    @objc public let primaryStorage: OWSPrimaryStorage
    public let reachabilityManager: SSKReachabilityManager
    
    // Note: This property is configured after Environment is created.
    public let notificationsManager: Atomic<NotificationsProtocol?> = Atomic(nil)
    
    @objc public static var shared: SSKEnvironment!
    
    public var isComplete: Bool {
        (notificationsManager.wrappedValue != nil)
    }
    
    public var objectReadWriteConnection: YapDatabaseConnection
    public var sessionStoreDBConnection: YapDatabaseConnection
    public var migrationDBConnection: YapDatabaseConnection
    public var analyticsDBConnection: YapDatabaseConnection
    
    // MARK: - Initialization
    
    @objc public init(
        primaryStorage: OWSPrimaryStorage,
        reachabilityManager: SSKReachabilityManager
    ) {
        self.primaryStorage = primaryStorage
        self.reachabilityManager = reachabilityManager
        
        self.objectReadWriteConnection = primaryStorage.newDatabaseConnection()
        self.sessionStoreDBConnection = primaryStorage.newDatabaseConnection()
        self.migrationDBConnection = primaryStorage.newDatabaseConnection()
        self.analyticsDBConnection = primaryStorage.newDatabaseConnection()
        
        super.init()
        
        if SSKEnvironment.shared == nil {
            SSKEnvironment.shared = self
        }
    }
    
    // MARK: - Functions
    
    public static func clearSharedForTests() {
        shared = nil
    }
}
