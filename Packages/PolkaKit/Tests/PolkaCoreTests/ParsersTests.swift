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

    @Test func ignoresBlankAndHugeText() {
        var history = ClipboardHistory()
        #expect(!history.record("   \n"))
        #expect(!history.record(String(repeating: "x", count: ClipboardHistory.maximumTextLength + 1)))
    }
}
