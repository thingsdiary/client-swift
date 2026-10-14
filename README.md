# thingsdiary Swift client

A Swift library for the thingsdiary API. The macOS and iOS apps use this package.

The client:

- parses and generates the frontend-compatible `TDKV1` secret-key format;
- derives the same Ed25519 and X25519 keys as the Go and JavaScript clients;
- reads data encrypted by those clients and produces data they can read;
- provides a small asynchronous API built on `URLSession`;
- follows `thingsd/api/openapi/openapi.yaml` without a generated network layer.

The current scope is documented in [docs/scope.md](docs/scope.md). Architecture decisions live in `docs/adr`.

## Usage

```swift
import ThingsDiaryClient

let client = ThingsDiaryClient()
let secretKey = try ThingsDiarySecretKey.parse(userInput)
try await client.login(
    login: login,
    password: password,
    secretKey: secretKey.rawValue
)
let diaries = try await client.diaries()
```

The package supports iOS 16 and macOS 13. Authentication state and keys remain in the client instance's memory.

## Tests

The default test run does not use the network:

```sh
swift test
```

The production integration test creates a disposable user and one encrypted diary. It then signs in with a new client instance and loads the diary:

```sh
THINGSDIARY_LIVE_TESTS=1 swift test --filter productionRegistrationLoginAndDiaries
```

The live test is disabled by default because it writes data to the production server.
