import Foundation

/// Lets a continuation be resumed from a handler that may fire more than once,
/// such as a Network framework state handler.
package final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?

    package init(_ continuation: CheckedContinuation<T, any Error>) {
        self.continuation = continuation
    }

    package func resume(returning value: T) {
        take()?.resume(returning: value)
    }

    package func resume(throwing error: any Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<T, any Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }
}

extension Duration {
    package var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
