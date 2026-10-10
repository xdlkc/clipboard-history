import XCTest
@testable import ClipboardCore

final class PreviewImageFileTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewImageFileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testShouldLoadDecision() {
        XCTAssertEqual(PreviewImageFile.maxBytes, 20 * 1024 * 1024)
        XCTAssertFalse(PreviewImageFile.shouldLoad(fileSize: nil), "取不到大小不读")
        XCTAssertFalse(PreviewImageFile.shouldLoad(fileSize: 0))
        XCTAssertTrue(PreviewImageFile.shouldLoad(fileSize: 1))
        XCTAssertTrue(PreviewImageFile.shouldLoad(fileSize: 20 * 1024 * 1024))
        XCTAssertFalse(PreviewImageFile.shouldLoad(fileSize: 20 * 1024 * 1024 + 1))
        XCTAssertFalse(PreviewImageFile.shouldLoad(fileSize: 500 * 1024 * 1024))
    }

    func testSmallFileIsRead() throws {
        let url = dir.appendingPathComponent("small.png")
        try Data([1, 2, 3, 4]).write(to: url)
        XCTAssertEqual(PreviewImageFile.fileSize(atPath: url.path), 4)
        XCTAssertEqual(PreviewImageFile.read(atPath: url.path), Data([1, 2, 3, 4]))
    }

    func testOversizedFileIsNotRead() throws {
        let url = dir.appendingPathComponent("huge.tiff")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(PreviewImageFile.maxBytes + 1))
        try handle.close()

        XCTAssertEqual(PreviewImageFile.fileSize(atPath: url.path), PreviewImageFile.maxBytes + 1)
        XCTAssertNil(PreviewImageFile.read(atPath: url.path))
        XCTAssertNotNil(PreviewImageFile.read(atPath: url.path, maxBytes: PreviewImageFile.maxBytes + 1))
    }

    func testMissingFileAndDirectoryAreNotRead() {
        let missing = dir.appendingPathComponent("gone.png").path
        XCTAssertNil(PreviewImageFile.fileSize(atPath: missing))
        XCTAssertNil(PreviewImageFile.read(atPath: missing))
        XCTAssertNil(PreviewImageFile.fileSize(atPath: dir.path))
        XCTAssertNil(PreviewImageFile.read(atPath: dir.path))
        XCTAssertNil(PreviewImageFile.read(atPath: "/Volumes/DisconnectedNAS-\(UUID().uuidString)/photo.jpg"))
    }
}
