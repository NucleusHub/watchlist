import XCTest
@testable import Watchlist

/// The Swift merge must give exactly what the web app's merge gives (Fixtures/generate.mjs).
final class MergeTests: XCTestCase {
    private struct Fixture: Decodable {
        struct Case: Decodable {
            let a: JSONValue
            let b: JSONValue
            let merged: JSONValue
            let fingerprint: String
            let normalizedA: JSONValue
        }
        let now: String
        let cases: [String: Case]
    }

    private func fixture() throws -> Fixture {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "merge-cases", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testMatchesWebMerge() throws {
        let f = try fixture()
        let now = try XCTUnwrap(Timestamp.date(f.now))
        XCTAssertFalse(f.cases.isEmpty)
        for (name, c) in f.cases.sorted(by: { $0.key < $1.key }) {
            let a = WatchlistDocument.normalize(c.a)
            let b = WatchlistDocument.normalize(c.b)
            XCTAssertEqual(a.json, c.normalizedA, "normalize: \(name)")
            let merged = WatchlistDocument.merge(a, b, now: now)
            XCTAssertEqual(merged.json, c.merged, "merge: \(name)")
            XCTAssertEqual(merged.fingerprint, c.fingerprint, "fingerprint: \(name)")
        }
    }

    func testDocumentRoundTripsUnknownFields() throws {
        let json = #"{"items":[{"_id":"a","title":"A","year":"1999","plugin":{"x":[1,2.5,null]}}],"collections":[],"settings":{"updatedAt":null},"deleted":{}}"#
        let doc = try JSONDecoder().decode(WatchlistDocument.self, from: Data(json.utf8))
        XCTAssertEqual(doc.items.first?.year, 1999)
        let again = try JSONDecoder().decode(WatchlistDocument.self, from: JSONEncoder().encode(doc))
        XCTAssertEqual(again.items.first?.raw["plugin"], ["x": [1, 2.5, nil]])
    }

    func testTimestampsMatchJavaScript() {
        let s = Timestamp.string(Date(timeIntervalSince1970: 1_727_784_000.123))
        XCTAssertEqual(s, "2024-10-01T12:00:00.123Z")
        XCTAssertEqual(RecordID.make().count, 24)
    }
}
