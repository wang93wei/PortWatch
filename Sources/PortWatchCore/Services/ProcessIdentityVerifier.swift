import Foundation

public protocol ProcessIdentityVerifying: Sendable {
    func verify(entry: PortEntry) async -> Bool
}

public struct ProcessIdentityVerifier: ProcessIdentityVerifying {
    private let metadataProvider: ProcessMetadataProviding

    public init(metadataProvider: ProcessMetadataProviding = PSProcessMetadataProvider()) {
        self.metadataProvider = metadataProvider
    }

    public func verify(entry: PortEntry) async -> Bool {
        guard let identity = await metadataProvider.identity(for: entry.pid) else {
            return false
        }
        guard identity.pid == entry.pid,
              identity.processName == entry.processName,
              identity.user == entry.user else {
            return false
        }
        let metadata = await metadataProvider.metadata(for: entry.pid)
        if let expectedPath = entry.executablePath {
            guard let actualPath = metadata.executablePath ?? identity.executablePath else {
                return false
            }
            return expectedPath == actualPath
        }
        if let expectedCommand = entry.commandLine, let actualCommand = metadata.commandLine {
            return expectedCommand == actualCommand
        }
        guard entry.commandLine != nil else {
            return false
        }
        return false
    }
}
