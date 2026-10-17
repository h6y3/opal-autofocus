import Foundation
import IOKit

/// Reports attach, and detach when a detach handler is given, for every matching camera.
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

    // Carries the model to the detach callback: a terminated service may have lost its registry properties.
    private final class Registration {
        unowned let watcher: DeviceWatcher
        let model: CameraModel

        init(watcher: DeviceWatcher, model: CameraModel) {
            self.watcher = watcher
            self.model = model
        }
    }

    private let models: [CameraModel]
    private let queue: DispatchQueue
    private let onAttach: (OpalDevice) -> Void
    private let onDetach: ((OpalDevice) -> Void)?
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var terminatedIterators: [io_iterator_t] = []
    private var registrations: [Registration] = []

    public init(models: [CameraModel] = KnownModels.all, queue: DispatchQueue = .main,
                onAttach: @escaping (OpalDevice) -> Void,
                onDetach: ((OpalDevice) -> Void)? = nil) {
        self.models = models
        self.queue = queue
        self.onAttach = onAttach
        self.onDetach = onDetach
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

            if onDetach != nil {
                let registration = Registration(watcher: self, model: model)
                var terminated: io_iterator_t = 0
                let tkr = IOServiceAddMatchingNotification(
                    port, kIOTerminatedNotification, OpalDevice.matchingDictionary(for: model),
                    { refcon, iterator in
                        guard let refcon else { return }
                        let registration = Unmanaged<Registration>.fromOpaque(refcon).takeUnretainedValue()
                        registration.watcher.drainTerminated(iterator, model: registration.model)
                    },
                    Unmanaged.passUnretained(registration).toOpaque(), &terminated)
                guard tkr == KERN_SUCCESS else {
                    stop()
                    throw WatcherError.ioKit(tkr, "IOServiceAddMatchingNotification")
                }
                terminatedIterators.append(terminated)
                registrations.append(registration)
                // Draining arms the terminated notification; it reports nothing at start.
                drainTerminated(terminated, model: model)
            }
        }
    }

    public func stop() {
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators.removeAll()
        for iterator in terminatedIterators { IOObjectRelease(iterator) }
        terminatedIterators.removeAll()
        registrations.removeAll()
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

    private func drainTerminated(_ iterator: io_iterator_t, model: CameraModel) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            onDetach?(OpalDevice(service: service, model: model))
        }
    }
}
