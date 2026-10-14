# API inventory

Route source: `thingsd/api/openapi/openapi.yaml`.

## Authentication

- `register`
- `login`
- `loginVerify`
- `logout`
- `getCurrentSession`

Authentication uses two requests. `login` returns a challenge, nonce, and KDF salt. The client validates and canonicalizes the `TDKV1` secret key, derives keys from its canonical string, signs the nonce with Ed25519, and sends the signature to `loginVerify`.

## Diaries and keys

- `createDiary`
- `getDiaries`
- `getDiaryById`
- `putDiary`
- `deleteDiary`
- `getDiaryKeys`
- `getDiaryChanges`

## Entries

- `getEntries`
- `getEntryById`
- `putEntry`
- `deleteEntry`
- `restoreEntry`

## Topics

- `getTopics`
- `getTopicById`
- `putTopic`
- `deleteTopic`
- `restoreTopic`

## Templates

- `getTemplates`
- `getTemplateById`
- `putTemplate`
- `deleteTemplate`
- `restoreTemplate`

## Compatibility checks

- OpenAPI names `https://cloud.thingsdiary.io/api` as the server. The JavaScript client uses `https://cloud.thingsdiary.com/api` and appends `/v1/...` routes.
- OpenAPI defines models and HTTP status codes, but not the complete client-side encryption format.
- The Go client stores an Ed25519 private key as 64 bytes. JavaScript stores a 32-byte seed. The Swift API must choose one public representation and convert explicitly at the boundary.
- Randomized ciphertext cannot be compared for equality. Cross-client tests must control randomness or decrypt with a different client.
- Go implements 23 of 27 operations. It lacks current session and the three restore methods. JavaScript implements 21 of 27 and also lacks logout and changes.
- JavaScript `login` returns only the token, losing the KDF salt and derived credentials. Swift `login` must return enough authentication state to use the client without another request.
- Existing clients only partly support pagination, delete options, and optimistic concurrency versions. The Swift API must expose these parameters.
