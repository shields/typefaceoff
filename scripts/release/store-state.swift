import CryptoKit
import Foundation

func base64URL(_ data: Data) -> String {
  data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

let env = ProcessInfo.processInfo.environment
let header = try JSONSerialization.data(withJSONObject: [
  "alg": "ES256", "kid": env["ASC_KEY_ID"]!, "typ": "JWT",
])
let now = Int(Date().timeIntervalSince1970)
let claims = try JSONSerialization.data(withJSONObject: [
  "iss": env["ASC_ISSUER_ID"]!, "iat": now, "exp": now + 300, "aud": "appstoreconnect-v1",
])
let payload = base64URL(header) + "." + base64URL(claims)
let key = try P256.Signing.PrivateKey(
  pemRepresentation: String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
)
let signature = try key.signature(for: Data(payload.utf8))
var url = URLComponents(string: "https://api.appstoreconnect.apple.com/v1/builds")!
url.queryItems = [
  URLQueryItem(name: "filter[app]", value: env["ASC_APP_ID"]!),
  URLQueryItem(name: "filter[preReleaseVersion.platform]", value: "MAC_OS"),
  URLQueryItem(name: "filter[version]", value: CommandLine.arguments[1]),
  URLQueryItem(name: "sort", value: "-uploadedDate"),
  URLQueryItem(name: "limit", value: "1"),
]
var request = URLRequest(url: url.url!)
request.setValue(
  "Bearer " + payload + "." + base64URL(signature.rawRepresentation),
  forHTTPHeaderField: "Authorization")
let (response, metadata) = try await URLSession.shared.data(for: request)
guard let http = metadata as? HTTPURLResponse, http.statusCode == 200 else {
  throw URLError(.badServerResponse)
}
struct Builds: Decodable {
  struct Build: Decodable {
    struct Attributes: Decodable { let processingState: String }
    let attributes: Attributes
  }
  let data: [Build]
}
print(
  try JSONDecoder().decode(Builds.self, from: response).data.first?.attributes.processingState
    ?? "ABSENT")
