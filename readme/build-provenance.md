# Core build provenance

Every freshly compiled core gets a JSON sidecar beside the binary. The sidecar
name is the complete artifact name followed by `.build.json`.

- Desktop: `libclash/<platform>/<core-name>.build.json`
- Android: `libclash/android/<abi>/libclash.so.build.json`

Desktop builds overwrite the platform's core when you switch architecture. The
sidecar's `build.architecture` field records the architecture of the current
binary.

The record describes the core immediately after `go build` and before later
packaging or release signing. On macOS, the Go linker may already apply an ad
hoc/linker signature at this point; `core-before-signing` means before the later
signing stage, not necessarily that the file has no signature at all.
It contains the artifact size and SHA-256, build options, the client version,
the wrapper and vendored core module names, and source observations taken before
and after `go build`.
The upstream core release is explicitly recorded as unknown because neither the
client version nor the placeholder module version identifies an upstream
release.

## Reading source observations

When Git is available and its top-level directory is exactly this repository,
the record includes the current commit, its tree, the vendored core tree, and a
whole-repository dirty flag. The dirty flag considers tracked changes and
non-ignored untracked files, but deliberately does not list file names. These
values are observations of the working tree, not proof of the exact contents of
dirty files.

`dirty: true` means the checkout contained changes outside the recorded commit.
`dirty: null` and `status: unavailable` mean Git metadata could not be safely
read. `changedDuringBuild: true` means at least one source observation,
dependency-file hash, or the pubspec version changed between the two captures.
In all three cases, do not claim the binary came from an exact clean source
revision.

The allowlisted dependency files are hashed from disk at both observation
points. A missing file is represented by `null`.

## Checking an artifact

Calculate SHA-256 for the core binary and compare it with
`artifact.sha256` in the adjacent sidecar. For example:

```sh
shasum -a 256 libclash/macos/BettboxCore
```

The sidecar describes the bytes immediately after `go build`, before later
packaging or release signing. Later signing can change the binary and therefore
its SHA-256. Copying a binary without its sidecar, or altering it during signing
or packaging, breaks this direct comparison.

The sidecar is a local build record, not a signed attestation. Desktop packaging
does not automatically copy or publish it. Android native-library staging
explicitly excludes it. Release tooling must make a separate, deliberate choice
if these records should be distributed.

`--ensure` preserves the existing reuse behavior. When a build is skipped, no
new provenance is generated and an old binary is never stamped retroactively.
If a sidecar is missing or stale, run a fresh build without relying on the skip.

No automated tests or network validation were run for this change.
