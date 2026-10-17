import Foundation
import OpalUVC

/// Renders snapshots as the JSON documented in the README's Scripting section.
enum StatusJSON {
    static let schema = 1

    static func render(_ cameras: [CameraSnapshot]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = Payload(cameras: cameras.map(View.init), schema: schema)
        let data = try! encoder.encode(payload)
        return String(decoding: data, as: UTF8.self)
    }

    private struct View: Encodable {
        let camera: CameraSnapshot

        private enum Keys: String, CodingKey {
            case model, serial, location, autofocus, position, minimum, maximum
            case `default`, error
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode(camera.model, forKey: .model)
            if let serial = camera.serial {
                try container.encode(serial, forKey: .serial)
            } else {
                try container.encodeNil(forKey: .serial)
            }
            try container.encode(camera.location, forKey: .location)
            switch camera.reading {
            case .status(let focus):
                try container.encode(focus.autofocus, forKey: .autofocus)
                try container.encode(focus.position, forKey: .position)
                try container.encode(focus.minimum, forKey: .minimum)
                try container.encode(focus.maximum, forKey: .maximum)
                try container.encode(focus.defaultPosition, forKey: .default)
            case .failed(let message):
                try container.encode(message, forKey: .error)
            }
        }
    }

    private struct Payload: Encodable {
        let cameras: [View]
        let schema: Int
    }
}