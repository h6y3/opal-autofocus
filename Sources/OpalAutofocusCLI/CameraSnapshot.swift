import OpalUVC

/// One camera at the moment its status was read, as `status --json` and `doctor` show it.
struct CameraSnapshot: Equatable {
    let model: String
    let serial: String?
    let location: String
    let label: String
    let reading: Reading

    enum Reading: Equatable {
        case status(FocusStatus)
        case failed(String)
    }

    static func take(_ device: OpalDevice) -> CameraSnapshot {
        var reading: Reading
        do {
            reading = .status(try device.open().focusStatus())
        } catch {
            reading = .failed("\(error)")
        }
        return CameraSnapshot(
            model: device.model.name, serial: device.serial, location: device.locationString,
            label: device.label, reading: reading)
    }
}