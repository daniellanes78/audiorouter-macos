import Foundation
import CoreAudio

/// Captura o áudio de um ou mais processos (Process Tap, macOS 14.2+),
/// silencia na saída original e reproduz no dispositivo escolhido.
///
/// Fluxo: CATapDescription -> AudioHardwareCreateProcessTap
///        -> Aggregate Device (sub-device = saída destino + tap)
///        -> IOProc copia entrada (tap) -> saída (destino)
final class ProcessTapRouter {
    let processObjectIDs: [AudioObjectID]
    let outputUID: String

    private var tapID = kUnknownObject
    private var aggregateID = kUnknownObject
    private var ioProcID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "br.com.daniel.AudioRouter.io", qos: .userInteractive)

    init(processObjectIDs: [AudioObjectID], outputUID: String) {
        self.processObjectIDs = processObjectIDs
        self.outputUID = outputUID
    }

    deinit { stop() }

    func start() throws {
        // 1) Tap dos processos, mutando a saída original enquanto capturado
        let desc = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        desc.uuid = UUID()
        desc.muteBehavior = .mutedWhenTapped

        var tap = kUnknownObject
        try check(AudioHardwareCreateProcessTap(desc, &tap), "AudioHardwareCreateProcessTap")
        tapID = tap
        let tapUID = desc.uuid.uuidString

        // 2) Aggregate device privado: saída destino como clock + tap como entrada
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AudioRouter-\(tapUID.prefix(8))",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapDriftCompensationKey: true,
                 kAudioSubTapUIDKey: tapUID]
            ],
        ]

        var agg = kUnknownObject
        try check(AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &agg), "AudioHardwareCreateAggregateDevice")
        aggregateID = agg

        // 3) IOProc: copia o tap para a saída
        var procID: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, agg, queue) { _, inInput, _, outOutput, _ in
            ProcessTapRouter.render(input: inInput, output: outOutput)
        }, "AudioDeviceCreateIOProcIDWithBlock")
        ioProcID = procID

        // 4) Desliga streams de entrada do sub-device (ex.: microfone do AirPods),
        //    mantendo só o tap (último stream). Evita o fone cair para modo HFP.
        if let procID { disableNonTapInputStreams(procID: procID) }

        try check(AudioDeviceStart(agg, procID), "AudioDeviceStart")
    }

    func stop() {
        if aggregateID != kUnknownObject {
            if let p = ioProcID {
                AudioDeviceStop(aggregateID, p)
                AudioDeviceDestroyIOProcID(aggregateID, p)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kUnknownObject {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = kUnknownObject
        tapID = kUnknownObject
    }

    // MARK: - Stream usage

    private func disableNonTapInputStreams(procID: AudioDeviceIOProcID) {
        guard let inStreams = try? readIDs(aggregateID, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput),
              inStreams.count > 1 else { return }

        // struct AudioHardwareIOProcStreamUsage { void* mIOProc; UInt32 mNumberStreams; UInt32 mStreamIsOn[n]; }
        let n = inStreams.count
        let ptrSize = MemoryLayout<UnsafeMutableRawPointer>.size
        let headerSize = ptrSize + MemoryLayout<UInt32>.size
        let size = headerSize + MemoryLayout<UInt32>.size * n
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { raw.deallocate() }

        raw.storeBytes(of: unsafeBitCast(procID, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        raw.storeBytes(of: UInt32(n), toByteOffset: ptrSize, as: UInt32.self)
        for i in 0..<n {
            raw.storeBytes(of: UInt32(i == n - 1 ? 1 : 0),
                           toByteOffset: headerSize + i * MemoryLayout<UInt32>.size,
                           as: UInt32.self)
        }

        var addr = propAddress(kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput)
        let st = AudioObjectSetPropertyData(aggregateID, &addr, 0, nil, UInt32(size), raw)
        if st != noErr { NSLog("AudioRouter: IOProcStreamUsage falhou (\(st))") }
    }

    // MARK: - Render (thread de áudio, sem alocação)

    private static func render(input: UnsafePointer<AudioBufferList>,
                               output: UnsafeMutablePointer<AudioBufferList>) {
        let outList = UnsafeMutableAudioBufferListPointer(output)
        for b in outList {
            if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) }
        }

        // Tap = último buffer de entrada com dados (Float32 intercalado)
        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        var tap: AudioBuffer?
        for b in inList where b.mData != nil && b.mNumberChannels > 0 && b.mDataByteSize > 0 {
            tap = b
        }
        guard let src = tap, let s = src.mData?.assumingMemoryBound(to: Float.self) else { return }
        let inCh = Int(src.mNumberChannels)
        let inFrames = Int(src.mDataByteSize) / (MemoryLayout<Float>.size * inCh)

        for b in outList {
            guard b.mNumberChannels > 0, let d = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let outCh = Int(b.mNumberChannels)
            let frames = min(inFrames, Int(b.mDataByteSize) / (MemoryLayout<Float>.size * outCh))
            for f in 0..<frames {
                let si = f * inCh
                let di = f * outCh
                if outCh == 1 && inCh >= 2 {
                    d[di] = (s[si] + s[si + 1]) * 0.5
                } else {
                    for c in 0..<outCh { d[di + c] = s[si + (c % inCh)] }
                }
            }
        }
    }
}
