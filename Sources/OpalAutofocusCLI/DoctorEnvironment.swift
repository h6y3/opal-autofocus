protocol DoctorEnvironment {
    var home: String { get }
    var userID: UInt32 { get }
    var executablePath: String { get }
    func fileExists(_ path: String) -> Bool
    func plist(at path: String) -> [String: Any]?   // nil when missing or unparseable
    func isLoaded(label: String) -> Bool
    func cameras() throws -> [CameraSnapshot]
    func lastLines(of path: String, count: Int) -> [String]?   // nil when the file is missing
}