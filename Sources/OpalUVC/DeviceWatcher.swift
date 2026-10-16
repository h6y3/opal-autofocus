import Foundation
import IOKit

/// Calls `onAttach` for every matching camera already present and for each one attached later.
public final class DeviceWatcher {
    public enum WatcherError: Error, CustomStringConvertible {
        case alreadyStarted
        case ioKit(IOReturn, String)

        public var description: String {
            switch self {
            case .alreadyStarted: return "watcher already started"
            case .ioKit(let code, let what): return "\(what) failed: \(UVCError.name(of: code))"
            }
        }
    }

    private let models: [CameraModel]
    private let queue: DispatchQueue
    private let onAttach: (OpalDevice) -> Void
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    public init(models: [CameraModel] = KnownModels.all, queue: DispatchQueue = .main,
                onAttach: @escaping (OpalDevice) -> Void) {
        self.models = models
        self.queue = queue
        self.onAttach = onAttach
    }

    deinit { stop() }

    public func start() throws {
        guard port == nil else { throw WatcherError.alreadyStarted }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            throw WatcherError.ioKit(IOReturn(bitPattern: 0xe00002bc), "IONotificationPortCreate")  // kIOReturnError
        }
        IONotificationPortSetDispatchQueue(port, queue)
        self.port = port

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for model in models {
            var iterator: io_iterator_t = 0
            let kr = IOServiceAddMatchingNotification(
                port, kIOFirstMatchNotification, OpalDevice.matchingDictionary(for: model),
                { refcon, iterator in
                    guard let refcon else { return }
                    Unmanaged<DeviceWatcher>.fromOpaque(refcon).takeUnretainedValue().drain(iterator)
                },
                refcon, &iterator)
            guard kr == KERN_SUCCESS else {
                stop()
                throw WatcherError.ioKit(kr, "IOServiceAddMatchingNotification")
            }
            iterators.append(iterator)
            // Draining arms the notification and reports devices that are already attached.
            drain(iterator)
        }
    }

    public func stop() {
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators.removeAll()
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }

    private func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            guard let model = OpalDevice.model(for: service, among: models) else {
                IOObjectRelease(service)
                continue
            }
            onAttach(OpalDevice(service: service, model: model))
        }
    }
}
