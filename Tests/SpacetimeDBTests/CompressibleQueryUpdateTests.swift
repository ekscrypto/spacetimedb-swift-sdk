import Testing
import Foundation
import Compression
@testable import SpacetimeDB
@testable import BSATN

@Suite("CompressibleQueryUpdate Tests")
struct CompressibleQueryUpdateTests {

    @Test("Parse uncompressed CompressibleQueryUpdate")
    func parseUncompressedQueryUpdate() throws {
        // Create QueryUpdate directly
        let insertRows = [Data([0x01, 0x02, 0x03])]
        let deleteRows: [Data] = []

        let queryUpdate = QueryUpdate(
            deletes: BsatnRowList(rows: deleteRows),
            inserts: BsatnRowList(rows: insertRows)
        )

        let compressible = CompressibleQueryUpdate.uncompressed(queryUpdate)
        let result = try compressible.getQueryUpdate()

        #expect(result.inserts.rows.count == 1)
        #expect(result.inserts.rows[0] == insertRows[0])
        #expect(result.deletes.rows.isEmpty)
    }

    @Test("CompressibleQueryUpdate with Brotli compression")
    @available(iOS 15.0, macOS 12.0, *)
    func brotliCompressedQueryUpdate() throws {
        // Create test data
        let insertRows = [
            Data([0x01, 0x02, 0x03, 0x04]),
            Data([0x05, 0x06, 0x07, 0x08])
        ]
        let deleteRows: [Data] = []

        // Create QueryUpdate
        let queryUpdate = QueryUpdate(
            deletes: BsatnRowList(rows: deleteRows),
            inserts: BsatnRowList(rows: insertRows)
        )

        // Construct what a real server would send (post-fix, matching the
        // SpacetimeDB BsatnRowList wire format):
        //   BsatnRowList = { size_hint: u8 tag + variant payload, rows_data }
        //   tag 0 = FixedSize(u16); tag 1 = RowOffsets(u32 count + count*u64)
        //   rows_data = u32 size + size bytes
        let writer = BSATNWriter()

        // Deletes: empty list expressed as FixedSize(0)/data=0
        writer.write(UInt8(0))                  // hint tag = FixedSize
        writer.write(UInt16(0))                 // fixed size = 0 (no rows)
        writer.write(UInt32(0))                 // data size = 0

        // Inserts: 2 rows of 4 bytes each via RowOffsets
        writer.write(UInt8(1))                  // hint tag = RowOffsets
        writer.write(UInt32(2))                 // offset count
        writer.write(UInt64(0))                 // row 0 starts at offset 0
        writer.write(UInt64(4))                 // row 1 starts at offset 4
        writer.write(UInt32(8))                 // data size
        writer.write(Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]))

        let uncompressedData = writer.finalize()

        // Compress using Brotli
        let compressedData = uncompressedData.withUnsafeBytes { sourceBuffer in
            guard let sourcePtr = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return Data()
            }

            let destBufferSize = uncompressedData.count * 2 + 1024
            let destBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destBufferSize)
            defer { destBuffer.deallocate() }

            let compressedSize = compression_encode_buffer(
                destBuffer, destBufferSize,
                sourcePtr, uncompressedData.count,
                nil, COMPRESSION_BROTLI
            )

            guard compressedSize > 0 else { return Data() }
            return Data(bytes: destBuffer, count: compressedSize)
        }

        #expect(compressedData.count > 0)

        let compressible = CompressibleQueryUpdate.brotli(compressedData)
        let result = try compressible.getQueryUpdate()

        #expect(result.inserts.rows.count == 2)
        #expect(result.inserts.rows[0] == insertRows[0])
        #expect(result.inserts.rows[1] == insertRows[1])
        #expect(result.deletes.rows.isEmpty)
    }

    @Test("CompressibleQueryUpdate with both inserts and deletes")
    func queryUpdateWithInsertsAndDeletes() throws {
        let insertRows = [Data([0xAA, 0xBB])]
        let deleteRows = [Data([0xCC, 0xDD])]

        let queryUpdate = QueryUpdate(
            deletes: BsatnRowList(rows: deleteRows),
            inserts: BsatnRowList(rows: insertRows)
        )

        let compressible = CompressibleQueryUpdate.uncompressed(queryUpdate)
        let result = try compressible.getQueryUpdate()

        #expect(result.inserts.rows.count == 1)
        #expect(result.inserts.rows[0] == insertRows[0])
        #expect(result.deletes.rows.count == 1)
        #expect(result.deletes.rows[0] == deleteRows[0])
    }

    @Test("Reject malformed GZIP payload")
    func malformedGzipCompression() throws {
        // Phase 9 added gzip support — bogus bytes should still fail
        // cleanly rather than crashing.
        let compressible = CompressibleQueryUpdate.gzip(Data(repeating: 0, count: 10))
        #expect(throws: BSATNError.self) {
            _ = try compressible.getQueryUpdate()
        }
    }
}