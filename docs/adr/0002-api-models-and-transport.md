# ADR 0002. API models and transport

Status: accepted for the first slice.

## Decision

Build a small client on Foundation and `URLSession`. Public methods use `async throws`. DTOs conform to `Codable` and `Sendable`.

Add models by hand as methods are implemented. OpenAPI remains the source for field names, types, and HTTP status codes. Do not include a generated network client in the package.

Inject the HTTP transport into the client. This is the only replacement used in unit tests. The public API does not expose `URLRequest` or internal encoding details.

## Rationale

Swift OpenAPI Generator supports `generate: [types]`, but its output still includes `APIProtocol`, `Operations`, the `Components` namespace, and an `OpenAPIRuntime` dependency. For 27 operations, that adds more code and dependencies than this client needs.

`URLSession.data(for:)` already supports structured concurrency and task cancellation. The client does not create hidden `Task` instances or manage queues for the calling app.

## Platforms

The first package supports iOS 16 and macOS 13. Add older versions only after testing the relevant toolchain and dependencies.

## Sources

- [Apple: async/await with URLSession](https://developer.apple.com/videos/play/wwdc2021/10095/)
- [Swift OpenAPI Generator configuration](https://github.com/apple/swift-openapi-generator/blob/main/Sources/swift-openapi-generator/Documentation.docc/Articles/Configuring-the-generator.md)
- [Swift platform support](https://www.swift.org/platform-support/)
