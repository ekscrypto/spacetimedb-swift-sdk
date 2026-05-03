import Testing
import Foundation
@testable import SpacetimeDB
@testable import BSATN

@Suite("BsatnRowList Tests")
struct BsatnRowListTests {

    @Test("Create empty BsatnRowList")
    func createEmptyRowList() throws {
        let rowList = BsatnRowList(rows: [])

        #expect(rowList.rows.isEmpty)
    }

    @Test("Create BsatnRowList with single row")
    func createSingleRowList() throws {
        let rowData = Data([0x01, 0x02, 0x03, 0x04])
        let rowList = BsatnRowList(rows: [rowData])

        #expect(rowList.rows.count == 1)
        #expect(rowList.rows[0] == rowData)
    }

    @Test("Create BsatnRowList with multiple rows")
    func createMultipleRowsList() throws {
        let row1 = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let row2 = Data([0x06, 0x07, 0x08, 0x09, 0x0A])
        let row3 = Data([0x0B, 0x0C, 0x0D, 0x0E])

        let rowList = BsatnRowList(rows: [row1, row2, row3])

        #expect(rowList.rows.count == 3)
        #expect(rowList.rows[0] == row1)
        #expect(rowList.rows[1] == row2)
        #expect(rowList.rows[2] == row3)
    }

    @Test("Create BsatnRowList with variable length rows")
    func createVariableLengthRows() throws {
        let row1 = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A])
        let row2 = Data([0x0B, 0x0C, 0x0D])

        let rowList = BsatnRowList(rows: [row1, row2])

        #expect(rowList.rows.count == 2)
        #expect(rowList.rows[0] == row1)
        #expect(rowList.rows[1] == row2)
    }
}