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

    func testDedupesDualStackWildcardListen() {
        // lsof 对 `*:port` 通配 listen 输出 IPv4 + IPv6 两行，address 字段都是 `*`，
        // parser 必须按 (protocol, address, port, pid) 去重，避免 ForEach ID 冲突。
        let output = """
        COMMAND   PID     USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        postgres  731 postgres    7u  IPv6 0x2222222222222222      0t0  TCP *:5432 (LISTEN)
        postgres  731 postgres    8u  IPv4 0x2222222222222223      0t0  TCP *:5432 (LISTEN)
        node     8421     alan   21u  IPv4 0x1111111111111111      0t0  TCP 127.0.0.1:3000 (LISTEN)
        """
        let parser = LsofParser(currentUserName: "alan")

        let result = parser.parse(output)

        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.skippedLineCount, 1)
        // id 必须唯一
        let ids = result.entries.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "entries 包含重复 id: \(ids)")
        // postgres 5432 留下一行（IPv4/IPv6 哪行无所谓，行为一致）
        XCTAssertEqual(result.entries.filter { $0.processName == "postgres" }.count, 1)
        XCTAssertEqual(result.entries.filter { $0.processName == "postgres" }.first?.port, 5432)
    }

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: nil)!
        return try String(contentsOf: url, encoding: .utf8)
    }
}
