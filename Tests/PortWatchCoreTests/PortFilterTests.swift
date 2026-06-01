import XCTest
@testable import PortWatchCore

final class PortFilterTests: XCTestCase {
    func testFavoritesFilterOnlyReturnsFavoritePorts() {
        let entries = [
            sample(port: 3000, category: .development, privilege: .currentUser),
            sample(port: 80, category: .privileged, privilege: .rootOrSystem)
        ]

        let result = PortFilter.favorites.apply(to: entries, favoritePorts: [3000], searchText: "")

        XCTAssertEqual(result.map(\.port), [3000])
    }

    func testSearchMatchesPortProcessPIDUserAndPath() {
        let entries = [
            sample(port: 5173, processName: "vite", pid: 1198, user: "alan", path: "/tmp/project/vite"),
            sample(port: 5432, processName: "postgres", pid: 731, user: "postgres", path: "/opt/homebrew/postgres")
        ]

        XCTAssertEqual(PortFilter.listening.apply(to: entries, favoritePorts: [], searchText: "vite").map(\.port), [5173])
        XCTAssertEqual(PortFilter.listening.apply(to: entries, favoritePorts: [], searchText: "731").map(\.port), [5432])
        XCTAssertEqual(PortFilter.listening.apply(to: entries, favoritePorts: [], searchText: "homebrew").map(\.port), [5432])
    }

    private func sample(
        port: Int,
        processName: String = "node",
        pid: Int32 = 1,
        user: String = "alan",
        path: String? = nil,
        category: PortCategory = .development,
        privilege: PrivilegeLevel = .currentUser
    ) -> PortEntry {
        PortEntry(
            protocolName: .tcp,
            address: "127.0.0.1",
            port: port,
            pid: pid,
            processName: processName,
            user: user,
            executablePath: path,
            commandLine: nil,
            privilegeLevel: privilege,
            category: category
        )
    }
}
