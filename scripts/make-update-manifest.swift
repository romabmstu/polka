// Signs an update archive and prints its update.json.
//
//   UPDATE_SIGNING_KEY=<base64 Ed25519 seed> EXPECTED_UPDATE_PUBLIC_KEY=<base64 public key> \
//       swift scripts/make-update-manifest.swift \
//       <zip> <version> <build> <stable|beta> <download-url> <minimum-macos> <notes-file>
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 8, let build = Int(args[3]), ["stable", "beta"].contains(args[4]) else {
    FileHandle.standardError.write(Data("usage: make-update-manifest <zip> <version> <build> <channel> <url> <min-macos> <notes>\n".utf8))
    exit(2)
}

guard
    // Tolerate what copy and paste adds around a secret: spaces, line
    // breaks, quotes.
    let encoded = ProcessInfo.processInfo.environment["UPDATE_SIGNING_KEY"]?
        .filter({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/=".contains($0)) }),
    let seed = Data(base64Encoded: encoded),
    let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed)
else {
    FileHandle.standardError.write(Data("UPDATE_SIGNING_KEY is missing or invalid\n".utf8))
    exit(1)
}

guard let expected = ProcessInfo.processInfo.environment["EXPECTED_UPDATE_PUBLIC_KEY"],
    key.publicKey.rawRepresentation.base64EncodedString() == expected
else {
    FileHandle.standardError.write(Data("UPDATE_SIGNING_KEY does not match the app's update public key\n".utf8))
    exit(1)
}

let archive = try Data(contentsOf: URL(fileURLWithPath: args[1]))
let signature = try key.signature(for: archive)
guard key.publicKey.isValidSignature(signature, for: archive) else { exit(1) }

let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
let notes = (try? String(contentsOfFile: args[7], encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

let manifest: [String: Any] = [
    "version": args[2],
    "build": build,
    "channel": args[4],
    "url": args[5],
    "size": archive.count,
    "sha256": digest,
    "signature": signature.base64EncodedString(),
    "minimumSystemVersion": args[6],
    "notes": String(notes.prefix(4000)),
    "publishedAt": ISO8601DateFormatter().string(from: Date()),
]
let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
FileHandle.standardOutput.write(json)
FileHandle.standardOutput.write(Data("\n".utf8))
