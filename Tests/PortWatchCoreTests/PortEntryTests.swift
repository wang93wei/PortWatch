import XCTest
@testable import PortWatchCore

final class PortEntryTests: XCTestCase {
    func testPortEntryStableIdentifierIncludesProtocolAddressPortAndPID() {
        let entry = PortEntry(
            protocolName: .tcp,
            address: "127.0.0.1",
            port: 3000,
            pid: 8421,
            processName: "node",
            user: "alan",
            executablePath: "/opt/homebrew/bin/node",
            commandLine: "/opt/homebrew/bin/node server.js",
            privilegeLevel: .currentUser,
            category: .development
        )

        XCTAssertEqual(entry.id, "tcp-127.0.0.1-3000-8421")
        XCTAssertEqual(entry.displayEndpoint, "127.0.0.1:3000")
    }
}
