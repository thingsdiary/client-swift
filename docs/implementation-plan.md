# Implementation plan

## 1. Record the protocol

- Compare OpenAPI with the Go and JavaScript clients.
- Capture fixed vectors for the KDF, keys, signatures, AES-GCM, and sealed boxes.
- Record differences as protocol constraints.

This step is complete when one input set has expected bytes produced by the existing clients.

## 2. Select cryptography libraries

- Check Apple CryptoKit and system APIs first.
- For missing algorithms, choose a small maintained library with clear code provenance.
- Record versions, platforms, audits, and missing guarantees in an ADR.

This step is complete when the selected libraries implement the protocol without changing its wire format.

## 3. Implement cryptography with TDD

The public API accepts a `TDKV1` secret key and salt, returns key pairs, signs and verifies data, and encrypts and decrypts data. Each cycle starts with one failing test against a fixed vector.

This step is complete when Swift passes Go and JavaScript vectors in both directions.

## 4. Implement the API client with TDD

Start with one vertical slice: login, challenge signing, login verification, and diary listing. Add the remaining OpenAPI methods one at a time.

Tests call public asynchronous methods. Only the HTTP transport is replaced.

This step is complete when the client covers the specification and handles successful responses, API errors, and invalid data.

## 5. Verify integration

- Swift encrypts data that Go and JavaScript can decrypt.
- Swift decrypts data produced by Go and JavaScript.
- All three clients verify each other's signatures.
- Swift completes the minimum workflow against `thingsd`.

## 6. Connect the macOS app

This belongs to the second goal and starts after the Swift Package API is stable.
