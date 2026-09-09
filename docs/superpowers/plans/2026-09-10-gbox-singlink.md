# Gbox SingLink source integration implementation plan

> REQUIRED SUB-SKILL: subagent-driven-development. User has delegated development; no approval menu. Latest no-tests instruction overrides test workflow. Existing isolated codex/singlink-v1 worktree.

**Goal:** Compile Gbox's actual outbound adapter against an exact private SingLink SDK without changing default public dependencies.
**Architecture:** Public parser/stub/options and overlay adapter glue; standalone offline compiler creates git-archived SDK workspace and records provenance.
**Tech:** Existing Go core/SDK and Dart dependencies, no new dependencies.

## Global Constraints

- Full docs/superpowers/specs/2026-09-10-gbox-singlink.md authoritative for API, exact values and bounds.
- Source/offline compilation/static review only. No tests/testfiles/runtime/protocol traffic/listeners/captures/simulations/install/download/push/merge/deploy. Compiler orchestration is permitted, never execute resulting binary. Commits [skip ci].
- Public Gbox source must not contain copied private SDK implementation. Keep existing module/sum files, setup.dart, workflows and production profiles unchanged. Controller owns global docs and evidence outside repo.
- Existing Gbox base07a6efe; private SDK exact03ebf55baef1681ceef25bea9b839177d1c55e28. Build proves compilation only.

### Task 1: Add actual native outbound and explicit private SDK build

**Files:** modify core/Clash.Meta/adapter/parser.go, core/Clash.Meta/constant/adapters.go, tool/build_provenance.dart; create core/Clash.Meta/adapter/outbound/singlink.go, core/Clash.Meta/adapter/outbound/singlink_disabled.go, tool/singlink/outbound.go.in, tool/singlink/sdk.json, tool/build_singlink.dart, readme/singlink-development.md. Controller owns spec/plan.

- [x] Read full spec, sdk session/tcpclient/mux/target contracts and existing native outbound/wrappers before editing. Resolve architecture issues with controller before broadening scope.
- [x] Register type/append constant, common options and default stub; reject outer smux for singlink. Pattern: case "singlink": decode SingLinkOption; proxy,err=outbound.NewSingLink(option); existing autoClose registration unchanged.
- [x] Implement enabled public glue. Pattern: one tcpclient.New(Config{Factory: generationCtx -> configuredDialer.DialContext -> session.Client, bounded fields/MuxRoleClient}); DialContext -> target.Endpoint from actual metadata -> client.DialContext -> native extended conn with explicit CloseWrite/ref; Close -> client.Close(); <-client.Done(). Validate every option first and never echo token.
- [x] Implement explicit build entry and exact-source extraction/temporary workspace/overlay (only wrapper and archived SDK are main modules; preserve existing mihomo replacement). Pattern: parse args; reject existing/in-source output; load pin; git rev-parse pinned commit/tree; git archive pinned commit into scratch; extract and verify go.mod; write go.work + overlay; record start; Process.run go build with fixed offline env; write provenance; finally remove scratch. Refuse failures without leaving an apparently valid artifact/manifest. No setup.dart edits or go mod tidy.
- [x] Add provenance optional integration data and allowlisted dependency hashes; write clear readme and unsupported/runtime-limits status.
- [x] Format scoped Go source/template and Dart; offline compile default wrapper and optional core to unique paths under ../evidence/gbox-singlink/, analyze/compile changed Dart and focused vet adapter in both modes. If scratch cleanup prevents later enabled vet, orchestrator may expose a narrow --vet compiler-only option that runs focused go vet after build before cleanup; document it. No tests. Use existing Flutter Dart at /opt/homebrew/Caskroom/flutter/3.44.9/flutter/bin/dart and Go local; network disabled in compilation env. Review formatting, git diff --check, unchanged test/module/workflow files, no private source copied. Exact command logs/exit statuses go in report.
- [x] Self-review ownership, cancellation, AddRef, option bounds, overlay/default tidy isolation, archive exactness, source/manifest failure cleanup, no secret-bearing logs. Commit production files/docs only [skip ci], no push. Report full changes/evidence/limitations/self-review/head in specified report file; controller handles independent task/final reviews.
