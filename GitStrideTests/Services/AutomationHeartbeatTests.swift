import Foundation
import os
import Testing
@testable import GitStride

@Suite(.timeLimit(.minutes(1)))
struct AutomationHeartbeatTests {
    @Test(arguments: [false, true])
    func repeatedCallbacksKeepFirstResult(failsFirst: Bool) async throws {
        let socket = HeartbeatPing()
        let heartbeat = Task { try await AutomationService.sendHeartbeat(sendPing: { socket.sendPing(pongReceiveHandler: $0) }) }
        await socket.waitForPing()
        socket.reply(failsFirst ? URLError(.networkConnectionLost) : nil)
        socket.reply(failsFirst ? nil : URLError(.cancelled))
        do {
            try await heartbeat.value
            #expect(!failsFirst)
        } catch {
            #expect(failsFirst)
            #expect((error as? URLError)?.code == .networkConnectionLost)
        }
    }

    @Test
    func missingCallbackTimesOutAndLateCallbackIsHarmless() async {
        let socket = HeartbeatPing()
        do {
            try await AutomationService.sendHeartbeat(sendPing: { socket.sendPing(pongReceiveHandler: $0) }, timeout: .milliseconds(10))
            Issue.record("A missing pong must time out")
        } catch {
            #expect((error as? URLError)?.code == .timedOut)
        }
        socket.reply(nil)
        socket.reply(URLError(.cancelled))
    }

    @Test
    func cancellationEndsPendingPingWithoutCallback() async {
        let socket = HeartbeatPing()
        let heartbeat = Task {
            try await AutomationService.sendHeartbeat(sendPing: { socket.sendPing(pongReceiveHandler: $0) }, timeout: .seconds(120))
        }
        await socket.waitForPing()
        heartbeat.cancel()
        do {
            try await heartbeat.value
            Issue.record("A cancelled heartbeat must throw")
        } catch {
            #expect(error is CancellationError)
        }
        socket.reply(nil)
        socket.reply(URLError(.cancelled))
    }
}

// URLSession's callback boundary is controlled without opening a network connection.
// The only mutable state is protected by the lock; the stream is thread-safe.
private struct HeartbeatPing: Sendable {
    private let callback = OSAllocatedUnfairLock<(@Sendable (Error?) -> Void)?>(initialState: nil)
    private let started = AsyncStream<Void>.makeStream()

    func sendPing(pongReceiveHandler: @escaping @Sendable (Error?) -> Void) {
        callback.withLock { $0 = pongReceiveHandler }
        started.continuation.yield(())
        started.continuation.finish()
    }

    func waitForPing() async {
        for await _ in started.stream {}
    }

    func reply(_ error: Error?) {
        let handler = callback.withLock { $0 }
        handler?(error)
    }
}
