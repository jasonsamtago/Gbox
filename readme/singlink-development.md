# SingLink development core build

SingLink is an opt-in direct TLS TCP outbound. Normal public builds keep the existing dependency graph and return a clear unsupported-build error. This slice builds a native executable only, not an installed Gbox client package.

From this repository source root, with Dart, Go, Git, tar and complete existing offline dependency caches:

```sh
dart tool/build_singlink.dart --sdk /path/to/private/singlink-go --out /outside/source/core-singlink --vet
```

Obtain authorized private SDK access separately; never expose credentials. The builder performs no downloads or authentication. Outputs must be outside both checkouts; existing artifacts and sidecars are refused. Optional `--target` accepts darwin/linux/windows and `--arch` arm64/amd64, defaulting to the Go host. Compiling another target does not prove runtime support. A compiled Dart helper is a compiler-validation artifact, not a relocatable CLI; invoke the source from the checkout.

The manifest pins SDK commit `03ebf55baef1681ceef25bea9b839177d1c55e28`. Git replacement objects are disabled while resolving and archiving it. SDK checkout HEAD and dirty files are not compiled. External temporary extraction, a workspace containing the wrapper and archived SDK, and an explicit overlay of the public glue enable compilation. The wrapper retains its existing local mihomo replacement. No private SDK source enters this repository; no default module graph changes are required. A bare `singlink` tag is insufficient. Pin updates require reviewing SDK source/API changes, updating `tool/singlink/sdk.json`, and repeating offline compiler/static review.

This example contains a deliberately invalid token placeholder; privately replace it with the server's nonzero 32-byte token encoded as 64 hex characters:

```yaml
proxies:
  - name: Private SingLink
    type: singlink
    server: endpoint.example.com
    port: 443
    sni: endpoint.example.com
    token: REPLACE_PRIVATELY_WITH_64_HEX_CHARACTERS
    transport: direct-tls
```

Certificate verification is mandatory. UDP, UOT, outer smux, insecure TLS, CDN/XHTTP and QUIC are unsupported. Native TCP destination metadata supplies the actual host/IP and port. Construction is lazy; each adapter owns one reusable bounded SDK client. Pending requests default to 64, streams to 128 and receive window to 262144 bytes. Pending/stream limits are 1–1024; window is 1–1048576 bytes with streams × window at most 67108864. Setup/open/write timeout defaults are 10000 milliseconds, bounded to 1–600000. Zero selects defaults. Diagnostics do not echo secret configuration.

The connection wrapper preserves SDK deadlines, half-close, chain metadata and adapter reference lifetime without the native extra deadline wrapper. Adapter Close waits for SDK drain; an uncooperative host dial or close can block it. Never call this joining Close from an SDK-owned callback.

The JSON sidecar records source observations, tags, SDK commit/tree/archive hash and template hash. Dirty observations do not identify all dirty bytes exactly. The executable is never launched. Failed compilation or recording removes owned partial outputs; temporary SDK extraction is cleaned up. Keep the sidecar with the artifact.

Evidence is limited to source review, offline compilation, Go vet and Dart static/compiler checks. Protocol, application, connection, concurrency, installation and production behavior have not been executed or established.

## Source and validation record

| Component | Source identity | Evidence scope |
|---|---|---|
| Gbox SingLink adapter and compiler entry | `03e7da8cee9afd02e37ce3f94fdc5011429603f3` | Public integration glue; development executable only |
| Complete focused static-analysis targets | `f93ad10757a0840f903bb2dd43098b1ef14917aa` | Explicit parser and outbound vet targets; earlier adapter-only vet was incomplete |
| Private shared SDK | `03ebf55baef1681ceef25bea9b839177d1c55e28` | Exact git archive selected by sdk.json; not a released protocol version |

Recorded on 2026-09-10: offline darwin/arm64 opt-in compilation and both-package vet passed with Go1.26.3 and cached Go1.20.14. The ordinary core build and both-package vet passed with Go1.26.3. Dart format, analysis and compiler checks passed. No automated tests or generated executables were run. These records do not establish working connections, a shipped client, production deployment or an upstream release number.
