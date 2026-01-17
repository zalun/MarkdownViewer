import XCTest
@testable import MarkdownViewer

final class HeadingSluggerTests: XCTestCase {
    func testSlugifyDeduplicatesTitles() {
        var slugger = HeadingSlugger()

        XCTAssertEqual(slugger.slug(for: "Hello World"), "hello-world")
        XCTAssertEqual(slugger.slug(for: "Hello World"), "hello-world-1")
    }

    func testSlugifyStripsPunctuation() {
        var slugger = HeadingSlugger()

        XCTAssertEqual(slugger.slug(for: "Hello, World!"), "hello-world")
    }

    func testSlugifyFallsBackToSection() {
        var slugger = HeadingSlugger()

        XCTAssertEqual(slugger.slug(for: "   "), "section")
    }
}
