import Foundation
import MobiPadProtocol
import Network

/// Finds Macs running the companion app on the local network (FR-01, CR-02).
public final class MacBrowser: @unchecked Sendable {
    public struct Mac: Sendable, Hashable, Identifiable {
        public let name: String
        public let endpoint: NWEndpoint
        public var id: String { name }
    }

    private let browser: NWBrowser

    /// - Parameters:
    ///   - type: the Bonjour service type; another one only for development tools such as the stream probe.
    ///   - onChange: called on the main queue with the current list, sorted by name.
    public init(type: String = MobiPadService.bonjourType, onChange: @escaping @Sendable ([Mac]) -> Void) {
        browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .udp)
        browser.browseResultsChangedHandler = { results, _ in
            let macs = results.compactMap { result -> Mac? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return Mac(name: name, endpoint: result.endpoint)
            }
            onChange(macs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        }
    }

    public func start() {
        browser.start(queue: .main)
    }

    public func stop() {
        browser.cancel()
    }
}
