import XCTest
@testable import Watchlist

final class NucleusServerTests: XCTestCase {
    private let code = "nucleus" + "a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6" + "home"

    private func problem(_ body: () throws -> Any) -> ServerProblem? {
        do { _ = try body(); return nil } catch { return error as? ServerProblem }
    }

    // MARK: Address

    func testBareHostIsHTTPSOnDefaultPath() throws {
        let s = try NucleusServer.parse("  nas.tail1234.ts.net ")
        XCTAssertEqual(s.origin.absoluteString, "https://nas.tail1234.ts.net")
        XCTAssertEqual(s.discoveryURL.absoluteString, "https://nas.tail1234.ts.net/api/v1/oauth/metadata")
    }

    func testHostPortAndIP() throws {
        let s = try NucleusServer.parse("100.101.102.103:8080", scheme: "http")
        XCTAssertEqual(s.origin.absoluteString, "http://100.101.102.103:8080")
    }

    func testMagicDNSShortName() throws {
        XCTAssertEqual(try NucleusServer.parse("nas", scheme: "http").origin.absoluteString, "http://nas")
    }

    func testFullURLSchemeAndPortWinAndPathIsIgnored() throws {
        let s = try NucleusServer.parse("http://Example.com:81/authorize?x=1", scheme: "https", port: 9000)
        XCTAssertEqual(s.origin.absoluteString, "http://example.com:81")
        XCTAssertEqual(s.discoveryPath, NucleusServer.defaultDiscoveryPath)
    }

    func testPortFieldUsedWhenTextHasNone() throws {
        XCTAssertEqual(try NucleusServer.parse("nas", port: 8443).origin.absoluteString, "https://nas:8443")
    }

    func testCustomDiscoveryPathGetsLeadingSlash() throws {
        let s = try NucleusServer.parse("nas", discoveryPath: "well-known/nucleus")
        XCTAssertEqual(s.discoveryURL.absoluteString, "https://nas/well-known/nucleus")
    }

    func testBadAddresses() {
        for text in ["", "   ", "foo bar", "ftp://nas", "https://", "://nas"] {
            XCTAssertEqual(problem { try NucleusServer.parse(text) }, .badAddress, text)
        }
    }

    // MARK: Code

    func testCodeFormat() {
        XCTAssertTrue(NucleusServer.isCode(code))
        for bad in ["", "nucleushome", code.replacingOccurrences(of: "nucleus", with: "Nucleus"),
                    String(code.dropLast(4)) + "Home", "nucleus" + String(repeating: "a", count: 31) + "home",
                    "nucleus" + String(repeating: "a", count: 33) + "home", code.replacingOccurrences(of: "a1", with: "a-")] {
            XCTAssertFalse(NucleusServer.isCode(bad), bad)
        }
    }

    // MARK: Setup link and file

    func testSetupLink() throws {
        let url = URL(string: "com.nucleushome.watchlist://server?scheme=http&host=nas&port=8080&path=/meta&code=\(code)%0A")!
        let s = try NucleusServer.setup(from: url)
        XCTAssertEqual(s.origin.absoluteString, "http://nas:8080")
        XCTAssertEqual(s.discoveryPath, "/meta")
        XCTAssertEqual(s.code, code)
    }

    func testSetupFile() throws {
        let json = #"{"host":"nas.tail1234.ts.net","port":443,"code":"\#(code)"}"#
        let s = try NucleusServer.setup(fromFile: Data(json.utf8))
        XCTAssertEqual(s.origin.absoluteString, "https://nas.tail1234.ts.net:443")
        XCTAssertEqual(s.discoveryPath, NucleusServer.defaultDiscoveryPath)
        XCTAssertEqual(s.code, code)
    }

    func testSetupWithBadCodeSaysOnlyThat() {
        let url = URL(string: "com.nucleushome.watchlist://server?host=nas&code=nucleus123home")!
        XCTAssertEqual(problem { try NucleusServer.setup(from: url) }, .badCode)
    }

    func testBrokenSetups() {
        for link in ["com.nucleushome.watchlist://server", "com.nucleushome.watchlist://server?host=a/b",
                     "com.nucleushome.watchlist://server?host=nas&port=99999", "com.nucleushome.watchlist://server?host=nas&scheme=ftp"] {
            XCTAssertEqual(problem { try NucleusServer.setup(from: URL(string: link)!) }, .badSetup, link)
        }
        XCTAssertEqual(problem { try NucleusServer.setup(fromFile: Data("not json".utf8)) }, .badSetup)
    }
}
