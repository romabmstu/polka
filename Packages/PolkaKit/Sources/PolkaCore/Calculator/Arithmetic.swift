import Foundation

/// Arithmetic for the quick calculator.
///
/// A small recursive-descent parser over `Decimal`, so `0.1 + 0.2` is `0.3`
/// and nothing typed by the user is ever evaluated as code.
///
///     expression := term (("+" | "-") term)*
///     term       := power (("*" | "/" | "%") power)*
///     power      := unary ("^" power)?
///     unary      := ("-" | "+") unary | postfix
///     postfix    := primary "%"?          // 15% means 0.15
///     primary    := number | "(" expression ")"
public enum Arithmetic {
    public enum Failure: Error, Equatable {
        case empty
        case unexpectedCharacter(Character)
        case unexpectedEnd
        case divisionByZero
        case tooComplex
    }

    public static func evaluate(_ input: String) throws(Failure) -> Decimal {
        var parser = Parser(input)
        guard !parser.isAtEnd else { throw .empty }
        let value = try parser.expression()
        if let c = parser.peek() { throw .unexpectedCharacter(c) }
        return value
    }

    private struct Parser {
        private let chars: [Character]
        private var index = 0
        private var depth = 0

        init(_ input: String) {
            chars = input
                .replacingOccurrences(of: "×", with: "*")
                .replacingOccurrences(of: "÷", with: "/")
                .replacingOccurrences(of: "−", with: "-")
                .filter { !$0.isWhitespace && $0 != "\u{00A0}" }
                .map { $0 }
        }

        var isAtEnd: Bool { index >= chars.count }

        func peek() -> Character? { isAtEnd ? nil : chars[index] }

        mutating func expression() throws(Failure) -> Decimal {
            var value = try term()
            while let op = peek(), op == "+" || op == "-" {
                index += 1
                let rhs = try term()
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func term() throws(Failure) -> Decimal {
            var value = try power()
            while let op = peek(), op == "*" || op == "/" {
                index += 1
                let rhs = try power()
                if op == "*" {
                    value *= rhs
                } else {
                    guard !rhs.isZero else { throw .divisionByZero }
                    value /= rhs
                }
            }
            return value
        }

        mutating func power() throws(Failure) -> Decimal {
            let base = try unary()
            guard peek() == "^" else { return base }
            index += 1
            let exponent = try power()
            guard exponent.isWhole, abs(exponent) <= 1_000 else { throw .tooComplex }
            let n = NSDecimalNumber(decimal: exponent).intValue
            let magnitude = Foundation.pow(base, abs(n))
            if n >= 0 { return magnitude }
            guard !magnitude.isZero else { throw .divisionByZero }
            return 1 / magnitude
        }

        mutating func unary() throws(Failure) -> Decimal {
            guard let c = peek(), c == "-" || c == "+" else { return try postfix() }
            index += 1
            let value = try unary()
            return c == "-" ? -value : value
        }

        mutating func postfix() throws(Failure) -> Decimal {
            let value = try primary()
            if peek() == "%" {
                index += 1
                return value / 100
            }
            return value
        }

        mutating func primary() throws(Failure) -> Decimal {
            guard let c = peek() else { throw .unexpectedEnd }
            if c == "(" {
                depth += 1
                guard depth <= 64 else { throw .tooComplex }
                index += 1
                let value = try expression()
                guard let close = peek() else { throw Failure.unexpectedEnd }
                guard close == ")" else { throw Failure.unexpectedCharacter(close) }
                index += 1
                depth -= 1
                return value
            }
            return try number()
        }

        mutating func number() throws(Failure) -> Decimal {
            let start = index
            var seenSeparator = false
            while let c = peek() {
                if c.isASCII, c.isNumber {
                    index += 1
                } else if (c == "." || c == ","), !seenSeparator {
                    seenSeparator = true
                    index += 1
                } else {
                    break
                }
            }
            guard index > start else {
                if let c = peek() { throw .unexpectedCharacter(c) }
                throw .unexpectedEnd
            }
            let literal = String(chars[start..<index]).replacingOccurrences(of: ",", with: ".")
            guard literal.count <= 40, let value = Decimal(string: literal, locale: Locale(identifier: "en_US_POSIX"))
            else { throw .tooComplex }
            return value
        }
    }
}

extension Decimal {
    fileprivate var isWhole: Bool {
        var source = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        return rounded == self
    }
}
