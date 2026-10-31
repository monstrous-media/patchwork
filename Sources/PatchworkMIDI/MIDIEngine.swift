import Foundation
import PatchworkCore

#if canImport(CoreMIDI)
import CoreMIDI

public enum MIDIError: Error, CustomStringConvertible {
    case osStatus(OSStatus, String)
    case noEndpoint(String)
    case timeout(String)

    public var description: String {
        switch self {
        case .osStatus(let s, let what): return "\(what) failed (OSStatus \(s))"
        case .noEndpoint(let what): return "no MIDI endpoint matched “\(what)”"
        case .timeout(let what): return "timed out waiting for \(what)"
        }
    }
}

/// Thin CoreMIDI wrapper: enumerates endpoints, sends byte arrays, reassembles incoming SysEx
/// across packets and hands complete F0…F7 messages to `onSysEx`.
public final class MIDIEngine {

    public struct Endpoint: Identifiable, Hashable {
        public let id: MIDIEndpointRef
        public let name: String
        public init(id: MIDIEndpointRef, name: String) { self.id = id; self.name = name }
    }

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var connectedSource: MIDIEndpointRef = 0

    private let lock = NSLock()
    private var sysexBuffer: [UInt8] = []
    private var inSysEx = false

    /// Called on CoreMIDI's receive thread with each complete SysEx message.
    public var onSysEx: (([UInt8]) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onSysEx }
        set { lock.lock(); defer { lock.unlock() }; _onSysEx = newValue }
    }
    private var _onSysEx: (([UInt8]) -> Void)?
    /// Called when the MIDI setup changes (devices plugged/unplugged).
    public var onSetupChanged: (() -> Void)?
    /// Called with the raw bytes of every incoming packet (channel messages included) — for diagnostics.
    public var onRawBytes: (([UInt8]) -> Void)?

    public init(name: String = "M1 Editor") throws {
        var c = MIDIClientRef()
        let s1 = MIDIClientCreateWithBlock(name as CFString, &c) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                self?.onSetupChanged?()
            }
        }
        guard s1 == noErr else { throw MIDIError.osStatus(s1, "MIDIClientCreate") }
        client = c

        var ip = MIDIPortRef()
        let s2 = MIDIInputPortCreateWithBlock(client, "\(name) In" as CFString, &ip) { [weak self] packetList, _ in
            self?.receive(packetList)
        }
        guard s2 == noErr else { throw MIDIError.osStatus(s2, "MIDIInputPortCreate") }
        inputPort = ip

        var op = MIDIPortRef()
        let s3 = MIDIOutputPortCreate(client, "\(name) Out" as CFString, &op)
        guard s3 == noErr else { throw MIDIError.osStatus(s3, "MIDIOutputPortCreate") }
        outputPort = op
    }

    deinit {
        if connectedSource != 0 { MIDIPortDisconnectSource(inputPort, connectedSource) }
        if client != 0 { MIDIClientDispose(client) }
    }

    // MARK: Endpoints

    public static func sources() -> [Endpoint] {
        (0..<MIDIGetNumberOfSources()).map { i in
            let ref = MIDIGetSource(i)
            return Endpoint(id: ref, name: displayName(of: ref))
        }
    }

    public static func destinations() -> [Endpoint] {
        (0..<MIDIGetNumberOfDestinations()).map { i in
            let ref = MIDIGetDestination(i)
            return Endpoint(id: ref, name: displayName(of: ref))
        }
    }

    static func displayName(of ref: MIDIObjectRef) -> String {
        var cf: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(ref, kMIDIPropertyDisplayName, &cf) == noErr, let s = cf?.takeRetainedValue() {
            return s as String
        }
        return "Endpoint \(ref)"
    }

    /// Find an endpoint by 0-based index ("1"), or by case-insensitive substring of its name ("komplete").
    public static func match(_ query: String, in endpoints: [Endpoint]) -> Endpoint? {
        if let i = Int(query), i >= 0, i < endpoints.count { return endpoints[i] }
        let q = query.lowercased()
        return endpoints.first { $0.name.lowercased().contains(q) }
    }

    // MARK: Input

    public func connect(source: MIDIEndpointRef) throws {
        if connectedSource == source { return }
        if connectedSource != 0 { MIDIPortDisconnectSource(inputPort, connectedSource); connectedSource = 0 }
        let s = MIDIPortConnectSource(inputPort, source, nil)
        guard s == noErr else { throw MIDIError.osStatus(s, "MIDIPortConnectSource") }
        connectedSource = source
    }

    public func disconnectSource() {
        if connectedSource != 0 { MIDIPortDisconnectSource(inputPort, connectedSource); connectedSource = 0 }
    }

    private func receive(_ packetList: UnsafePointer<MIDIPacketList>) {
        let dataOffset = MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.data)!
        var completed: [[UInt8]] = []
        var raw: [[UInt8]] = []
        lock.lock()
        for packet in packetList.unsafeSequence() {
            let count = Int(packet.pointee.length)
            let base = UnsafeRawPointer(packet).advanced(by: dataOffset).assumingMemoryBound(to: UInt8.self)
            let bytes = UnsafeBufferPointer(start: base, count: count)
            raw.append(Array(bytes))
            for b in bytes {
                if b == 0xF0 {
                    sysexBuffer = [0xF0]
                    inSysEx = true
                } else if inSysEx {
                    if b == 0xF7 {
                        sysexBuffer.append(b)
                        completed.append(sysexBuffer)
                        sysexBuffer = []
                        inSysEx = false
                    } else if b >= 0xF8 {
                        continue                      // realtime bytes may interleave; ignore
                    } else if b & 0x80 != 0 {
                        sysexBuffer = []              // another status byte: sysex was aborted
                        inSysEx = false
                    } else {
                        sysexBuffer.append(b)
                    }
                }
            }
        }
        let handler = _onSysEx
        let rawHandler = onRawBytes
        lock.unlock()
        if let rawHandler = rawHandler { for r in raw { rawHandler(r) } }
        for m in completed { handler?(m) }
    }

    // MARK: Output

    public func send(_ bytes: [UInt8], to destination: MIDIEndpointRef) throws {
        guard !bytes.isEmpty else { return }
        let listSize = bytes.count + 512
        let raw = UnsafeMutableRawPointer.allocate(byteCount: listSize, alignment: MemoryLayout<MIDIPacketList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: MIDIPacketList.self, capacity: 1)
        guard bytes.count <= Int(UInt16.max) else { throw MIDIError.osStatus(-1, "message too large for one packet") }
        let first = MIDIPacketListInit(list)
        // One packet may carry a whole SysEx message; CoreMIDI/the driver pace it onto the wire.
        let added: UnsafeMutablePointer<MIDIPacket>? = bytes.withUnsafeBufferPointer { buf in
            MIDIPacketListAdd(list, listSize, first, 0, buf.count, buf.baseAddress!)
        }
        guard added != nil else { throw MIDIError.osStatus(-1, "MIDIPacketListAdd (buffer too small)") }
        let s = MIDISend(outputPort, destination, list)
        guard s == noErr else { throw MIDIError.osStatus(s, "MIDISend") }
    }

    /// Send `request` and block until a SysEx message satisfying `matching` arrives or `timeout` elapses.
    /// Intended for the CLI; the app uses `onSysEx` asynchronously.
    public func sendAndWait(_ request: [UInt8], to destination: MIDIEndpointRef, timeout: TimeInterval,
                            matching: @escaping ([UInt8]) -> Bool) throws -> [UInt8]? {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        let previous = onSysEx
        onSysEx = { message in
            previous?(message)
            if matching(message) && box.set(message) { semaphore.signal() }
        }
        defer { onSysEx = previous }
        try send(request, to: destination)
        _ = semaphore.wait(timeout: .now() + timeout)
        return box.get()
    }

    private final class ResultBox {
        private let lock = NSLock()
        private var value: [UInt8]?
        func set(_ v: [UInt8]) -> Bool {
            lock.lock(); defer { lock.unlock() }
            if value != nil { return false }
            value = v
            return true
        }
        func get() -> [UInt8]? {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }
}

#else

// Non-Apple platforms: keep the module compiling so the Core tests can run on Linux CI.
public enum MIDIError: Error { case unavailable }
public final class MIDIEngine {
    public struct Endpoint: Identifiable, Hashable {
        public let id: UInt32; public let name: String
        public init(id: UInt32, name: String) { self.id = id; self.name = name }
    }
    public func connect(source: UInt32) throws { throw MIDIError.unavailable }
    public func send(_ bytes: [UInt8], to destination: UInt32) throws { throw MIDIError.unavailable }
    public var onSysEx: (([UInt8]) -> Void)?
    public var onRawBytes: (([UInt8]) -> Void)?
    public func sendAndWait(_ request: [UInt8], to destination: UInt32, timeout: TimeInterval,
                            matching: @escaping ([UInt8]) -> Bool) throws -> [UInt8]? { throw MIDIError.unavailable }
    public static func match(_ query: String, in endpoints: [Endpoint]) -> Endpoint? { nil }
    public init(name: String = "") throws { throw MIDIError.unavailable }
    public static func sources() -> [Endpoint] { [] }
    public static func destinations() -> [Endpoint] { [] }
}

#endif

// MARK: - Channel-voice helpers (same on every platform; MIDIEndpointRef is UInt32)

extension MIDIEngine {
    public func noteOn(_ note: UInt8, velocity: UInt8, channel: UInt8, to destination: UInt32) throws {
        try send([0x90 | (channel & 0x0F), note & 0x7F, max(1, velocity & 0x7F)], to: destination)
    }

    public func noteOff(_ note: UInt8, channel: UInt8, to destination: UInt32) throws {
        try send([0x80 | (channel & 0x0F), note & 0x7F, 0x40], to: destination)
    }

    public func programChange(_ number: UInt8, channel: UInt8, to destination: UInt32) throws {
        try send([0xC0 | (channel & 0x0F), number & 0x7F], to: destination)
    }

    /// CC 123 (All Notes Off) + CC 120 (All Sound Off).
    public func allNotesOff(channel: UInt8, to destination: UInt32) throws {
        try send([0xB0 | (channel & 0x0F), 123, 0, 0xB0 | (channel & 0x0F), 120, 0], to: destination)
    }
}
