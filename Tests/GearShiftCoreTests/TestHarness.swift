import Foundation

var passes = 0
var failures = 0

func expect(_ condition: Bool, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    if condition {
        passes += 1
    } else {
        failures += 1
        print("  ✗ \(file):\(line) \(message())")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #fileID, line: UInt = #line) {
    expect(actual == expected, "expected \(expected), got \(actual)", file: file, line: line)
}

/// Runs one group of checks; an uncaught error counts as a failure.
func suite(_ name: String, _ body: () throws -> Void) {
    print("▸ \(name)")
    do {
        try body()
    } catch {
        failures += 1
        print("  ✗ threw \(error)")
    }
}

func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("gearshift-tests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func append(_ text: String, to url: URL) throws {
    try append(Data(text.utf8), to: url)
}

func append(_ data: Data, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
}
