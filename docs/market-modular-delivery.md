# Market Modular Delivery — Product Decision and Architecture

- **Status:** Owner-approved staged strategy: stabilize the existing APK first; then use a controlled, signed project server for test-stage module packages; evaluate Google Play delivery near release. Implementation and distribution validation are not complete.
- **Date:** 2026-11-23
- **Scope:** Keep Market in the base app while letting users add/remove optional provider modules without removing Cybersecurity Assistant.
- **Related:** [Final Technical Blueprint](technical-blueprint.md), [Platform Product Blueprint](platform-product-blueprint.md), [Android Market foundation](android-market-package-manager.md), [Priority providers](market-priority-providers.md), [AI Engine](ai-cybersecurity-expert-engine.md), and [Embedded Runtime](embedded-runtime-implementation.md).

## Product decision

The first Play Store download should contain only the app foundation and remain as small as practical. The **Market screen, catalog, module registry, security/policy boundary, shared provider contracts, and core local checks remain available in the base app**. Market must remain visible even when no optional provider is installed.

Users choose optional capabilities in Market. They can install or remove each optional module independently; removing a module must never uninstall the main app or Market. Provider cards remain visible in the catalog and accurately show whether the module is available, downloading, installed, waiting for setup, not ready, incompatible, or failed.

### Initial optional modules

| Market item | Intended optional content | Activation and truthful readiness |
|---|---|---|
| **Cloudflare** | Cloudflare adapter and its dedicated account/zone workspace. | After module installation, ask for a user-owned, least-privilege token. Show each operation only when the corresponding API response demonstrates access. The current scope is read-only account/zone listing and zone details; installation must not imply DNS, Workers, R2, D1, or write support. |
| **Gemini** | Gemini provider adapter and its provider-specific UI. | After module installation, require the user's own key. Each prompt and any approved tool result still require explicit data-sharing consent. Installation alone does not mean connected or ready. |
| **Local AI** | Optional on-device inference adapter/runtime and a separately managed compatible model artifact. | Runtime code and model weights are separate delivery concerns. Require a compatible device/runtime, trusted artifact metadata, license/integrity checks, available storage, and a successful on-device inference before reporting Ready. Never fall back silently to cloud AI. |

These three are the initial priority set; this decision does not authorize adding more providers.

## Meaning of install, connect, ready, and uninstall

These states are distinct and must never be collapsed into one “Installed/Connected” badge:

1. **Not installed:** the module is listed in Market but its optional component is absent.
2. **Installing / installed:** the optional component is being delivered or is present on the device.
3. **Needs setup / disconnected:** component is present but credentials or configuration are absent or unverified.
4. **Connected:** the implemented, bounded connection test succeeded in the current session.
5. **Capability allowed/denied/not checked:** permission evidence for each operation comes from that operation's response, not from a general token-valid status.
6. **Ready:** all required code, configuration, device compatibility, and runtime/model checks succeeded for the specific advertised feature.
7. **Uninstall module:** remove only the selected optional component and its module-managed files. Keep the base app, Market, unrelated providers, assessment history, findings, and reports. Credential deletion/retention must be explicit and independently confirmed; it must not silently delete unrelated credentials or user evidence.

The Market catalog remains visible when a module is uninstalled so the user can install it again later. Package/module installation is not a connection test and is not proof of capability. **Uninstalling a module must preserve saved credentials, user configuration, and user-owned external resources by default.** It must not revoke a provider token, delete a user account/storage bucket/domain, or silently remove a credential from Secure Storage. Credential deletion/revocation belongs to a separate, explicit user action.

## Required BYOK/BYOI and provider-connection standard (target)

Every Market module must use **BYOK/BYOI when relevant**: the user supplies and controls the credential, account, endpoint, domain, storage, or other infrastructure that the service actually requires. Do not impose an API key on local-only, public, bundled, or otherwise unauthenticated capabilities. An unauthenticated module still needs an honest Connect/Disconnect (or equivalent activation/deactivation) flow that verifies the service state without fabricating credential fields.

For modules with external providers, the implementation and publication evidence must include:

- A provider-specific configuration form based on the provider's current official documentation. Link setup and permission references in the UI, note the documentation review date/version, validate input locally, and do not send values until the user chooses **Connect** or **Test Connection**.
- Android Keystore-backed `Secure Storage` for secrets; mask them in the UI and exclude them from logs, errors, Diagnostics, analytics, reports, and package/catalog requests. Nonsecret settings are stored separately with a versioned schema.
- **Connect** and **Disconnect** actions with clear statuses. Connect performs a bounded, least-invasive credential/service test and identifies what it did and did not verify. A valid token is not proof of every permission. Disconnect stops use of that connection; if it also removes a saved credential, label that effect and require an explicit confirmation. Do not conflate disconnect with module uninstall.
- Official, actionable guidance for obtaining/configuring an API key, token, endpoint, or account; least-privilege scope and expiry guidance; warnings about billing and client-side credential risks where relevant.
- Direct provider communication from the app to the provider's documented HTTPS endpoint. **Never relay user credentials through a project-controlled server**, including module distribution, catalog, diagnostics, telemetry, or update requests. Do not send prompts, findings, or user data unless the applicable feature's separate consent permits it.
- Provider-specific tests proving the credential is stored securely, validation and connection failure are truthful, requests reach only the documented provider endpoint, and no credential appears in server/diagnostic/logging traffic.
- Uninstall regression tests proving credentials, nonsecret configuration, and user-owned provider resources are unchanged. If a module cannot operate while removed, keep its credential/configuration dormant for reinstall; deletion or provider-side revocation is a separate, deliberate action.

For user-owned infrastructure (BYOI), use the user's configured endpoint/account and least-privilege access. The app must remain useful without a mandatory developer-operated server or developer-owned credential. Market's own artifact delivery is not a route for forwarding provider credentials.

## Module contract and component responsibilities (target)

A publishable module must implement the following contract. These are **design requirements, not current repository capabilities**. Keep the host APK authoritative for policy, credentials, data ownership, and diagnostics; a module may request only registered typed capabilities.

| Component | Responsibility and required behavior |
|---|---|
| **Manifest** | Stable module ID, display name/description, publisher, semantic version, payload type, minimum host/API/ABI, dependencies, artifact size/digest, license, declared capabilities, and compatibility metadata. Canonical serialization and signature verification are required for remote artifacts. |
| **Capability Registry** | Register only reviewed capability IDs and typed input/output schemas. Reject duplicate/unknown IDs and prevent a module from granting itself capabilities. Registry entries carry module ownership and policy metadata. |
| **Permission Declaration** | Declare requested capabilities and rationale before install/activation. Declarations are requests, not grants; the host Policy Engine and operation-level authorization remain authoritative. Provider/API permissions are checked per operation. |
| **Runtime Adapter** | Expose a narrow, versioned host interface and route all privileged work through base-app adapters and the Policy Engine. No arbitrary code execution, direct unrestricted network/filesystem/shell, or policy bypass. Downloaded executable payloads require separate threat model and constrained-runtime approval; signature alone is insufficient. |
| **Configuration** | Provide provider-doc-aligned setup and key/token/account/endpoint guidance; store typed, schema-versioned nonsecret settings separately from secrets in Android Keystore-backed Secure Storage. Support local validation, migrations, masked display, explicit Connect/Disconnect semantics, and retention through module uninstall. Do not require credentials for services that do not use them. |
| **Lifecycle** | Define idempotent `install`, `start`, `stop`, `update`, and `uninstall` transitions with explicit intermediate/error states. Verify before activation, stage updates atomically, stop before removal, support rollback/recovery, and never remove app, Market, history, reports, or unrelated modules. |
| **Health Check** | Report lifecycle/runtime health separately from provider connectivity, per-capability authorization, and feature readiness. Use bounded checks with no hidden destructive operation or secret leakage. |
| **Error Reporting** | Send structured, redacted error events to in-app Diagnostics with module ID/version, lifecycle stage, safe error category, and correlation ID. Never include tokens, keys, prompt content, or sensitive findings by default; respect consent and retention controls. |
| **Tests** | Include contract, schema, permission/policy, lifecycle/failure/recovery, compatibility, regression/isolation, and data-preservation tests. Host integration tests must prove the module cannot affect unrelated modules or bypass policy. |

## Market publication gates

A module remains draft/unlisted until every gate passes and evidence is recorded for the exact module version and target host build:

1. **Foundation complete:** manifest/registry/adapter/configuration/lifecycle/health/diagnostics contracts implemented and versioned; ownership and migration/removal semantics documented.
2. **Security and permissions validated:** signed artifact and manifest verify against an approved trust root; compatibility, dependencies, payload type, declared capabilities, least privilege, policy enforcement, secret handling, and failure-closed behavior pass review. Unknown or excess permissions are rejected.
3. **Install/update/uninstall verified:** install, update, interruption, corrupt artifact, rollback, stop, uninstall, and reinstall pass; operations are atomic/recoverable and remove only module-owned files. Credentials, nonsecret configuration, and user-owned provider resources survive uninstall. Any credential deletion or provider-side revocation is a separate, explicitly confirmed action.
4. **APK integration verified:** target APK can discover and activate the module through the documented adapter/registry; lifecycle and health states remain truthful; existing Market, four primary destinations, and other providers work normally.
5. **Functional tests pass:** unit, integration, compatibility, and on-device checks pass for advertised capabilities. Readiness is not granted by installation alone.
6. **Isolation/regression passes:** install/update/remove and injected failures do not change another module's state, credentials, settings, reports, findings, or assessment history; Policy Engine bypass tests fail closed.
7. **Documentation/support ready:** user setup, permissions, limitations, compatibility, data/credential retention, update/removal, troubleshooting, and diagnostics guidance are available for the module.

The publication record should link the artifact digest, manifest signature/key ID, test results, review approval, supported host/device matrix, and rollback plan. A failed or missing gate blocks publication. During test-server distribution these gates govern project testing releases; Play publication adds its own platform/policy/release checks later.

## Staged module distribution design

### Test/development stage: controlled project server

After the existing base APK is stable, a controlled, official project server may distribute versioned, user-selected module artifacts for testing. Keep the source behind an explicit HTTPS host allowlist and a provider-agnostic `ModuleDeliverySource` interface so the Market lifecycle does not depend directly on one server or future Play APIs.

Every artifact needs a canonical, signed manifest containing module ID, version, publisher, source, payload type, size, license, Android/API/ABI compatibility, declared capabilities/permissions, and artifact digest. Verify the manifest signature against an embedded/pinned trust root and verify the payload digest before atomic installation into a module-owned app-private directory. A checksum detects byte mismatch; the signature authenticates the trusted manifest; neither one proves the code is safe or confines its privileges. Keep signing keys out of the APK/repository, define key rotation/revocation and rollback behavior, and fail closed on unknown keys, malformed metadata, version rollback, unsupported payload types, or digest mismatch.

**Important runtime boundary:** manifests, logos, provider metadata, model weights, and reviewed declarative configuration can be downloaded as data and interpreted by fixed, already-reviewed adapters. Do not download and execute arbitrary Dart, DEX/JAR, native `.so`, APK, script, or shell payloads merely because they are signed. Code running in-process can bypass host policy if it has unrestricted APIs; signatures/checksums are not a sandbox. If independently downloaded executable provider code is still required during the test stage, stop first for a separate Android threat model and a demonstrably constrained module runtime with typed capability calls, no direct unrestricted network/filesystem/shell access, and tests proving the Policy Engine cannot be bypassed. Until that runtime is reviewed, module packages may enable provider functionality through host-compiled adapters but do **not** reduce the APK's code size.

For Local AI, keep runtime code and model data separate. A compatible model bundle can be an optional signed/verified data artifact from the controlled server; disclose source, license, size, compatibility, integrity, storage, and removal effects. It must not be reported Ready until the native/runtime integration loads it and a local inference succeeds. The current code has no such integration.

### Play release stage: evaluate platform module delivery

Near release, evaluate moving executable provider code to Google Play on-demand feature modules in an Android App Bundle (AAB), while keeping module contracts, typed capabilities, manifests, registry states, package ownership, and Market UI stable. The delivery source can change from the project's test server to Play without changing Market's product flow, but the executable packaging/runtime integration itself may require a deliberate code move and native/Flutter configuration; do not promise a zero-change migration. Evaluate Play Asset Delivery or a verified data download for model weights based on measured size/update needs.

Build signing, module manifests, install/uninstall APIs, Flutter deferred-component compatibility, Play-policy requirements, account/region/device availability, and physical-device behavior must be verified on the generated Android project via Play internal testing or an appropriate local bundle-delivery test. An ordinary sideloaded debug APK cannot prove Play-only delivery. Keep a separate test path that never weakens production signature checks.

This is a staged recommendation, not proof that either custom-server modules or Play Feature Delivery currently work in this repository. Verify the selected Flutter/Gradle/Android mechanism before implementation.

## Security and privacy boundaries

- The base app owns the Market UI, package/module metadata validation, typed provider contracts, authorization policy, audit rules, and install-state display.
- Provider modules expose only reviewed, typed capabilities. They cannot add arbitrary permissions, shell access, unregistered tools, or policy bypass.
- The AI may suggest registered tools only. Existing user review, scope authorization, policy validation, and tool orchestration remain required after Gemini or Local AI is installed.
- Credentials remain user-owned and protected by Android Keystore-backed Secure Storage. Send them only to the user's documented provider endpoint when the user initiates an allowed operation; never embed developer credentials or relay user credentials/data through the project server, Market catalog, package server, Diagnostics, analytics, or update service.
- Cloudflare permissions are checked per read operation. Gemini data-sharing consent remains per request. Local AI remains local-only and has no hidden cloud fallback.
- Integrity, publisher/source, version, license, size, supported Android API/ABI, dependencies, permissions, update and removal effects must be visible before user consent.
- Removing a module must not remove reports, findings, or unrelated app data. Any provider-specific credential cleanup must be a separate, explicit choice.

## Current implementation gap — do not confuse target with status

The current repository does **not** yet implement this product decision:

- Market is always part of the UI, but its current package lifecycle is limited to verified data/JSON payloads; it does not load optional provider code.
- Cloudflare and Gemini adapters are currently bundled in the base app and cannot be individually uninstalled through Market.
- Local AI has a capability contract/device probe but no integrated inference runtime, model manager/download, or successful inference path.
- Only the small Security Assessment Evidence Guide is installable from the current package catalog. Provider cards are not equivalent to installable modules.
- CI currently validates a debug APK path; it does not produce or validate a modular Play AAB or on-demand provider install/remove flow.

Keep these current-state facts in implementation notes until each module passes the acceptance tests below. The product decision must not be represented as completed functionality merely by changing catalog labels or buttons.

## Implementation stages and acceptance checks

Modular delivery is deliberately **last**. Complete and record each foundation gate before beginning the next stage:

1. **Stabilize the current base APK:** resolve the known CI/build/signing-verifier root cause at its source; run Flutter dependency resolution, `flutter analyze`, the full Flutter unit/widget suite, Android source/APK verification, and a reproducible debug APK build. Preserve the current four primary destinations and honest capability states. Do not start a provider-module split while these checks are failing or unverified.
2. **Validate current Market and Provider Manager:** test existing Cloudflare token verification and read-only account/zone operations, operation-specific permission states, Gemini key/test/consent flow, and Local AI's fail-closed `Not Ready` state. Verify provider credentials stay in Secure Storage and are sent only to the documented provider endpoint—not the project server or Diagnostics. Confirm the Market remains reachable with no provider configured and never labels a provider ready solely because code is bundled.
3. **Prove package lifecycle/data safety:** run install/update/uninstall tests for the current knowledge package and verify these operations remove only package-managed files. The app, Market, provider credentials unless explicitly chosen for removal, assessment history, findings, reports, and unrelated packages must remain intact. Add regression tests for corrupt catalog/registry data, failed/partial operations, app restart, and orphaned package removal.
4. **Build and test the stable base on a physical Android device:** install the debug APK, smoke-test startup/navigation/assessment/Market/provider configuration/local storage and uninstall/reinstall behavior, and record device model, Android/API, ABI, APK size, failures, and evidence. Do not claim the base is stable until the relevant automated tests and device checklist pass. Release signing is a separate gate.
5. **Design transport-neutral package contracts:** only after stages 1–4 pass, define stable module IDs, signed manifests, trust-root/key rotation, module-owned storage, typed host capabilities, lifecycle states, and a `ModuleDeliverySource` boundary. Do not weaken the existing verifier or policy boundary.
6. **Test-server lifecycle proof:** use the controlled official server for signed declarative/provider data packages first; prove install/update/uninstall, offline/failure/rollback/reinstall, and preservation of app/history/credentials. Existing Cloudflare/Gemini adapters remain host-compiled in this safe phase, so this validates Market lifecycle but does not reduce APK code size.
7. **Cloudflare and Gemini activation:** expose their dedicated pages/features only when the corresponding verified Market package is installed; keep provider operations routed through host-compiled, typed adapters and Policy Engine. Verify per-operation Cloudflare access, Gemini BYOK/consent, and that uninstall disables only the selected module. Do not claim downloaded executable code unless a separate constrained runtime has passed review.
8. **Local AI model lifecycle:** after the base runtime integration exists, use the controlled server to deliver a specifically reviewed model data artifact. Pin runtime/model versions and licenses; verify metadata/integrity/device memory/storage/ABI; add user-approved install/remove; report Ready only after real on-device inference with network disabled. Runtime code delivery remains a separate decision.
9. **Near-Play code-delivery evaluation:** review the threat model for executable modules; then compare Play Feature Delivery for code and Play Asset Delivery or signed data downloads for models. Internal-test a signed AAB on supported devices, benchmark base/module/model sizes, and verify on-demand install/uninstall. Record measured results instead of promising “lightweight” without evidence.

Release acceptance requires the Market itself to remain usable after module removals; no module can access capabilities not registered in the base policy; provider-specific permissions/readiness stay accurate; app data is preserved according to explicit uninstall choices; and all Flutter, native Android, Play-delivery, privacy, and physical-device tests pass.
