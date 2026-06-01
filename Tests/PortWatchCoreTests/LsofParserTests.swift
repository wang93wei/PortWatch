import Foundation
import XCTest
@testable import PortWatchCore

final class LsofParserTests: XCTestCase {
    func testParsesListeningPortsAndSkipsMalformedLines() throws {
        let output = try fixture("lsof-listen.txt")
        let parser = LsofParser(currentUserName: "alan")

        let result = parser.parse(output)

        XCTAssertEqual(result.entries.map(\.port), [3000, 5432, 80, 5173])
        XCTAssertEqual(result.entries[0].processName, "node")
        XCTAssertEqual(result.entries[0].address, "127.0.0.1")
        XCTAssertEqual(result.entries[0].privilegeLevel, .currentUser)
        XCTAssertEqual(result.entries[1].privilegeLevel, .otherUser)
        XCTAssertEqual(result.entries[2].privilegeLevel, .rootOrSystem)
        XCTAssertEqual(result.skippedLineCount, 1)
    }

    private func fixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil)!
        return try String(contentsOf: url, encoding: .utf8)
    }
}
