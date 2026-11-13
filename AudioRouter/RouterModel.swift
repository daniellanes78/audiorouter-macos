import Foundation
import SwiftUI
import CoreAudio

struct AppGroup: Identifiable, Hashable {
    let id: String                 // bundleID ou "pid:123"
    let name: String
    let processObjects: [AudioObjectID]
    let isPlaying: Bool
}

@MainActor
final class RouterModel: ObservableObject {
    @Published private(set) var groups: [AppGroup] = []
    @Published private(set) var devices: [OutputDevice] = []
    @Published private(set) var defaultDeviceName = "-"
    @Published private(set) var routes: [String: String] = [:]   // groupKey -> deviceUID
    @Published var lastError: String?
    @Published var showAll = false

    private struct Active {
        let router: ProcessTapRouter
        let objects: [AudioObjectID]
        let deviceUID: String
    }
    private var active: [String: Active] = [:]
    private var timer: Timer?
    private let defaultsKey = "routes"

    init() {
        routes = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var visibleGroups: [AppGroup] {
        groups.filter { showAll || $0.isPlaying || routes[$0.id] != nil }
    }

    func setRoute(_ groupKey: String, uid: String?) {
        routes[groupKey] = uid
        UserDefaults.standard.set(routes, forKey: defaultsKey)
        refresh()
    }

    func stopAll() {
        for (_, a) in active { a.router.stop() }
        active.removeAll()
    }

    func refresh() {
        devices = listOutputDevices()
        let defID = defaultOutputDeviceID()
        defaultDeviceName = devices.first(where: { $0.id == defID })?.name ?? "-"

        var byKey: [String: [AudioProcess]] = [:]
        for p in listAudioProcesses() { byKey[p.groupKey, default: []].append(p) }

        groups = byKey.map { key, procs in
            AppGroup(id: key,
                     name: friendlyName(for: procs[0]),
                     processObjects: procs.map(\.objectID).sorted(),
                     isPlaying: procs.contains(where: \.isPlaying))
        }
        .sorted { a, b in
            if a.isPlaying != b.isPlaying { return a.isPlaying }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        applyRoutes()
    }

    private func applyRoutes() {
        let validUIDs = Set(devices.map(\.uid))
        let groupByKey = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })

        // Para rotas que mudaram, sumiram ou cujo conjunto de processos mudou
        for (key, a) in active {
            let g = groupByKey[key]
            let wanted = routes[key]
            if g == nil || wanted != a.deviceUID || g!.processObjects != a.objects || !validUIDs.contains(a.deviceUID) {
                a.router.stop()
                active[key] = nil
            }
        }

        // Inicia rotas pendentes
        for g in groups {
            guard let uid = routes[g.id], validUIDs.contains(uid), active[g.id] == nil else { continue }
            let r = ProcessTapRouter(processObjectIDs: g.processObjects, outputUID: uid)
            do {
                try r.start()
                active[g.id] = Active(router: r, objects: g.processObjects, deviceUID: uid)
                lastError = nil
            } catch {
                r.stop()
                lastError = "\(g.name): \(error.localizedDescription)"
            }
        }
    }
}
