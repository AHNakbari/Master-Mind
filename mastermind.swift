import Foundation

struct Mastermind {
    let codeLength: Int = 4
    let digitsRange = 1...6
    let maxAttempts: Int = 10  // change if you want more/less attempts

    private(set) var secret: [Int] = []
    private(set) var attempts = 0

    init() {
        secret = (0..<codeLength).map { _ in Int.random(in: digitsRange) }
    }

    mutating func play() {
        printBanner()
        while attempts < maxAttempts {
            print("\nGuess \(attempts + 1)/\(maxAttempts) — enter a \(codeLength)-digit code using digits \(digitsRange.lowerBound)-\(digitsRange.upperBound) (or type 'exit'):", terminator: " ")
            guard let line = readLine() else { print("\nExiting."); return }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased() == "exit" { print("Exit. Goodbye."); return }

            guard let guess = parseGuess(trimmed) else {
                print("Invalid input. Example: 1234 (exactly \(codeLength) digits, each between \(digitsRange.lowerBound) and \(digitsRange.upperBound)).")
                continue
            }

            attempts += 1
            let (b, w) = score(guess: guess, secret: secret)
            let hint = String(repeating: "B", count: b) + String(repeating: "W", count: w)
            print("Result: \(hint.isEmpty ? "—" : hint)  (B=\(b), W=\(w))")

            if b == codeLength {
                print("You win. The secret was \(secret.map(String.init).joined()). Attempts: \(attempts).")
                return
            }
        }

        print("You lost. The secret was \(secret.map(String.init).joined()).")
    }

    private func parseGuess(_ s: String) -> [Int]? {
        guard s.count == codeLength, s.allSatisfy({ $0.isNumber }) else { return nil }
        let digits = s.compactMap { Int(String($0)) }
        guard digits.count == codeLength, digits.allSatisfy({ digitsRange.contains($0) }) else { return nil }
        return digits
    }

    // Calculates B (blacks) and W (whites). Repeated digits are allowed.
    private func score(guess: [Int], secret: [Int]) -> (Int, Int) {
        var blacks = 0
        var secretR: [Int] = []
        var guessR: [Int] = []

        for i in 0..<codeLength {
            if guess[i] == secret[i] {
                blacks += 1
            } else {
                secretR.append(secret[i])
                guessR.append(guess[i])
            }
        }

        var countsS = [Int](repeating: 0, count: digitsRange.count)
        var countsG = [Int](repeating: 0, count: digitsRange.count)
        for v in secretR { countsS[v - digitsRange.lowerBound] += 1 }
        for v in guessR { countsG[v - digitsRange.lowerBound] += 1 }

        var whites = 0
        for i in 0..<countsS.count { whites += min(countsS[i], countsG[i]) }

        return (blacks, whites)
    }

    private func printBanner() {
        print("""
        ---------------------------
                Mastermind
        ---------------------------
        Rules:
        • Each guess is a \(codeLength)-digit code using digits \(digitsRange.lowerBound)-\(digitsRange.upperBound).
        • Type 'exit' to quit at any time.
        • Feedback:
          - B: right digit in the right position
          - W: right digit in the wrong position
        Example: BBBW means 3 blacks and 1 white.
        """)
    }
}

extension ClosedRange where Bound == Int {
    var count: Int { upperBound - lowerBound + 1 }
}

var game = Mastermind()
game.play()
