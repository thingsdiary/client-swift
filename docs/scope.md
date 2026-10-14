# Scope

## Context

`thingsd` already has Go and JavaScript clients. Their code defines the API and encryption protocol currently in use. The Swift Package is the shared client library for the macOS and iOS apps.

The product and project are named `thingsdiary`. `thingsd` remains the server name.

## Goal 1. Swift library

The first goal delivers:

- a Swift Package in `td/client-swift`;
- a compatible cryptography module;
- an asynchronous API client;
- request and response models based on OpenAPI;
- tests with fixed vectors from the Go and JavaScript clients;
- integration tests that exchange encrypted data between all three clients;
- an ADR that records the cryptography dependencies and the reasons for choosing them.

The existing clients define the cryptographic protocol:

1. PBKDF2-HMAC-SHA256 with 650,000 iterations and a 32-byte output.
2. HKDF-SHA256 without an explicit salt. `info` is `thingsdiary-ed25519-v1` or `thingsdiary-x25519-v1`.
3. Ed25519 signatures.
4. X25519 and NaCl sealed boxes for key encryption.
5. AES-256-GCM with a 12-byte nonce for data encryption.

OpenAPI defines the models and routes. The Go and JavaScript clients clarify details that the specification omits, including cryptography and byte encoding.

## Goal 2. macOS app

After the library is ready, the app in `td/thingsdiary-mac` must:

- accept a login and password;
- request a challenge;
- accept a `TDKV1` secret key, derive keys in memory, and sign the challenge;
- complete authentication and show the diary list;
- run network and cryptographic work away from the main thread;
- discard all state when the app exits.

Persistence, registration, offline synchronization, and the entries screen are outside the first macOS slice.

## Implementation rules

- Write only the code required by the current slice.
- Use Swift concurrency in public methods.
- OpenAPI generation is acceptable for readable models. Write the network client by hand.
- Prove cryptographic compatibility with known byte values instead of repeating the algorithm in the test.
- Never write passwords, secret keys, or derived keys to disk or logs.
