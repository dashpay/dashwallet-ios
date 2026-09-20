//
//  BrowserLoginPeripheral.swift
//  DashWallet
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import CoreBluetooth
import Foundation
import Security

/// The Bluetooth LE peripheral a browser connects to for a login key.
///
/// Owns the `CBPeripheralManager`, publishes the
/// `BrowserLoginBleProtocol` service, reassembles the browser's
/// request write, and serves the status and response characteristics.
/// Everything the UI needs is pushed through `@Published` state on the
/// main actor; the flow decisions (confirm, register, deliver) stay in
/// the view model so this class knows nothing about identities.
@MainActor
final class BrowserLoginPeripheral: NSObject, ObservableObject {
    enum RadioState: Equatable {
        case unknown
        case unauthorized
        case poweredOff
        case unsupported
        case poweredOn
        case advertising
    }

    @Published private(set) var radioState: RadioState = .unknown
    @Published private(set) var status: BrowserLoginBleProtocol.Status = .idle
    @Published private(set) var lastError: String?
    /// Whether the browser has confirmed it read the response. Until it does,
    /// tearing the service down would wipe `responseBytes` and orphan a key
    /// that is already registered on the identity.
    @Published private(set) var responseWasAcknowledged = false

    /// Called on the main actor with each complete request write.
    var onRequest: ((Data) -> Void)?

    private var manager: CBPeripheralManager?
    private var service: CBMutableService?
    private var statusCharacteristic: CBMutableCharacteristic?
    private var responseCharacteristic: CBMutableCharacteristic?
    private var sessionCharacteristic: CBMutableCharacteristic?
    private var responseBytes = Data()
    /// The nonce this advertising session commits to before it can see any
    /// request, and the commitment it serves until a request is accepted.
    /// Together they are what keeps the pairing code out of a relay's reach.
    private(set) var pairingNonce = Data()
    private var pairingCommitment = Data()
    private var pairingNonceIsRevealed = false
    /// The latest status CoreBluetooth refused to queue. Resent from
    /// `peripheralManagerIsReady(toUpdateSubscribers:)`; a browser that
    /// relies on notifications would otherwise miss the transition.
    private var undeliveredStatus: BrowserLoginBleProtocol.Status?
    /// Whether `start()` was called and the service should go up as
    /// soon as the radio reports powered on.
    private var wantsAdvertising = false

    private let localName: String

    init(localName: String) {
        self.localName = localName
        super.init()
    }

    /// Bring the radio up and advertise the service once it is ready.
    func start() {
        guard prepareSession() else { return }
        if manager == nil {
            // A nil queue delivers delegate callbacks on the main queue,
            // which is what the @MainActor isolation of this class expects.
            manager = CBPeripheralManager(delegate: self, queue: nil)
        } else {
            publishIfReady()
        }
    }

    /// Everything `start()` does before it touches the radio: draw this
    /// session's pairing nonce and the commitment the browser reads before it
    /// writes anything. Fixing the nonce here — with no request in hand — is
    /// what stops either side from choosing its half of the pairing code
    /// after seeing the other's.
    @discardableResult
    func prepareSession() -> Bool {
        wantsAdvertising = true
        lastError = nil
        responseWasAcknowledged = false
        pairingNonceIsRevealed = false
        do {
            pairingNonce = try Self.randomBytes(BrowserLoginBleProtocol.pairingNonceLength)
            pairingCommitment = try BrowserLoginBleProtocol.pairingCommitment(nonce: pairingNonce)
            return true
        } catch {
            lastError = "Could not start the Bluetooth session: \(error.localizedDescription)"
            wantsAdvertising = false
            return false
        }
    }

    /// Stop advertising and tear the service down. The response bytes
    /// are wiped so a later connection cannot read a stale key.
    func stop() {
        wantsAdvertising = false
        // The protocol defines `.idle` as "advertising, no request received
        // yet". `decline()` and `reset()` stop this same peripheral before a
        // later `startAdvertising()`, so without this the next session would
        // serve the previous terminal status.
        status = .idle
        undeliveredStatus = nil
        responseWasAcknowledged = false
        pairingNonceIsRevealed = false
        pairingNonce = Data()
        pairingCommitment = Data()
        responseBytes.resetBytes(in: 0..<responseBytes.count)
        responseBytes = Data()
        manager?.stopAdvertising()
        manager?.removeAllServices()
        service = nil
        statusCharacteristic = nil
        responseCharacteristic = nil
        sessionCharacteristic = nil
        if radioState == .advertising {
            radioState = .poweredOn
        }
    }

    /// Update the status byte and notify a subscribed browser.
    func setStatus(_ status: BrowserLoginBleProtocol.Status) {
        self.status = status
        guard let manager, let statusCharacteristic else { return }
        // `false` means the notification was not queued. The readable
        // characteristic still carries the value for a polling client, but a
        // browser waiting on a notification needs the resend.
        let queued = manager.updateValue(
            Data([status.rawValue]),
            for: statusCharacteristic,
            onSubscribedCentrals: nil
        )
        undeliveredStatus = queued ? nil : status
    }

    /// Serve the nonce behind the commitment. Called once the request the
    /// pairing code covers has been accepted — never before, or the code
    /// stops binding the session.
    func revealPairingNonce() {
        pairingNonceIsRevealed = true
    }

    /// Expose the encrypted response and flip the status to `ready`.
    func deliver(response: Data) {
        responseBytes = response
        responseWasAcknowledged = false
        setStatus(.ready)
    }

    private func publishIfReady() {
        guard wantsAdvertising, let manager, manager.state == .poweredOn, service == nil else { return }

        let request = CBMutableCharacteristic(
            type: BrowserLoginBleProtocol.requestCharacteristicUUID,
            properties: [.write],
            value: nil,
            permissions: [.writeable]
        )
        let statusChar = CBMutableCharacteristic(
            type: BrowserLoginBleProtocol.statusCharacteristicUUID,
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )
        let response = CBMutableCharacteristic(
            type: BrowserLoginBleProtocol.responseCharacteristicUUID,
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )
        let session = CBMutableCharacteristic(
            type: BrowserLoginBleProtocol.sessionCharacteristicUUID,
            properties: [.read, .write],
            value: nil,
            permissions: [.readable, .writeable]
        )
        let service = CBMutableService(type: BrowserLoginBleProtocol.serviceUUID, primary: true)
        service.characteristics = [request, statusChar, response, session]

        self.service = service
        self.statusCharacteristic = statusChar
        self.responseCharacteristic = response
        self.sessionCharacteristic = session
        manager.add(service)
    }

    private func handle(writes requests: [CBATTRequest]) {
        guard let manager, let first = requests.first else { return }
        // A write longer than the ATT MTU arrives as several prepared
        // writes with increasing offsets, delivered together. Stitch
        // them back into one buffer before parsing.
        let target = first.characteristic.uuid
        var assembled = Data()
        for request in requests.sorted(by: { $0.offset < $1.offset }) {
            guard request.characteristic.uuid == target,
                  target == BrowserLoginBleProtocol.requestCharacteristicUUID
                    || target == BrowserLoginBleProtocol.sessionCharacteristicUUID else {
                manager.respond(to: first, withResult: .writeNotPermitted)
                return
            }
            guard request.offset == assembled.count, let chunk = request.value else {
                manager.respond(to: first, withResult: .invalidOffset)
                return
            }
            assembled.append(chunk)
        }
        manager.respond(to: first, withResult: .success)
        if target == BrowserLoginBleProtocol.sessionCharacteristicUUID {
            acknowledge(sessionWrite: assembled)
        } else {
            onRequest?(assembled)
        }
    }

    /// The only thing the browser may write to the session characteristic:
    /// "I have the response". Anything else is ignored — the characteristic
    /// is unauthenticated, so a write is a hint, never a command.
    func acknowledge(sessionWrite bytes: Data) {
        guard !responseBytes.isEmpty,
              let value = try? BrowserLoginBleProtocol.parseSession(bytes),
              value.stage == .received else { return }
        responseWasAcknowledged = true
    }

    private func handle(read request: CBATTRequest) {
        guard let manager else { return }
        let bytes: Data
        switch request.characteristic.uuid {
        case BrowserLoginBleProtocol.statusCharacteristicUUID:
            bytes = Data([status.rawValue])
        case BrowserLoginBleProtocol.responseCharacteristicUUID:
            bytes = responseBytes
        case BrowserLoginBleProtocol.sessionCharacteristicUUID:
            bytes = sessionValueBytes()
        default:
            manager.respond(to: request, withResult: .readNotPermitted)
            return
        }
        guard request.offset <= bytes.count else {
            manager.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = bytes.subdata(in: request.offset..<bytes.count)
        manager.respond(to: request, withResult: .success)
    }

    /// The commitment until a request has been accepted, the nonce after.
    /// Serving the nonce any earlier would let a relay pick the browser's
    /// side of the pairing code once it knows the wallet's.
    func sessionValueBytes() -> Data {
        guard !pairingNonce.isEmpty else { return Data() }
        let value = BrowserLoginBleProtocol.SessionValue(
            stage: pairingNonceIsRevealed ? .reveal : .commitment,
            payload: pairingNonceIsRevealed ? pairingNonce : pairingCommitment
        )
        return (try? BrowserLoginBleProtocol.serializeSession(value)) ?? Data()
    }

    private static func randomBytes(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return Data(bytes)
    }
}

// The manager was created with a nil queue, so CoreBluetooth calls these
// on the main queue. The `@preconcurrency` conformance keeps the methods
// main-actor isolated (checked at runtime) so the non-Sendable manager
// and ATT requests can be used in place.
extension BrowserLoginPeripheral: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            radioState = .poweredOn
            publishIfReady()
        case .poweredOff:
            radioState = .poweredOff
        case .unauthorized:
            radioState = .unauthorized
        case .unsupported:
            radioState = .unsupported
        default:
            radioState = .unknown
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?
    ) {
        if let error {
            lastError = "Could not publish the Bluetooth service: \(error.localizedDescription)"
            return
        }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BrowserLoginBleProtocol.serviceUUID],
            CBAdvertisementDataLocalNameKey: localName,
        ])
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard let undeliveredStatus, let statusCharacteristic else { return }
        let queued = peripheral.updateValue(
            Data([undeliveredStatus.rawValue]),
            for: statusCharacteristic,
            onSubscribedCentrals: nil
        )
        if queued {
            self.undeliveredStatus = nil
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            lastError = "Could not start advertising: \(error.localizedDescription)"
        } else {
            radioState = .advertising
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        handle(read: request)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        handle(writes: requests)
    }
}
