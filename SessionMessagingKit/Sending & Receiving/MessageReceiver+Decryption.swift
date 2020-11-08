import CryptoSwift
import SessionProtocolKit
import SessionUtilitiesKit

internal extension MessageReceiver {

    static func decryptWithSignalProtocol(envelope: SNProtoEnvelope, using transaction: Any) throws -> (plaintext: Data, senderPublicKey: String) {
        let storage = Configuration.shared.storage
        let certificateValidator = Configuration.shared.certificateValidator
        guard let data = envelope.content else { throw Error.noData }
        guard let userPublicKey = storage.getUserPublicKey() else { throw Error.noUserPublicKey }
        let cipher = try SMKSecretSessionCipher(sessionResetImplementation: Configuration.shared.sessionRestorationImplementation,
            sessionStore: storage, preKeyStore: storage, signedPreKeyStore: storage, identityStore: storage)
        let result = try cipher.throwswrapped_decryptMessage(certificateValidator: certificateValidator, cipherTextData: data,
            timestamp: envelope.timestamp, localRecipientId: userPublicKey, localDeviceId: 1, protocolContext: transaction)
        return (result.paddedPayload, result.senderRecipientId)
    }

    static func decryptWithSharedSenderKeys(envelope: SNProtoEnvelope, using transaction: Any) throws -> (plaintext: Data, senderPublicKey: String) {
        // 1. ) Check preconditions
        guard let groupPublicKey = envelope.source, Configuration.shared.storage.isClosedGroup(groupPublicKey) else {
            throw Error.invalidGroupPublicKey
        }
        guard let data = envelope.content else {
            throw Error.noData
        }
        guard let hexEncodedGroupPrivateKey = Configuration.shared.storage.getClosedGroupPrivateKey(for: groupPublicKey) else {
            throw Error.noGroupPrivateKey
        }
        let groupPrivateKey = Data(hex: hexEncodedGroupPrivateKey)
        let groupKeyPair = ECKeyPair(publicKey: Data(hex: groupPublicKey), privateKey: groupPrivateKey)
        // 2. ) Parse the wrapper
        let wrapper = try SNProtoClosedGroupCiphertextMessageWrapper.parseData(data)
        let ivAndCiphertext = wrapper.ciphertext
        let ephemeralPublicKey = wrapper.ephemeralPublicKey
        // 3. ) Decrypt the data inside
        guard let ephemeralSharedSecret = Curve25519.generateSharedSecret(fromPublicKey: ephemeralPublicKey, andKeyPair: groupKeyPair) else {
            throw Error.sharedSecretGenerationFailed
        }
        let salt = "LOKI"
        let symmetricKey = try HMAC(key: salt.bytes, variant: .sha256).authenticate(ephemeralSharedSecret.bytes)
        let closedGroupCiphertextMessageAsData = try AESGCM.decrypt(ivAndCiphertext, with: Data(symmetricKey))
        // 4. ) Parse the closed group ciphertext message
        let closedGroupCiphertextMessage = ClosedGroupCiphertextMessage(_throws_with: closedGroupCiphertextMessageAsData)
        let senderPublicKey = closedGroupCiphertextMessage.senderPublicKey.toHexString()
        guard senderPublicKey != Configuration.shared.storage.getUserPublicKey() else { throw Error.selfSend }
        // 5. ) Use the info inside the closed group ciphertext message to decrypt the actual message content
        let plaintext = try SharedSenderKeys.decrypt(closedGroupCiphertextMessage.ivAndCiphertext, for: groupPublicKey,
            senderPublicKey: senderPublicKey, keyIndex: UInt(closedGroupCiphertextMessage.keyIndex), using: transaction)
        // 6. ) Return
        return (plaintext, senderPublicKey)
    }
}
