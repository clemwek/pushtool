import Foundation

@objcMembers
public class Pusher: NSObject {
    
    // MARK: Public Type Methods
    
    public class func connect(withIdentity identity: NWIdentityRef,
                              environment: NWEnvironment) throws -> Pusher {
        let pusher = Pusher()
        
        try pusher.connect(withIdentity: identity,
                           environment: environment)
        
        return pusher
    }
    
    public class func connect(withPKCS12Data data: Data,
                              password: String,
                              environment: NWEnvironment) throws -> Pusher {
        let pusher = Pusher()
        
        try pusher.connect(withPKCS12Data: data,
                           password: password,
                           environment: environment)
        
        return pusher
    }
    
    // MARK: Public Instance Properties
    
    public var connection: NWSSLConnection?
    
    // MARK: Public Instance Methods
    
    public func connect(withIdentity identity: NWIdentityRef,
                        environment: NWEnvironment) throws {
        self.connection?.disconnect()
        
        var environment = environment
        
        if environment == .auto {
            let options = SecTools.environmentOptions(forIdentity: identity)

            environment = options != .production ? .sandbox : .production
        }
        
        let host = (environment == .sandbox) ? sandboxPushHost : pushHost
        
        if let connection = NWSSLConnection(host: host,
                                            port: pushPort,
                                            identity: identity) {
            try connection.connect()
            
            self.connection = connection
        }
    }
    
    public func connect(withPKCS12Data data: Data,
                        password: String,
                        environment: NWEnvironment) throws {
        let identity: NWIdentityRef = try SecTools.identities(withPKCS12Data: data,
                                                              password: password) as NWIdentityRef
        
        try connect(withIdentity: identity,
                    environment: environment)
    }
    
    public func disconnect() {
        self.connection?.disconnect()
        self.connection = nil
    }
    
    public func pushNotification(_ notification: NWNotification,
                                 type: NWNotificationType) throws {
        let data = notification.data(with: .type2)
        
        guard let connection = self.connection
            else { return  }
        
        var length: UInt = 0
        
        try connection.write(data,
                             length: &length)
        
        if length != data.count {
            throw ErrorUtil.errorWithErrorCode(.pushWriteFail,
                                               reason: Int(length))
        }
    }
    
    public func pushPayload(_ payload: String,
                            token: String,
                            identifier: UInt) throws {
        let notification = NWNotification(payload: payload,
                                          token: token,
                                          identifier: identifier,
                                          expiration: nil,
                                          priority: 0)
        
        try self.pushNotification(notification,
                                  type: .type2)
    }
    
    public func readFailedIdentifier(_ identifier: UnsafeMutablePointer<Int>,
                                     apnError: NSErrorPointer) throws {
        
        identifier.pointee = 0
        
        let dataLength = UInt8.bitWidth * 2 + UInt32.bitWidth
        
        let data = NSMutableData(length: dataLength)
        
        try self.connection?.read(data,
                                  length: identifier)
        
        var command: UInt8 = 0
        
        data?.getBytes(&command,
                       range: NSMakeRange(0, 1))
        
        if command != 8 {
            throw ErrorUtil.errorWithErrorCode(.pushResponseCommand,
                                                 reason: Int(command))
        }
        
        var status: UInt8 = 0
        
        data?.getBytes(&status,
                       range: NSMakeRange(1, 1))
        
        var ID: UInt32 = 0
        
        data?.getBytes(&ID,
                       range: NSMakeRange(2, 4))
        
        identifier.pointee = Int(ID.bigEndian)
        
        apnError?.pointee = error(for: Int(status))
    }
    
    public func reconnect() throws {
        try self.connection?.connect()
    }
    
    // MARK: Private Instance Properties
    
    private let pushHost = "gateway.push.apple.com"
    private let pushPort: UInt = 2195
    private let sandboxPushHost = "gateway.sandbox.push.apple.com"
    
    // MARK: Private Instance Methods
    
    private func error(for status: Int) -> NSError {
        switch status {
        case 1:
            return ErrorUtil.errorWithErrorCode(.apnProcessing,
                                                reason: status)
            
        case 2:
            return ErrorUtil.errorWithErrorCode(.apnMissingDeviceToken,
                                                reason: status)
            
        case 3:
            return ErrorUtil.errorWithErrorCode(.apnMissingTopic,
                                                reason: status)
            
        case 4:
            return ErrorUtil.errorWithErrorCode(.apnMissingPayload,
                                                reason: status)
            
        case 5:
            return ErrorUtil.errorWithErrorCode(.apnInvalidTokenSize,
                                                reason: status)
            
        case 6:
            return ErrorUtil.errorWithErrorCode(.apnInvalidTopicSize,
                                                reason: status)
            
        case 7:
            return ErrorUtil.errorWithErrorCode(.apnInvalidPayloadSize,
                                                reason: status)
            
        case 8:
            return ErrorUtil.errorWithErrorCode(.apnInvalidTokenContent,
                                                reason: status)
            
        case 10:
            return ErrorUtil.errorWithErrorCode(.apnShutdown,
                                                reason: status)
            
        default:
            return ErrorUtil.errorWithErrorCode(.apnUnknownErrorCode,
                                                reason: status)
        }
    }
}