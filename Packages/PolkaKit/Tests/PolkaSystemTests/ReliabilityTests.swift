import AppKit
import Foundation
import ImageIO
import Security
import Testing
import UniformTypeIdentifiers

import PolkaCore
@testable import PolkaSystem

@Suite struct ClipboardImageCodecTests {
    private func encodedPicture(width: Int, height: Int, as type: UTType) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test func keepsPNGAndMakesASmallPreview() throws {
        let png = try encodedPicture(width: 1200, height: 800, as: .png)
        let image = try #require(ClipboardImageCodec.makeImage(from: .png(png)))
        #expect(image.png == png)
        #expect(image.pixelWidth == 1200 && image.pixelHeight == 800)
        let preview = try #require(CGImageSourceCreateWithData(image.preview as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(preview, 0, nil) as? [CFString: Any])
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        #expect(width <= ClipboardImageCodec.previewPixelSize)
    }

    @Test func convertsTIFFToPNGAndBack() throws {
        let tiff = try encodedPicture(width: 300, height: 200, as: .tiff)
        let image = try #require(ClipboardImageCodec.makeImage(from: .other(tiff)))
        #expect(image.png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(image.pixelWidth == 300 && image.pixelHeight == 200)
        let back = try #require(ClipboardImageCodec.tiffData(fromPNG: image.png))
        #expect(NSBitmapImageRep(data: back)?.pixelsWide == 300)
    }

    @Test func rejectsWhatIsNotAPictureOrTooLarge() {
        #expect(ClipboardImageCodec.makeImage(from: .png(Data("not a picture".utf8))) == nil)
        #expect(ClipboardImageCodec.makeImage(from: .other(Data())) == nil)
        #expect(ClipboardImageCodec.makeImage(from: .png(Data(count: ClipboardHistory.maximumImageBytes + 1))) == nil)
    }
}

@Suite struct CodeSignatureTests {
    private let calculator = URL(filePath: "/System/Applications/Calculator.app")

    @Test func acceptsAValidlySignedApp() throws {
        try CodeSignature.verify(calculator)
    }

    @Test func rejectsAnAppFromAnotherSigner() throws {
        var requirement: SecRequirement?
        let created = SecRequirementCreateWithString(#"identifier "io.github.romabmstu.Polka""# as CFString, [], &requirement)
        #expect(created == errSecSuccess)
        #expect(throws: CodeSignature.Failure.differentSigner) {
            try CodeSignature.verify(calculator, requirement: requirement)
        }
    }

    @Test func rejectsAnUnsignedBundle() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PolkaSignatureTest-\(UUID().uuidString)")
        let app = folder.appending(path: "Fake.app/Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("#!/bin/sh\n".utf8).write(to: app.appending(path: "Fake"))
        #expect(throws: (any Error).self) {
            try CodeSignature.verify(folder.appending(path: "Fake.app"))
        }
    }
}

@Suite struct ScriptSyntaxTests {
    private let runner = CommandRunner()

    /// Compiling needs the browser's scripting dictionary, so only installed
    /// browsers are checked; Safari always is.
    @Test(arguments: Browser.allCases)
    func browserScriptsCompile(_ browser: Browser) async throws {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) != nil else { return }
        var scripts = [BrowserBridge.newTabScript(for: browser), BrowserBridge.listTabsScript(for: browser)]
        if browser.supportsNewWindowScript { scripts.append(BrowserBridge.newWindowScript(for: browser)) }
        for script in scripts {
            let output = FileManager.default.temporaryDirectory.appending(path: "polka-\(UUID().uuidString).scpt")
            defer { try? FileManager.default.removeItem(at: output) }
            let result = try await runner.run(
                "/usr/bin/osacompile", ["-o", output.path(percentEncoded: false), "-"], input: script,
                timeout: .seconds(60))
            #expect(result.succeeded, "\(browser.name): \(result.errorOutput)")
        }
    }

    @Test func relaunchScriptParses() async throws {
        let result = try await runner.run("/bin/sh", ["-n"], input: Updater.relaunchScript)
        #expect(result.succeeded, "\(result.errorOutput)")
    }

    @Test func linksOpenOnlyAsWebPages() throws {
        let urls = ["https://example.com", "http://example.org", "file:///etc/passwd", "javascript:alert(1)"]
            .compactMap(URL.init(string:))
        #expect(BrowserBridge.webPages(urls).map(\.absoluteString) == ["https://example.com", "http://example.org"])
    }
}
