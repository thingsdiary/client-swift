# Public test boundaries

Two boundaries govern TDD in this package.

## Cryptography

Tests use only the public `ThingsDiaryCrypto` API:

- `TDKV1` parsing, checksum validation, generation, and credential derivation with a KDF salt;
- signing and signature verification;
- AES-256-GCM;
- NaCl sealed boxes.

Expected bytes come from saved Go and JavaScript vectors. Tests do not calculate the expected value with the Swift implementation under test.

## API

Tests use only `ThingsDiaryClient` and its public asynchronous methods. They replace the external HTTP transport. Tests do not depend on internal types, private functions, or call order.
