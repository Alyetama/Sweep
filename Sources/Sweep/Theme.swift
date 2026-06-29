import SwiftUI
import AppKit

// MARK: - Brand

enum Brand {
    /// The teal→indigo accent used across the app, matching the app icon.
    static let gradient = LinearGradient(
        colors: [Color(hex: 0x33D4BD), Color(hex: 0x5B6BFF)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let accent = Color(hex: 0x4C7CF5)
    static let danger = Color(hex: 0xFF4D4F)
}

// MARK: - Category presentation

extension FileCategory {
    var symbol: String {
        switch self {
        case .binary:          return "app.fill"
        case .support:         return "shippingbox.fill"
        case .caches:          return "bolt.fill"
        case .preferences:     return "slider.horizontal.3"
        case .containers:      return "cube.box.fill"
        case .groupContainers: return "square.stack.3d.up.fill"
        case .savedState:      return "macwindow"
        case .logs:            return "doc.text.fill"
        case .cookies:         return "circle.grid.cross.fill"
        case .webData:         return "globe"
        case .launchItems:     return "bolt.badge.clock.fill"
        case .crashReports:    return "exclamationmark.triangle.fill"
        case .other:           return "doc.fill"
        }
    }

    var tint: Color {
        switch self {
        case .binary:          return Color(hex: 0x4C7CF5)
        case .support:         return Color(hex: 0x6C5CE7)
        case .caches:          return Color(hex: 0xFF9F0A)
        case .preferences:     return Color(hex: 0x30B0C7)
        case .containers:      return Color(hex: 0xAF52DE)
        case .groupContainers: return Color(hex: 0xFF2D92)
        case .savedState:      return Color(hex: 0x32ADE6)
        case .logs:            return Color(hex: 0x8E8E93)
        case .cookies:         return Color(hex: 0xC69C6D)
        case .webData:         return Color(hex: 0x0A84FF)
        case .launchItems:     return Color(hex: 0xFF453A)
        case .crashReports:    return Color(hex: 0xFF6B22)
        case .other:           return Color(hex: 0x98989D)
        }
    }
}

// MARK: - Formatting

enum Format {
    private static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }()

    static func size(_ n: Int64) -> String {
        if n < 0 { return "—" }
        if n == 0 { return "Zero KB" }
        return bytes.string(fromByteCount: n)
    }

    /// "2 months ago", "Today", "Never" — for the last-used hint.
    static func lastUsed(_ date: Date?) -> String {
        guard let date else { return "Never used" }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        switch days {
        case ..<1:   return "Used today"
        case 1:      return "Used yesterday"
        case 2..<30: return "Used \(days) days ago"
        case 30..<365:
            let m = max(1, days / 30); return "Used \(m) month\(m == 1 ? "" : "s") ago"
        default:
            let y = max(1, days / 365); return "Used \(y) year\(y == 1 ? "" : "s") ago"
        }
    }
}

// MARK: - Reusable views

/// A circular check control with the accent fill, matching the cleaner-app look.
/// `mixed` shows the indeterminate (—) state used by a "Select All" box when only
/// some of its items are selected.
struct SelectCircle: View {
    let isOn: Bool
    var mixed = false
    var locked = false

    private var filled: Bool { isOn || mixed }

    var body: some View {
        ZStack {
            Circle()
                .fill(filled ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.clear))
            Circle()
                .strokeBorder(filled ? Color.clear : Color.secondary.opacity(0.45), lineWidth: 1.5)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            } else if mixed {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 20, height: 20)
        .opacity(locked ? 0.55 : 1)
    }
}

/// A small rounded category glyph (colored tile + SF Symbol).
struct CategoryGlyph: View {
    let category: FileCategory
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(category.tint.opacity(0.16))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: category.symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(category.tint)
            )
    }
}

/// A muted size pill used in list rows.
struct SizePill: View {
    let bytes: Int64
    var prominent = false

    var body: some View {
        Text(Format.size(bytes))
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(prominent ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(prominent ? 0.16 : 0.10),
                        in: Capsule())
    }
}

// MARK: - Color hex

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}
