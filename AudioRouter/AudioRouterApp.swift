import SwiftUI
import AppKit

@main
struct AudioRouterApp: App {
    @StateObject private var model = RouterModel()

    var body: some Scene {
        Window("AudioRouter", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("AudioRouter", systemImage: "headphones") {
            ContentView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @EnvironmentObject var model: RouterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AudioRouter").font(.headline)
                Spacer()
                Toggle("Todos", isOn: $model.showAll)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            Divider()

            if model.visibleGroups.isEmpty {
                Text("Nenhum app tocando áudio agora.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.visibleGroups) { g in row(g) }
                    }
                }
                .frame(maxHeight: 380)
            }

            if let err = model.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            Divider()

            HStack {
                Text("Padrão do sistema: \(model.defaultDeviceName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Sair") {
                    model.stopAll()
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 380)
    }

    private func row(_ g: AppGroup) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(g.isPlaying ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(g.name).lineLimit(1)
            Spacer()
            Picker("", selection: Binding(
                get: { model.routes[g.id] ?? "" },
                set: { model.setRoute(g.id, uid: $0.isEmpty ? nil : $0) }
            )) {
                Text("Padrão").tag("")
                ForEach(model.devices) { d in
                    Text(d.name).tag(d.uid)
                }
            }
            .labelsHidden()
            .frame(width: 180)
        }
    }
}
