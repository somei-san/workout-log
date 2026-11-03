import Testing
@testable import WorkoutLog

struct NumberInputTests {
    @Test func 重さとRPEの欄は数字と最初のドット1つだけを残す() {
        #expect(NumberInput.decimal("102.5") == "102.5")
        #expect(NumberInput.decimal("8a.5") == "8.5")
        #expect(NumberInput.decimal("1.2.3") == "1.23")
        #expect(NumberInput.decimal("-8+") == "8")
        #expect(NumberInput.decimal("8,5") == "85")
    }

    @Test func 回数とRIRの欄は数字だけを残す() {
        #expect(NumberInput.integer("10") == "10")
        #expect(NumberInput.integer("1.5") == "15")
        #expect(NumberInput.integer("2+") == "2")
        #expect(NumberInput.integer("abc") == "")
    }

    @Test func 全角の数字とドットは半角にして残す() {
        #expect(NumberInput.decimal("１０２．５") == "102.5")
        #expect(NumberInput.integer("１０") == "10")
    }
}
