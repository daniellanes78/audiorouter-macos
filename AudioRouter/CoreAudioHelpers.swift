import Foundation
import AppKit
import CoreAudio

// MARK: - Erros

struct CAError: LocalizedError {
    let status: OSStatus
    let context: String
    var errorDescription: String? { "\(context) falhou (OSStatus \(status))" }
}

@inline(__always)
func check(_ status: OSStatus, _ context: String) throws {
    guard status == noErr else { throw CAError(status: status, context: context) }
}

// MARK: - Leitura de propriedades

let kSystemObject = AudioObjectID(kAudioObjectSystemObject)
let kUnknownObject = AudioObjectID(kAudioObjectUnknown)

func propAddress(_ selector: AudioObjectPropertySelector,
                 _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func readValue<T>(_ obj: AudioObjectID,
                  _ selector: AudioObjectPropertySelector,
                  scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                  default value: T) throws -> T {
    var addr = propAddress(selector, scope)
    var size = UInt32(MemoryLayout<T>.size)
    var v = value
    try check(AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &v), "Get \(selector)")
    return v
}

func readIDs(_ obj: AudioObjectID,
             _ selector: AudioObjectPropertySelector,
             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [AudioObjectID] {
    var addr = propAddress(selector, scope)
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(obj, &addr, 0, nil, &size), "GetSize \(selector)")
    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    guard count > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: count)
    try check(AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &ids), "Get \(selector)")
    return ids
}

func readString(_ obj: AudioObjectID,
                _ selector: AudioObjectPropertySelector,
                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> String {
    var addr = propAddress(selector, scope)
    var ref: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    try check(AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &ref), "Get \(selector)")
    guard let s = ref?.takeRetainedValue() else { return "" }
    return s as String
}

// MARK: - Dispositivos de saída

struct OutputDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
}

func listOutputDevices() -> [OutputDevice] {
    let ids = (try? readIDs(kSystemObject, kAudioHardwarePropertyDevices)) ?? []
    return ids.compactMap { dev in
        let transport: UInt32 = (try? readValue(dev, kAudioDevicePropertyTransportType, default: UInt32(0))) ?? 0
        if transport == UInt32(kAudioDeviceTransportTypeAggregate) { return nil }

        let outStreams = (try? readIDs(dev, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)) ?? []
        guard !outStreams.isEmpty else { return nil }

        guard let uid = try? readString(dev, kAudioDevicePropertyDeviceUID),
              let name = try? readString(dev, kAudioObjectPropertyName),
              !uid.isEmpty else { return nil }
        return OutputDevice(id: dev, uid: uid, name: name)
    }
}

func defaultOutputDeviceID() -> AudioObjectID {
    (try? readValue(kSystemObject, kAudioHardwarePropertyDefaultOutputDevice, default: kUnknownObject)) ?? kUnknownObject
}

// MARK: - Processos com áudio

struct AudioProcess: Hashable {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String
    let isPlaying: Bool

    /// Agrupa processos auxiliares (ex.: Chrome Helper) sob a mesma chave
    var groupKey: String { bundleID.isEmpty ? "pid:\(pid)" : bundleID }
}

func listAudioProcesses() -> [AudioProcess] {
    let ids = (try? readIDs(kSystemObject, kAudioHardwarePropertyProcessObjectList)) ?? []
    let me = getpid()
    return ids.compactMap { obj in
        let pid: pid_t = (try? readValue(obj, kAudioProcessPropertyPID, default: pid_t(-1))) ?? -1
        guard pid > 0, pid != me else { return nil }
        let bundle = (try? readString(obj, kAudioProcessPropertyBundleID)) ?? ""
        let running: UInt32 = (try? readValue(obj, kAudioProcessPropertyIsRunningOutput, default: UInt32(0))) ?? 0
        return AudioProcess(objectID: obj, pid: pid, bundleID: bundle, isPlaying: running != 0)
    }
}

/// Nome amigável para o grupo (resolve helpers para o app pai quando possível)
func friendlyName(for process: AudioProcess) -> String {
    let b = process.bundleID
    let known: [String: String] = [
        "com.apple.WebKit.GPU": "Safari / WebKit",
        "com.apple.WebKit.WebContent": "Safari / WebKit",
        "com.google.Chrome.helper": "Google Chrome",
        "com.microsoft.edgemac.helper": "Microsoft Edge",
        "com.brave.Browser.helper": "Brave",
    ]
    if let n = known[b] { return n }

    if b.hasSuffix(".helper") {
        let parent = String(b.dropLast(".helper".count))
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: parent).first,
           let n = app.localizedName { return n }
    }
    if let app = NSRunningApplication(processIdentifier: process.pid), let n = app.localizedName { return n }
    if !b.isEmpty,
       let app = NSRunningApplication.runningApplications(withBundleIdentifier: b).first,
       let n = app.localizedName { return n }
    return b.isEmpty ? "PID \(process.pid)" : b
}
