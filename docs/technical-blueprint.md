# Cybersecurity Assistant — Final Technical Blueprint

- **Status:** Baseline architecture and roadmap
- **Platform:** Android
- **Product description:** AI-powered Android cybersecurity platform
- **Architecture principles:** Local-first, hybrid AI, BYOI (Bring Your Own Infrastructure), BYOK (Bring Your Own Key), and a GitHub-based tool ecosystem.

> **Implementation note:** The repository now includes an initial Flutter UI, an in-app registry for four P0 entries, a registry-only tool orchestration boundary, guarded DNS/TLS/HTTP-header adapters with a self-attestation audit marker, session-only result analysis/export plus opt-in SQLite history, a namespaced secure-credential wrapper and provider-details UI for local credential entry/status/deletion (not wired to connectors; Android runtime behavior is unverified), an HTTPS endpoint reachability prototype, a guide-only provider catalog, an allowlisted GitHub release-metadata viewer, and initial tests. These are an early foundation, not a complete or release-ready implementation. See [`apps/android/README.md`](../apps/android/README.md) for current limitations and setup.

## 1. Product concept

Cybersecurity Assistant is an Android application for discovering, managing, and safely using cybersecurity tools with AI assistance. It is composed of four major parts:

1. **Android application** — user interface and control center.
2. **Cybersecurity Tool Engine** — registry, policy checks, adapters, and execution of compatible tools.
3. **AI Assistant** — tool discovery, parameter guidance, result interpretation, and reporting.
4. **User-owned cloud infrastructure** — optional services configured and controlled by each user.

The project provides the application, engine, integration framework, catalog metadata, documentation, and infrastructure templates. Users provide any external accounts, domains, API keys, tokens, storage, and services they choose to connect. The application must not depend on a mandatory developer-operated backend.

## 2. GitHub tool ecosystem

GitHub can supply source code, catalog references, documentation, and releases. Candidate repositories include:

- `AKCodez/hackingtool-plugin` — reference for catalog metadata and workflows. Areas to review include `data/tools.json`, `ht_index.py`, `ht_search.py`, `ht_env.py`, `ht_run.py`, `SKILL.md`, and `workflows.md`.
- `4nzu/hackingtool` — reference for tool categories, dependencies, and workflows.
- `ggml-org/llama.cpp` — reference for local model inference.
- `termux/termux-app` — reference for an optional Android terminal environment.

These are references, not assumed runtime dependencies. Plugins, Python workflows, and Linux-oriented projects do not automatically run on Android. Any adaptation or redistribution must first check the source license, compatibility, dependencies, and security implications. The previously discussed catalog size of roughly 183 tools is an estimate, not a promise that every tool is supported or executable.

### GitHub Releases and downloads

Releases may provide tool binaries, model files, packages, source code, or configuration. A Download Manager must identify the source and version, check device compatibility and license, and verify a checksum or signature when one is published. It must not execute a downloaded file before validation. GitHub is not the default destination for user scan results or evidence; these remain local unless the user explicitly configures their own storage.

## 3. Tool Registry

The Tool Registry is the authoritative catalog for tools known to the application. Each entry should describe:

- Tool ID, name, category, and description.
- Source repository, version, and license.
- Supported platform and CPU architectures.
- Dependencies and installation method.
- Execution adapter or method.
- Compatibility status and required permissions.
- Usage guidance and safety constraints.

Initial categories include Web Security, Network Security, OSINT, Vulnerability Assessment, APK Analysis, Code Security, Cloud Security, Password Audit, and Digital Forensics.

### Compatibility states

The UI and engine must communicate capability accurately. Suggested states are:

- **Available** — ready to use.
- **Not Installed** — known but not installed.
- **Download Required** — requires a supported download.
- **Environment Required** — requires an additional environment or service.
- **Android Compatible** — tested on the current supported Android environment.
- **Limited Compatibility** — only some functions are supported.
- **Unsupported** — cannot run on the current device or environment.

These states are not mutually exclusive in every implementation; model compatibility and installation as separate fields if that makes the registry clearer. Never imply that an arbitrary GitHub tool works on every Android device.

## 4. Local-first execution and optional cloud

Local checks run on Android whenever practical. For example: a user supplies a domain they own or are authorized to assess; the app performs DNS lookup, TLS inspection, and HTTP security-header checks; results are stored in local SQLite. If the user enables synchronization, selected data may then be sent to a backend and storage they configure.

Cloud is optional infrastructure, not a mandatory place to run all tools. Supported connector families may include:

- **Cloudflare:** Workers for API/backend functions, D1 for database, R2 for object storage, Queues for optional job coordination, and a user-owned domain.
- **Firebase:** Authentication, Firestore, Storage, and Cloud Functions, as selected by the user.
- **Supabase or custom services:** Supabase, a self-hosted backend, REST API, S3-compatible storage, or WebDAV.

The application should provide configuration guidance and templates without requiring a provider. Data sync, remote coordination, and evidence upload must be opt-in and clearly explained.

## 5. System architecture and data flow

Primary tool flow:

```text
GitHub sources → Tool Catalog → Tool Registry → Policy Engine
              → Android Execution Engine → Local Results → AI Analysis
```

Optional user-owned services:

```text
Android App ↔ User-configured backend ↔ User-configured database/storage
```

The AI layer can use an installed local model or a cloud provider configured by the user. The app must remain useful without a cloud account or API key.

## 6. Android Execution Engine

Planned technologies:

- Flutter for the cross-platform UI.
- Kotlin for Android-native integration.
- ARM64 support where available, with runtime and device checks.
- Optional Termux adapter, subject to explicit setup and compatibility checks.
- `llama.cpp` as a possible local inference runtime.

Prioritized tools:

- **P0 — local basics:** DNS Lookup, SSL/TLS Inspector, HTTP Header Checker, Security Response Analyzer.
- **P1 — additional tools:** constrained Nmap TCP Connect checks, passive Subfinder workflows, and Gitleaks for user-selected files or repositories.
- **P2 — advanced integrations:** Nuclei with safe, explicitly selected templates; MobSF through a compatible local environment or service.

A binary being built for ARM64 does not make it Android-compatible. Linux, root, Docker, special drivers, or external services may be unavailable. The registry must declare these requirements, and the app must not silently bypass platform restrictions.

## 7. AI Assistant and orchestration

The AI Assistant helps users:

- Search and explain registry tools.
- Check requirements and compatibility.
- Propose and validate parameters.
- Explain risks and request confirmation before execution.
- Interpret results, group findings, suggest remediation, and prepare reports.

The AI must not execute arbitrary shell commands. All actions must resolve to a registered tool and pass through the Policy Engine with validated parameters. Active checks require an appropriately authorized target and explicit user confirmation. Cloud AI must not receive sensitive evidence without the user's informed consent.

## 8. Download Manager

The Download Manager should:

1. Retrieve tool release metadata from declared sources.
2. Show repository/source, version, license, and device compatibility.
3. Download only a compatible package selected by the user.
4. Verify checksum/signature where available and report when verification is unavailable.
5. Validate licensing and installation requirements.
6. Register, update, or remove tools with clear user consent.
7. Explain additional environment requirements before installation.

No downloaded artifact should be run automatically or before validation completes.

## 9. Connection Manager and credential handling

The Connection Manager organizes optional integrations by category:

- Backend.
- Database.
- Cloud Storage.
- AI Providers.
- Security Intelligence APIs.
- Custom Services.

Potential connectors include Cloudflare Workers, Firebase, Supabase, R2, S3-compatible storage, WebDAV, OpenAI, Gemini, Anthropic, OpenRouter, VirusTotal, Shodan, and URLScan. Each connection should provide endpoint/configuration fields, authentication setup, a **Test Connection** action, connection status, and provider-specific setup guidance. Tests should use the least-privileged request possible and avoid logging secrets or sending unnecessary data.

API keys and tokens must be stored encrypted using Android Keystore-backed protection. Do not embed developer credentials or cloud administrator/master keys in the APK. Secret values should be masked in the UI and excluded from logs, reports, crash data, and analytics.

## 10. Operating modes

### Standalone Mode

- SQLite and local history.
- Locally available tools and registry.
- Local reports.
- Optional local AI after a model is installed.
- No cloud account or API key required.

### Connected Mode

User-selected features may include cloud AI, a custom backend, cloud database/storage, security intelligence APIs, synchronization, and remote job coordination. Every connection is optional and can be disconnected by the user.

## 11. Suggested repository layout

```text
apps/android
engine/android
engine/runtime
engine/registry
engine/adapters
engine/policies
engine/download_manager
catalog/tools
catalog/providers
ai/local
ai/cloud
ai/orchestrator
ai/model_manager
integrations/backend
integrations/database
integrations/storage
integrations/ai
integrations/security_apis
shared/contracts
shared/schemas
templates/cloudflare
templates/firebase
templates/supabase
docs
```

Directories should be introduced as their components are implemented; this is a target layout, not a requirement to create empty folders upfront.

## 12. Security, privacy, and licensing principles

- Respect each source repository's license; do not copy or redistribute code without the necessary rights.
- Prefer official sources and verify checksums or signatures when available.
- Never automatically run untrusted scripts or downloads.
- Never ship developer API tokens or administrator credentials in the APK.
- Do not request cloud administrator/master credentials when a scoped credential is sufficient.
- Enforce authorization scope, validated parameters, permission checks, and time limits for tool execution.
- Maintain an auditable record of actions without recording secrets.
- Keep evidence local by default; require consent before sending sensitive data to cloud AI or user-owned cloud storage.
- Perform active security testing only on targets the user owns or is authorized to assess.

## 13. Development roadmap

1. **Sprint 1 — Foundation:** Flutter app, dashboard, navigation, SQLite, AI Assistant UI, and Connection Manager UI.
2. **Sprint 2 — Tool Ecosystem:** Tool Registry, metadata catalog, categories, search, compatibility checks, and basic Download Manager.
3. **Sprint 3 — Android Execution:** Kotlin integration, tool adapters, Policy Engine, and the four P0 local checks.
4. **Sprint 4 — GitHub Integration:** repository metadata, release checking, download verification, tool updates, and per-tool documentation.
5. **Sprint 5 — Hybrid AI:** `llama.cpp`, Model Manager, BYOK cloud AI, and AI tool orchestration.
6. **Sprint 6 — User-Owned Cloud:** backend, database, and storage connectors; Test Connection; optional synchronization.
7. **Sprint 7 — Security and Release:** encryption, compatibility and security testing, documentation, and APK release.

## 14. Final decision

Cybersecurity Assistant is more than a directory of tool links. It is an Android platform integrating a tool catalog, registry, download and execution systems, AI assistance, GitHub sources, and optional user-owned infrastructure.

- **GitHub:** source code, catalog references, documentation, and distribution.
- **Tool Registry:** source of truth for tool metadata and compatibility.
- **Download Manager:** controlled retrieval, validation, installation, and updates.
- **Android Execution Engine:** runs supported tools on-device.
- **AI Assistant:** helps select, configure, and analyze tools through guarded orchestration.
- **User-owned cloud:** optional backend, database, storage, synchronization, and coordination.
- **SQLite:** primary local persistence.
- **Connection Manager:** configuration and testing of user-owned external services.

The project builds the platform and integrations; users control which tools they install, which AI they use, and which cloud infrastructure they connect. Local-first behavior, explicit consent, authorization boundaries, and accurate compatibility reporting are core requirements.
