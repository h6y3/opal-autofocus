import Testing
import Foundation
@testable import OpalUVC

@Suite(.serialized) struct DeviceWatcherTests {
    @Test func startReportsAlreadyAttachedDevices() throws {
        let present = try OpalDevice.find().count
        let queue = DispatchQueue(label: "watcher-test")
        let seen = LockedBox<[CameraModel]>([])
        let watcher = DeviceWatcher(queue: queue) { device in seen.mutate { $0.append(device.model) } }
        try watcher.start()
        queue.sync {}  // initial scan runs synchronously inside start(); drain anything queued
        watcher.stop()
        #expect(seen.value.count == present)
        for model in seen.value { #expect(KnownModels.all.contains(model)) }
    }

    @Test func startWithDetachHandlerReportsAttachOnly() throws {
        let present = try OpalDevice.find().count
        let queue = DispatchQueue(label: "watcher-test-detach")
        let counts = LockedBox<(attached: Int, detached: Int)>((0, 0))
        let watcher = DeviceWatcher(
            queue: queue,
            onAttach: { _ in counts.mutate { $0.attached += 1 } },
            onDetach: { _ in counts.mutate { $0.detached += 1 } })
        try watcher.start()
        queue.sync {}  // initial scan runs synchronously inside start(); drain anything queued
        #expect(counts.value.attached == present)
        #expect(counts.value.detached == 0)
        watcher.stop()

        counts.mutate { $0 = (0, 0) }
        try watcher.start()
        queue.sync {}
        #expect(counts.value.attached == present)
        #expect(counts.value.detached == 0)
        watcher.stop()
    }

    @Test func startTwiceThrows() throws {
        let watcher = DeviceWatcher(queue: DispatchQueue(label: "w")) { _ in }
        try watcher.start()
        #expect(throws: DeviceWatcher.WatcherError.self) { try watcher.start() }
        watcher.stop()
    }

    @Test func stopIsIdempotentAndAllowsRestart() throws {
        let watcher = DeviceWatcher(queue: DispatchQueue(label: "w2")) { _ in }
        try watcher.start()
        watcher.stop()
        watcher.stop()
        try watcher.start()
        watcher.stop()
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.withLock { stored } }
    func mutate(_ body: (inout T) -> Void) { lock.withLock { body(&stored) } }
}
