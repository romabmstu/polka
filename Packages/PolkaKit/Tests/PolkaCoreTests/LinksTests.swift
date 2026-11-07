import Foundation
import Testing

@testable import PolkaCore

@Suite struct URLNormalizerTests {
    @Test(arguments: [
        ("https://example.com", true),
        ("http://example.com/page?x=1", true),
        ("file:///Users/me/notes.txt", true),
        ("javascript:alert(1)", false),
        ("data:text/html,hi", false),
        ("polka://save?url=x", false),
    ])
    func savable(_ string: String, _ expected: Bool) {
        #expect(URLNormalizer.isSavable(URL(string: string)!) == expected)
    }

    @Test func identityIgnoresCaseDefaultPortsAndTrailingSlash() {
        let a = URLNormalizer.identity(of: URL(string: "HTTPS://Example.COM:443/docs/")!)
        let b = URLNormalizer.identity(of: URL(string: "https://example.com/docs")!)
        #expect(a == b)
    }

    @Test func identityKeepsFragments() {
        let a = URLNormalizer.identity(of: URL(string: "https://app.com/#/inbox")!)
        let b = URLNormalizer.identity(of: URL(string: "https://app.com/#/sent")!)
        #expect(a != b)
    }

    @Test func userInputGetsScheme() {
        #expect(URLNormalizer.url(fromUserInput: " swift.org/blog ")?.absoluteString == "https://swift.org/blog")
        #expect(URLNormalizer.url(fromUserInput: "not a url") == nil)
    }
}

@Suite struct LinkExtractorTests {
    @Test func extractsMixedFormats() {
        let text = """
            Read later:
            - [Swift blog](https://swift.org/blog)
            https://news.ycombinator.com | Hacker News
            Docs — https://developer.apple.com/documentation.
            https://a.com, https://b.com
            """
        let pages = LinkExtractor.pages(in: text)
        #expect(pages.map(\.url.absoluteString) == [
            "https://swift.org/blog",
            "https://news.ycombinator.com",
            "https://developer.apple.com/documentation",
            "https://a.com",
            "https://b.com",
        ])
        #expect(pages[0].title == "Swift blog")
        #expect(pages[1].title == "Hacker News")
        #expect(pages[2].title == "Docs")
    }

    @Test func keepsBalancedParentheses() {
        let pages = LinkExtractor.pages(in: "see https://en.wikipedia.org/wiki/Swift_(programming_language).")
        #expect(pages.first?.url.absoluteString == "https://en.wikipedia.org/wiki/Swift_(programming_language)")
    }

    @Test func readsAnchorsFromHTML() {
        let html = """
            <p>See <A class="x" HREF="https://swift.org/blog/?a=1&amp;b=2">the <b>Swift</b>
            blog</a>, <a href="/relative">this</a>, <a href='javascript:alert(1)'>that</a>
            and <a href="https://swift.org/blog/?a=1&amp;b=2">again</a>.</p>
            """
        let pages = LinkExtractor.pages(inHTML: html)
        #expect(pages.map(\.url.absoluteString) == ["https://swift.org/blog/?a=1&b=2"])
        #expect(pages.first?.title == "the Swift blog")
    }

    @Test func removesDuplicates() {
        #expect(LinkExtractor.pages(in: "https://a.com https://a.com/").count == 1)
    }
}
