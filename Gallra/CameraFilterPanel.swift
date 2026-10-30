import SwiftUI
import GallraCore

/// Popover with the camera-info filters: an exact value or a from/to range for each number.
struct CameraFilterPanel: View {
    let tab: FolderTab

    var body: some View {
        @Bindable var tab = tab
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Camera filters").font(.system(size: 12, weight: .semibold))
                Spacer()
                if let (done, total) = tab.cameraLoad {
                    Text("Reading \(done)/\(total)…").font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                Button("Clear") { tab.cameraFilter = CameraFilter() }
                    .controlSize(.small).disabled(!tab.cameraFilter.isActive)
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                row("Aperture", $tab.cameraFilter.aperture, tab.choices.apertures) { "f/" + Self.number($0) }
                row("Shutter", $tab.cameraFilter.shutter, tab.choices.shutters) { Self.shutter($0) }
                row("ISO", $tab.cameraFilter.iso, tab.choices.isos) { String(Int($0)) }
                row("Focal length", $tab.cameraFilter.focalLength, tab.choices.focalLengths) { Self.number($0) + " mm" }
            }
        }
        .padding(12).frame(width: 440)
        .foregroundStyle(Theme.textPrimary)
        .background(Theme.raised)                  // solid, not see-through
        .presentationBackground(Theme.raised)
        .preferredColorScheme(.dark)
        .onAppear { tab.loadAllCameraInfo() }
    }

    private func row(_ title: String, _ range: Binding<NumberRange>, _ values: [Double],
                     label: @escaping (Double) -> String) -> some View {
        GridRow {
            Text(title).font(.system(size: 12))
            picker("Exactly", range.exact, values, label)
            picker("From", range.min, values, label).disabled(range.wrappedValue.exact != nil)
            picker("To", range.max, values, label).disabled(range.wrappedValue.exact != nil)
        }
    }

    private func picker(_ placeholder: String, _ value: Binding<Double?>, _ values: [Double],
                        _ label: @escaping (Double) -> String) -> some View {
        Picker(placeholder, selection: value) {
            Text(placeholder).tag(Double?.none)
            ForEach(values, id: \.self) { Text(label($0)).tag(Double?.some($0)) }
        }
        .labelsHidden().controlSize(.small).disabled(values.isEmpty)
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func shutter(_ seconds: Double) -> String {
        seconds >= 1 ? number(seconds) + " s" : "1/\(Int((1 / seconds).rounded()))"
    }
}
