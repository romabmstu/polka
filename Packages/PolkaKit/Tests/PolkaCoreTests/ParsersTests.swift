import Foundation
import Testing

@testable import PolkaCore

@Suite struct SCUtilParserTests {
    private let sample = """
        Available network connection services in the current set (*=enabled):
        * (Connected)      3F2B0C3E-1A2B-4C5D-8E9F-ABCDEF012345 VPN (com.example.happ.tunnel) "Happ"                   [VPN:com.example.happ.tunnel]
        * (Disconnected)   0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9 VPN (com.v2box.mac.extension) "V2Box Germany"     [VPN:com.v2box.mac.extension]
          (Disconnected)   11111111-2222-3333-4444-555555555555 PPP --> L2TP     "Office"                          [PPP:L2TP]
        """

    @Test func parsesServices() {
        let list = SCUtilParser.connections(from: sample)
        #expect(list.count == 3)
        #expect(list[0].name == "Happ")
        #expect(list[0].status == .connected)
        #expect(list[0].providerBundleID == "com.example.happ.tunnel")
        #expect(list[1].name == "V2Box Germany")
        #expect(list[2].isEnabled == false)
        #expect(list[2].providerBundleID == nil)
    }

    @Test func parsesStatus() {
        #expect(SCUtilParser.status(from: "Connecting\nExtended Status <dictionary> {") == .connecting)
    }

    @Test func validatesServiceIDs() {
        #expect(SCUtilParser.isValidServiceID("3F2B0C3E-1A2B-4C5D-8E9F-ABCDEF012345"))
        #expect(!SCUtilParser.isValidServiceID("--nc"))
        #expect(!SCUtilParser.isValidServiceID("3F2B0C3E-1A2B-4C5D-8E9F-ABCDEF012345; rm -rf ~"))
    }
}

@Suite struct NetworkRoutingTests {
    @Test func detectsLocalSystemProxy() {
        let on = """
            <dictionary> {
              ExceptionsList : <array> {
                0 : 127.0.0.1
              }
              HTTPEnable : 1
              HTTPPort : 2080
              HTTPProxy : 127.0.0.1
              SOCKSEnable : 0
            }
            """
        #expect(NetworkRouting.localProxyEnabled(scutilProxyOutput: on))

        let corporate = "HTTPEnable : 1\nHTTPProxy : proxy.example.com\n"
        #expect(!NetworkRouting.localProxyEnabled(scutilProxyOutput: corporate))

        let switchedOff = "HTTPEnable : 0\nHTTPProxy : 127.0.0.1\nSOCKSEnable : 1\nSOCKSProxy : 10.0.0.1\n"
        #expect(!NetworkRouting.localProxyEnabled(scutilProxyOutput: switchedOff))
    }

    @Test func readsDefaultInterface() {
        let output = """
               route to: default
            destination: default
                   mask: default
                gateway: 198.18.0.1
              interface: utun5
                  flags: <UP,GATEWAY,DONE,STATIC,PRCLONING>
            """
        let interface = NetworkRouting.defaultInterface(routeOutput: output)
        #expect(interface == "utun5")
        #expect(NetworkRouting.isTunnel(interface))
        #expect(!NetworkRouting.isTunnel("en0"))
        #expect(NetworkRouting.defaultInterface(routeOutput: "route: writing to routing socket: not in table") == nil)
    }

    @Test func appIDsRoundTripAndRejectJunk() {
        let app = VPNApp(bundleID: "moe.Throne.macosx", name: "FSNT Client")
        #expect(VPNApp.bundleID(fromConnectionID: app.id) == "moe.Throne.macosx")
        #expect(VPNApp.bundleID(fromConnectionID: "app:-rf /") == nil)
        #expect(VPNApp.bundleID(fromConnectionID: "6A1F7E04-1B7B-4C2E-9F2D-0C5B8D2C7A11") == nil)
    }
}

@Suite struct TunnelblickTests {
    @Test func parsesConfigurationsAndStates() {
        let output = "Office\u{1F}CONNECTED\u{1E}Home NL\u{1F}EXITING\u{1E}Backup\u{1F}AUTH\u{1E}bad/name\u{1F}EXITING\u{1E}"
        let list = Tunnelblick.connections(fromScriptOutput: output)
        #expect(list.map(\.name) == ["Office", "Home NL", "Backup"])
        #expect(list.map(\.status) == [.connected, .disconnected, .connecting])
        #expect(list.allSatisfy { $0.isTunnelblick && !$0.isSystemService && !$0.isAppManaged })
        #expect(Tunnelblick.configurationName(fromConnectionID: list[1].id) == "Home NL")
    }

    @Test func readsNamesFromDiskAndRejectsJunk() {
        let names = Tunnelblick.configurationNames(fromFileNames: ["work.tblk", ".DS_Store", "Home.tblk", "work.tblk", "-x.tblk"])
        #expect(names == ["Home", "work"])
        #expect(Tunnelblick.configurationName(fromConnectionID: "tunnelblick:") == nil)
        #expect(Tunnelblick.configurationName(fromConnectionID: "app:net.tunnelblick.tunnelblick") == nil)
    }
}

@Suite struct MeetingLinkTests {
    @Test func prefersURLField() {
        let match = MeetingLink.find(
            url: URL(string: "https://meet.google.com/abc-defg-hij"), location: "Room 4", notes: nil)
        #expect(match?.service == .googleMeet)
    }

    @Test func findsLinkInNotes() {
        let match = MeetingLink.find(url: nil, location: nil, notes: "Join: https://us02web.zoom.us/j/123456?pwd=x")
        #expect(match?.service == .zoom)
    }

    @Test func ignoresLookalikeHosts() {
        #expect(MeetingLink.find(url: URL(string: "https://meet.google.com.evil.example/x"), location: nil, notes: nil) == nil)
        #expect(MeetingLink.find(url: URL(string: "http://meet.google.com/x"), location: nil, notes: nil) == nil)
    }
}

@Suite struct ExchangeRatesTests {
    private let payload = """
        {"result":"success","base_code":"USD","time_last_update_unix":1762473600,
         "rates":{"USD":1,"EUR":0.9,"RUB":80,"KRW":1400,"GBP":0.8,"JPY":150,"CNY":7.1,
                  "CHF":0.88,"CAD":1.37,"AUD":1.52,"TRY":34,"bad":5,"NEG":-1}}
        """

    @Test func decodesAndFilters() throws {
        let rates = try ExchangeRates.decodeOpenERAPI(Data(payload.utf8))
        #expect(rates.base == "USD")
        #expect(rates.rates["bad"] == nil)
        #expect(rates.rates["NEG"] == nil)
        #expect(rates.convert(1400, from: "KRW", to: "RUB") == 80)
    }

    @Test func rejectsProviderErrors() {
        let error = #"{"result":"error","base_code":"USD","rates":{}}"#
        #expect(throws: ExchangeRates.DecodingFailure.providerError) {
            try ExchangeRates.decodeOpenERAPI(Data(error.utf8))
        }
    }
}

@Suite struct ClipboardTests {
    @Test func skipsPasswordManagerContent() {
        #expect(!ClipboardPrivacy.shouldRecord(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(ClipboardPrivacy.shouldRecord(types: ["public.utf8-plain-text"]))
    }

    @Test func movesRepeatsToTopAndKeepsPins() {
        var history = ClipboardHistory(capacity: 3)
        history.record("one")
        history.record("two")
        history.togglePin(history.entries[1].id)
        history.record("three")
        history.record("four")
        history.record("one")

        #expect(history.entries.map(\.text) == ["one", "four", "three"])
        #expect(history.entries[0].isPinned)
    }

    @Test func keepsImagesApartFromTextAndCapsThem() {
        var history = ClipboardHistory(capacity: 30)
        let picture = ClipboardImage(png: Data([1, 2, 3]), pixelWidth: 10, pixelHeight: 5)
        #expect(history.record(picture))
        history.record("hello")
        history.record(picture)
        #expect(history.entries.count == 2)
        #expect(history.entries[0].kind == .image)
        #expect(history.entries[1].text == "hello")

        #expect(!history.record(ClipboardImage(png: Data(), pixelWidth: 1, pixelHeight: 1)))
        #expect(!history.record(ClipboardImage(png: Data(count: ClipboardHistory.maximumImageBytes + 1), pixelWidth: 1, pixelHeight: 1)))

        history.togglePin(history.entries[0].id)
        for byte in 10..<30 {
            history.record(ClipboardImage(png: Data([UInt8(byte)]), pixelWidth: 1, pixelHeight: 1))
        }
        let images = history.entries.filter { $0.kind == .image }
        #expect(images.count == ClipboardHistory.imageCapacity)
        #expect(images.contains { $0.image == picture && $0.isPinned })
        #expect(history.entries.contains { $0.text == "hello" })
    }

    @Test func ignoresBlankAndHugeText() {
        var history = ClipboardHistory()
        let blank = history.record("   \n")
        let huge = history.record(String(repeating: "x", count: ClipboardHistory.maximumTextLength + 1))
        #expect(!blank)
        #expect(!huge)
        #expect(history.entries.isEmpty)
    }
}

@Suite struct ScenarioTests {
    @Test func oldScenariosStillDecodeAndNewActionsRoundTrip() throws {
        let scenario = Scenario(
            name: "Focus", symbol: "moon.fill",
            actions: [
                .quitApp(bundleID: "com.tdesktop.Telegram"), .vpn(serviceID: nil), .appearance(.dark), .volume(30),
                .mute(false), .openApp(bundleID: "ru.yandex.desktop.music"), .runShortcut(name: "Work Focus"),
            ])
        let data = try JSONEncoder().encode([scenario])
        #expect(try JSONDecoder().decode([Scenario].self, from: data) == [scenario])

        let legacy = Scenario(name: "Old", symbol: "sparkles", actions: [.media(.play)])
        let legacyData = try JSONEncoder().encode(legacy)
        #expect(try JSONDecoder().decode(Scenario.self, from: legacyData).actions == [.media(.play)])
    }

    @Test func validatesBundleIDsAndVolume() {
        #expect(Scenario.isValidBundleID("com.apple.Safari"))
        #expect(!Scenario.isValidBundleID("Safari"))
        #expect(!Scenario.isValidBundleID("-a com.apple.Safari"))
        #expect(!Scenario.isValidBundleID("com.apple.Safari\nrm"))
        #expect(Scenario.clampedVolume(140) == 100)
        #expect(Scenario.clampedVolume(-3) == 0)
    }
}
