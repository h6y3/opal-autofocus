import OpalUVC

protocol FocusTarget {
    var label: String { get }
    func focusRange() throws -> ClosedRange<Int>
    func setFocus(_ position: Int) throws
}

extension OpalDevice: FocusTarget {
    func focusRange() throws -> ClosedRange<Int> { try open().focusRange() }
    func setFocus(_ position: Int) throws { try open().setFocus(position) }
}

/// Applies one position to every camera, writing only after every reported range contains it.
func applyFocus(_ position: Int, to targets: [FocusTarget], log: (String) -> Void, fail: (String) -> Void) -> Int32 {
    guard !targets.isEmpty else {
        fail("no Opal camera attached")
        return ExitStatus.noDevice
    }

    var writable: [FocusTarget] = []
    var outOfRange = false
    var failed = false

    // Read every range before writing so an out-of-range position moves no camera.
    for target in targets {
        do {
            let range = try target.focusRange()
            if range.contains(position) {
                writable.append(target)
            } else {
                outOfRange = true
                fail("\(target.label): position \(position) is outside this camera's range \(range.lowerBound)...\(range.upperBound)")
            }
        } catch {
            failed = true
            fail("\(target.label): \(error)")
        }
    }
    // A usage mistake wins over request failures, so report ranges before writing.
    if outOfRange { return ExitStatus.usage }

    for target in writable {
        do {
            try target.setFocus(position)
            log("set focus position \(position) on \(target.label)")
        } catch {
            failed = true
            fail("\(target.label): \(error)")
        }
    }
    return failed ? ExitStatus.requestFailed : ExitStatus.ok
}
