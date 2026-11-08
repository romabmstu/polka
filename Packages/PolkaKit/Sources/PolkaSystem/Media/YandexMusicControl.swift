import AppKit
import ApplicationServices

/// Uses the accessibility controls of the Yandex Music player itself. This
/// never sends a global media key that could start an unrelated application.
public enum YandexMusicControl {
    public static let bundleID = "ru.yandex.desktop.music"

    public enum Result: Sendable {
        case started, alreadyPlaying, notReady, permissionRequired
    }

    public static func start(pid: pid_t) async -> Result {
        guard AXIsProcessTrusted() else { return .permissionRequired }
        return await Task.detached {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.5)
            AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            for _ in 0..<20 {
                if let result = findPlayer(in: application) { return result }
                try? await Task.sleep(for: .milliseconds(500))
            }
            return .notReady
        }.value
    }

    private static func findPlayer(in application: AXUIElement) -> Result? {
        var queue: [AXUIElement] = [application]
        var index = 0
        while index < queue.count && index < 3000 {
            let element = queue[index]
            index += 1
            let label = stringAttribute(element, kAXDescriptionAttribute) ?? stringAttribute(element, kAXTitleAttribute)
            if label == "Плеер" || label == "Player" {
                if let result = playButton(in: element) { return result }
            }
            queue.append(contentsOf: children(element))
        }
        return nil
    }

    private static func playButton(in player: AXUIElement) -> Result? {
        var queue: [AXUIElement] = [player]
        var index = 0
        while index < queue.count && index < 300 {
            let element = queue[index]
            index += 1
            if stringAttribute(element, kAXRoleAttribute) == kAXButtonRole as String {
                let label = stringAttribute(element, kAXDescriptionAttribute) ?? stringAttribute(element, kAXTitleAttribute)
                if ["Пауза", "Pause"].contains(label ?? "") { return .alreadyPlaying }
                if ["Воспроизведение", "Play", "Playback"].contains(label ?? "") {
                    return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success ? .started : nil
                }
            }
            queue.append(contentsOf: children(element))
        }
        return nil
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
