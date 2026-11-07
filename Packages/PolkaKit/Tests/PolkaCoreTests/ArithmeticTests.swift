import Foundation
import Testing

@testable import PolkaCore

@Suite struct ArithmeticTests {
    @Test(arguments: [
        ("1 + 2 * 3", "7"),
        ("(1 + 2) * 3", "9"),
        ("0.1 + 0.2", "0.3"),
        ("1250 * 1,2", "1500"),
        ("2^10", "1024"),
        ("2^-2", "0.25"),
        ("-3 + 5", "2"),
        ("2400 * 15%", "360"),
        ("10 ÷ 4", "2.5"),
        ("7 × 6", "42"),
        ("2^3^2", "512"),
    ])
    func evaluates(_ input: String, _ expected: String) throws {
        #expect(try Arithmetic.evaluate(input) == Decimal(string: expected)!)
    }

    @Test func rejectsDivisionByZero() {
        #expect(throws: Arithmetic.Failure.divisionByZero) { try Arithmetic.evaluate("1/0") }
    }

    @Test func rejectsCode() {
        #expect(throws: Arithmetic.Failure.self) { try Arithmetic.evaluate("process.exit()") }
    }

    @Test func rejectsUnbalancedParentheses() {
        #expect(throws: Arithmetic.Failure.unexpectedEnd) { try Arithmetic.evaluate("(1 + 2") }
    }

    @Test func rejectsHugeExponents() {
        #expect(throws: Arithmetic.Failure.tooComplex) { try Arithmetic.evaluate("10^100000") }
    }

    @Test func rejectsDeepNesting() {
        let input = String(repeating: "(", count: 100) + "1" + String(repeating: ")", count: 100)
        #expect(throws: Arithmetic.Failure.tooComplex) { try Arithmetic.evaluate(input) }
    }
}
