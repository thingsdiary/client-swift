# ADR 0001. Cryptography libraries

Status: accepted.

## Decision

For iOS 16 and macOS 13, use:

- CryptoKit for HKDF-SHA256, Ed25519, X25519, and AES-256-GCM;
- CommonCrypto for PBKDF2-HMAC-SHA256;
- the `Clibsodium` binary product from Swift-Sodium only for NaCl anonymous sealed boxes.

The Swift Package stores an Ed25519 private key as a 32-byte seed. Go expands the same seed into a 64-byte private key.

## Rationale

CryptoKit and CommonCrypto ship in the Apple SDK. They implement the full protocol except sealed boxes. CryptoKit does not support XSalsa20-Poly1305, so `ChaChaPoly` cannot replace the existing format.

A small internal adapter calls `crypto_box_seal` and `crypto_box_seal_open` from libsodium. This matches Go's `nacl/box.SealAnonymous` and the current JavaScript implementation. The package's public API does not expose C types or Swift-Sodium. Implementing sealed boxes in this package would add custom cryptographic code without changing the product.

`swift-crypto` is not used in the Apple-only version. It duplicates CryptoKit and does not implement sealed boxes. Revisit this decision if the library needs Linux support.

## Risks

- Swift-Sodium is the only external package. The production target links its `Clibsodium` product, not the `Sodium` wrapper.
- No public independent audit of the Swift wrapper was found. The adapter is small, and the test suite checks compatibility and error handling.
- A libsodium update requires rerunning the cross-client vectors.
- CryptoKit returns AES-GCM ciphertext and tag separately. The thingsdiary wire format stores them consecutively.

## Verification

Swift passes saved Go and JavaScript vectors for the KDF, keys, Ed25519 verification, AES-GCM, and sealed-box opening. Sealed boxes created by Swift open through the same libsodium API and have the expected 48-byte overhead.

## Sources

- [CryptoKit Curve25519 signing](https://developer.apple.com/documentation/cryptokit/curve25519/signing/privatekey)
- [CryptoKit X25519](https://developer.apple.com/documentation/cryptokit/curve25519/keyagreement)
- [CryptoKit HKDF](https://developer.apple.com/documentation/cryptokit/hkdf)
- [CryptoKit AES-GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)
- [Swift-Sodium](https://github.com/jedisct1/swift-sodium)
- [libsodium sealed boxes](https://libsodium.gitbook.io/doc/public-key_cryptography/sealed_boxes)
