import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// ====== Models ======
struct CreateGameResponse: Codable {
    let game_id: String
}

struct GuessResponse: Codable {
    let black: Int
    let white: Int
}

struct ErrorResponse: Codable {
    let error: String
}

// ====== API Client ======
enum APIError: Error, CustomStringConvertible {
    case badStatus(Int, String?)
    case decoding(Error)
    case network(Error)
    case invalidURL

    var description: String {
        switch self {
        case .badStatus(let code, let msg):
            return "HTTP \(code)\(msg.map { ": \($0)" } ?? "")"
        case .decoding(let err): return "Decoding error: \(err)"
        case .network(let err):  return "Network error: \(err)"
        case .invalidURL:        return "Invalid URL"
        }
    }
}

final class MastermindAPI {
    let baseURL = URL(string: "https://mastermind.darkube.app")!
    let json = JSONEncoder()
    let session: URLSession = .shared

    func createGame() async throws -> String {
        var url = baseURL
        url.appendPathComponent("game")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw APIError.invalidURL }
            if http.statusCode == 200 || http.statusCode == 201 {
                return try JSONDecoder().decode(CreateGameResponse.self, from: data).game_id
            } else {
                let serverMsg = try? JSONDecoder().decode(ErrorResponse.self, from: data).error
                throw APIError.badStatus(http.statusCode, serverMsg)
            }
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.network(error)
        }
    }

    func makeGuess(gameID: String, guess: String) async throws -> GuessResponse {
        var url = baseURL
        url.appendPathComponent("guess")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: String] = [
            "game_id": gameID,
            "guess": guess
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw APIError.invalidURL }
            if http.statusCode == 200 {
                return try JSONDecoder().decode(GuessResponse.self, from: data)
            } else {
                let serverMsg = try? JSONDecoder().decode(ErrorResponse.self, from: data).error
                throw APIError.badStatus(http.statusCode, serverMsg)
            }
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.network(error)
        }
    }

    func deleteGame(gameID: String) async {
        var url = baseURL
        url.appendPathComponent("game")
        url.appendPathComponent(gameID)
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        _ = try? await session.data(for: req) // best-effort; ignore errors
    }
}

// ====== CLI Game (API-backed) ======
struct GameConfig {
    let codeLength = 4
    let digitsRange = 1...6
    let maxAttempts = 10 // keep local cap for UX; server does not enforce
}

final class MastermindCLI {
    private let api = MastermindAPI()
    private let cfg = GameConfig()
    private var gameID: String?
    private var attempts = 0

    func run() async {
        printBanner()
        do {
            let id = try await api.createGame()
            self.gameID = id
            print("New game created. id=\(id)")
        } catch {
            print("Failed to create game: \(error)")
            return
        }

        while attempts < cfg.maxAttempts {
            print("\nGuess \(attempts + 1)/\(cfg.maxAttempts) — enter a \(cfg.codeLength)-digit code using digits \(cfg.digitsRange.lowerBound)-\(cfg.digitsRange.upperBound) (or type 'exit'):", terminator: " ")
            guard let line = readLine() else {
                print("\nExiting.")
                await cleanup()
                return
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased() == "exit" {
                print("Exit requested.")
                await cleanup()
                return
            }

            guard let guess = parseGuess(trimmed) else {
                print("Invalid input. Example: 1234 (exactly \(cfg.codeLength) digits, each between \(cfg.digitsRange.lowerBound) and \(cfg.digitsRange.upperBound)).")
                continue
            }

            attempts += 1
            do {
                guard let id = gameID else { print("Game not initialized."); await cleanup(); return }
                let resp = try await api.makeGuess(gameID: id, guess: guess)
                let hint = String(repeating: "B", count: resp.black) + String(repeating: "W", count: resp.white)
                print("Result: \(hint.isEmpty ? "—" : hint)  (B=\(resp.black), W=\(resp.white))")

                if resp.black == cfg.codeLength {
                    print("You win in \(attempts) attempts.")
                    await cleanup()
                    return
                }
            } catch let err as APIError {
                print("API error: \(err.description)")
                if case .badStatus(let code, _) = err, code == 404 {
                    print("Game not found on server. Exiting.")
                    return
                }
            } catch {
                print("Unexpected error: \(error)")
            }
        }

        print("Out of attempts. Game over.")
        await cleanup()
    }

    private func parseGuess(_ s: String) -> String? {
        guard s.count == cfg.codeLength, s.allSatisfy({ $0.isNumber }) else { return nil }
        let digits = s.compactMap { Int(String($0)) }
        guard digits.count == cfg.codeLength, digits.allSatisfy({ cfg.digitsRange.contains($0) }) else { return nil }
        return s
    }

    private func printBanner() {
        print("""
        ---------------------------
                Mastermind
        ---------------------------
        API-backed mode
        Rules:
        • Each guess is a \(cfg.codeLength)-digit code using digits \(cfg.digitsRange.lowerBound)-\(cfg.digitsRange.upperBound).
        • Type 'exit' to quit at any time.
        • Feedback:
          - B: right digit in the right position
          - W: right digit in the wrong position
        """)
    }

    private func cleanup() async {
        if let id = gameID {
            await api.deleteGame(gameID: id)
        }
    }
}

// ====== Entry point ======
@main
struct App {
    static func main() async {
        let cli = MastermindCLI()
        await cli.run()
    }
}
