# Embedded Android Runtime — Implementation Blueprint

- **Status:** Conceptual architecture only; no embedded terminal, shell, package manager, or bundled tool runtime is implemented.
- **Purpose:** Define a safe path for supported, app-managed Android tools without requiring users to install the external Termux app.
- **Parent architecture:** [Final Technical Blueprint](technical-blueprint.md).
- **Related AI boundary:** [AI Cybersecurity Expert Engine](ai-cybersecurity-expert-engine.md).

> This is a design document, not a promise that arbitrary Linux tools can run inside an APK. It does not authorize general-purpose shell execution, root access, Docker, or automatic installation/execution of third-party binaries.

## 1. Goals and non-goals

### Goals

- Keep supported core checks usable from one Android app package without an external Termux installation.
- Run only registered, reviewed, Android-compatible tools using app-private data and least privilege.
- Support ARM64 where verified; report actual ABI, Android API, memory, storage, and permission requirements for each tool.
- Keep offline/local operation possible; downloads, models, cloud services, and user-owned infrastructure remain optional.
- Make package provenance, version, license, integrity verification, install/update/remove actions, and compatibility visible to the user.

### Non-goals for the initial runtime

- Recreating a full Linux distribution or a general-purpose Termux replacement.
- Arbitrary terminal commands, `sh -c`, shell pipelines, privilege escalation, root, Docker, or silent background scans.
- Assuming a Linux ARM64 executable is compatible with Android/Bionic, Android sandboxing, or Play/device policies.
- Automatically executing downloaded scripts, plugins, PoCs, malware samples, or tool installers.

A terminal-like interface, if ever approved, must be a constrained UI over registered, typed actions—not an unrestricted shell. The initial plan favors tool-specific screens and adapters over free-form command entry.

## 2. Conceptual architecture

```text
Flutter application
  ├─ Tool Registry + compatibility metadata
  ├─ Plugin/Tool Manager (reviewed manifest and user-approved lifecycle)
  ├─ Policy Engine (scope, authorization, permissions, resource/time limits)
  ├─ Tool Orchestrator (registered ID + typed arguments only)
  ├─ Android-native bridge (Kotlin; narrow, versioned interfaces)
  ├─ App-private runtime workspace
  │    ├─ supported Android-native libraries / reviewed executables
  │    ├─ per-tool data and temporary files
  │    └─ no shared secret-bearing shell environment
  └─ Result Analyzer → SQLite history / Report Engine
```

The AI Assistant can propose a registered tool and typed parameters, but it does not receive a shell, package-manager, filesystem, or process handle. Every execution must pass through the same Policy Engine and Orchestrator whether initiated by a person or later by AI-assisted planning.

## 3. Runtime components

### Internal terminal and command surface

No arbitrary shell is part of the initial MVP. Provide tool-specific forms and structured job status, cancellation, and output instead. If a future restricted console is considered, use a finite command grammar mapped to registered actions; reject unknown commands, shell metacharacters, redirection, arbitrary paths, network destinations, and chained commands. Never invoke a free-form command string through `sh -c`.

### App-private filesystem

- Store installed packages, tool data, caches, logs, and temporary work only in app-private locations with explicit per-tool subdirectories.
- Define quotas, expiration/cleanup behavior, export confirmation, and clear-data behavior. Do not place secrets in tool workspaces or logs.
- Treat imported files and plugin content as untrusted; validate file type/size and avoid path traversal, symlink escape, and archive extraction attacks.
- Use scoped Android Storage Access Framework selection for user files when required. Do not request broad storage access by default.
- Temporary files and malware samples must never be executed automatically.

### Tool and package manager

A future in-app manager is a curated lifecycle service, not a full system package manager. A package manifest should contain a stable tool ID, publisher/source, version, license, Android API range, ABI/architecture, artifact digest/signature metadata, dependencies, required permissions, installation footprint, and safety/usage notes.

Install/update flow: resolve an allowlisted source → show source/version/license/compatibility/permissions → obtain user consent → download to a staging area → verify available signatures/checksums and clearly disclose when none are published → inspect package metadata and size → atomically install into app-private storage → register the exact version → audit the result. Uninstall should remove files belonging to that package without deleting user evidence unless explicitly requested. No package executes during installation.

A “Plugin Store” is only a catalog and reviewed distribution channel in this design. Plugins cannot register native code or expand permissions without review. Prefer declarative manifests and fixed adapter capabilities; signed publisher identity alone is not proof of safety.

### Android process and ABI support

- Prefer Android-native Kotlin/Java APIs or reviewed Android NDK libraries for core capabilities.
- Any executable/runtime integration must explicitly declare Android API, ABI, dynamic-library, Bionic, SELinux, and device-resource requirements and be tested on supported devices.
- ARM64 support is conditional on validation; do not infer Android compatibility from an `aarch64` or Linux ARM64 build label.
- Use the Android app sandbox and the narrowest process/permission model available. Process separation can reduce risk but is not a substitute for review or a formal sandbox.
- The app must not require root, Docker, or an externally installed Termux environment for its supported core functions. Unsupported tools remain “Environment Required” or “Unsupported”; do not silently emulate unavailable capabilities.

### Dependencies and permissions

Each adapter declares a dependency manifest and permission rationale. Avoid bundled package managers or broad dependency trees unless their licensing, integrity, update, storage, and attack-surface implications are reviewed. Ask only for runtime permissions needed by a user-initiated operation; explain denial and provide a non-permission alternative when possible. Network checks remain bounded and require the app's authorization/scope controls.

## 4. Termux references, licensing, and attribution

Termux may be consulted as a technical reference, but the application must not require the Termux app to be installed. Do not copy, repackage, link, or redistribute Termux code, packages, or assets without a component-by-component license and compatibility review and required notices/source offers. Check licenses for every bundled tool, library, package, and model independently; tool source availability does not grant redistribution rights. Record notices, source/version, modifications, and obligations in an inventory before distribution. This blueprint is not legal advice.

No particular Termux component or package is selected for embedding. A later implementation proposal must explain why a native adapter or a narrowly bundled compatible component is required and document its maintenance and security ownership.

## 5. Security and operational safeguards

- Registry allowlist, typed arguments, strict input validation, and Policy Engine enforcement for every operation.
- User-visible target/scope/authorization confirmation for active checks; revalidate at execution time.
- Per-tool network allowlists, request/time/response/CPU/memory/storage limits, cancellation, and safe defaults.
- No automatic exploit execution, malware execution, shell execution, or background scan. Static malware review can inspect metadata without running a sample.
- Validate artifact integrity, version, license, ABI, and permissions before install; never run from staging.
- Audit action, selected tool/version, target scope, consent gate, source, start/end, and outcome without secrets or unnecessary content.
- Protect credentials with the app's secure credential boundary; never expose API keys to a process environment, tool output, report, or runtime workspace.
- Keep results local by default and require explicit consent before export/sync/cloud analysis.
- Clearly distinguish unsupported/untested environments from verified support; prohibit a “safe” conclusion based only on no findings.

## 6. Compatibility state model

Use existing Tool Registry compatibility semantics and keep installation separate from compatibility. At minimum report:

- **Available / Android compatible:** capability has been validated on the declared supported environment.
- **Not installed:** a compatible package exists but is not present.
- **Download required:** a user-approved, integrity-checkable compatible artifact is needed.
- **Environment required:** an explicitly named dependency/service not bundled by the app is necessary.
- **Limited compatibility:** only listed operations/devices are verified.
- **Unsupported:** ABI/API, sandbox, permission, licensing, or dependency constraints prevent use.

For every claim, record tested device model, Android API, ABI, app version, tool version, and test date. A green architecture diagram is not evidence of device compatibility.

## 7. Staged implementation proposal

| Stage | Deliverable | Gate before proceeding |
|---|---|---|
| 0. Scope and threat model | Decide supported tool types, non-goals, app sandbox, permissions, filesystem, licensing workflow, and UX. | Product/security review; no free-form shell. |
| 1. Contracts and inventory | Tool package manifest, compatibility states, audit event, typed process/task contract, dependency/license inventory. | Schema and hostile-input tests pass. |
| 2. Native P0 adapters | Implement/retain small Android-native DNS, TLS, and HTTP-header capabilities through existing registry/orchestrator boundaries. | Authorization, timeout, target scope, privacy, and Android tests pass. |
| 3. Private workspace | Add bounded per-tool files/cache and cleanup/export UX only when a tool needs it. | Path traversal, quota, permission, and data-deletion tests pass. |
| 4. Curated package lifecycle | Prototype verified install/update/remove of a small approved package set; no arbitrary plugins. | License, provenance, signature/checksum disclosure, rollback, and tamper tests pass. |
| 5. Optional compatible runtime | Evaluate individual Android-compatible native/bundled components on supported ABI/API devices. | Device tests and independent security/license review for each component. |
| 6. Plugin catalog and broader tooling | Add reviewed declarative plugin metadata and compatible tools incrementally. | Per-tool threat model, compatibility evidence, limits, and support owner. |

This plan does not make Termux, root, or Docker a prerequisite. It also does not promise that the full range of Linux security tools can be embedded or run on Android.

## 8. Current status

The repository currently has a Flutter interface, registry entries, a registry-ID-only orchestrator, policy/scope checks, limited DNS/TLS/HTTP-header adapters, local result analysis, SQLite history, and documentation. It does **not** currently have an embedded terminal, shell executor, internal package manager, plugin installer/store, bundled third-party tool runtime, or Termux code. See [`apps/android/README.md`](../apps/android/README.md) for tested boundaries and the [AI Engine blueprint](ai-cybersecurity-expert-engine.md) for the model-facing trust boundary.
