# Cybersecurity Assistant — Final Technical Blueprint

- **Status:** Product/architecture blueprint; AI Cybersecurity Expert Engine and Embedded Runtime remain planned, not implemented.
- **Platform:** Android-first
- **Product description:** Local-first Android cybersecurity assistant with a planned AI Cybersecurity Expert Engine.
- **Architecture principles:** Local-first, hybrid AI, BYOI (Bring Your Own Infrastructure), BYOK (Bring Your Own Key), a user-controlled tool ecosystem, and no mandatory developer backend.

> **Implementation note:** The repository contains a Flutter UI with splash, dashboard, primary navigation and a secondary Assistant screen; an in-app registry for four P0 entries; a registry-ID-only tool orchestration boundary; guarded DNS/TLS/HTTP-header adapters with a self-attestation audit marker; result analysis/export and opt-in SQLite history; a namespaced secure-credential wrapper and provider-details UI (not wired to provider connectors; Android runtime behavior is unverified); an HTTPS endpoint reachability prototype; a guide-only provider catalog; an allowlisted GitHub release-metadata viewer; and tests. The Assistant is a UI placeholder: no AI model/provider, knowledge base, AI reasoning engine, AI router, internal terminal/runtime, or embedded package manager is implemented. These are early foundations, not a complete or release-ready product. See [`apps/android/README.md`](../apps/android/README.md), [AI Cybersecurity Expert Engine](ai-cybersecurity-expert-engine.md), and [Embedded Runtime Blueprint](embedded-runtime-implementation.md) for details.

## 1. Product concept

Cybersecurity Assistant is an Android application for discovering, managing, and safely using cybersecurity tools. It is planned around five cooperating parts:

1. **Android application** — user interface and control center.
2. **Cybersecurity Tool Engine** — registry, policy checks, adapters, and execution of compatible tools.
3. **AI Cybersecurity Expert Engine (planned)** — cybersecurity reasoning, attributable knowledge retrieval, guarded tool planning, evidence analysis, remediation drafts, and report intelligence. See the [dedicated AI architecture](ai-cybersecurity-expert-engine.md). It is not implemented by the current Assistant UI.
4. **Cybersecurity Knowledge and Result Services** — versioned security references, normalized local findings, provenance, and report contracts shared with the AI and tools (planned or partial as marked in the AI ledger).
5. **User-owned cloud infrastructure** — optional services configured and controlled by each user; it is not a mandatory developer backend.

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

Guarded AI-assisted tool flow (all AI functions are planned):

```text
User + authorized scope
  → Assistant UI → AI Cybersecurity Expert Engine
  → Knowledge Base / Tool Registry (read-only lookup)
  → Policy Engine (scope, parameters, compatibility, consent, limits)
  → Tool Orchestrator → Local Execution Engine / approved adapter
  → Evidence + Result Analyzer + SQLite
  → AI evidence interpretation → Remediation / Report draft
  → user review → optional export or explicitly approved sharing
```

The model proposes, but never authorizes or executes. No free-form shell or policy bypass is allowed. The full module boundary, evidence model, data-sharing consent, and phased plan are specified in the [AI Engine blueprint](ai-cybersecurity-expert-engine.md).

Optional user-owned services:

```text
Android App ↔ User-configured backend ↔ User-configured database/storage
```

When the planned AI layer is implemented, it may use a compatible local model or a provider configured by the user. Local tools and core application functions must remain useful without a cloud account or API key; local-only mode must never silently fall back to cloud inference.

## 6. Android Execution Engine

Planned technologies:

- Flutter for the cross-platform UI.
- Kotlin for Android-native integration.
- ARM64 support where available, with runtime and device checks.
- An app-managed Embedded Runtime is a future option for specifically supported, reviewed Android-compatible tools. Core supported workflows must not require users to install the external Termux app; this does not imply arbitrary Linux tools are compatible. No embedded terminal, shell executor, or package manager is currently implemented. See the [Embedded Runtime Blueprint](embedded-runtime-implementation.md).
- `llama.cpp` is a possible future local-inference runtime, subject to model license, device/ABI/memory/thermal compatibility, and a separate implementation review.

Prioritized tools:

- **P0 — local basics:** DNS Lookup, SSL/TLS Inspector, HTTP Header Checker, Security Response Analyzer.
- **P1 — additional tools:** constrained Nmap TCP Connect checks, passive Subfinder workflows, and Gitleaks for user-selected files or repositories.
- **P2 — advanced integrations:** Nuclei with safe, explicitly selected templates; MobSF through a compatible local environment or service.

A binary being built for ARM64 does not make it Android-compatible. Linux, root, Docker, special drivers, or external services may be unavailable. The registry must declare these requirements, and the app must not silently bypass platform restrictions.

## 7. AI Cybersecurity Expert Engine and orchestration

The target is a cybersecurity-focused AI Expert Engine, not a generic chatbot. Its planned capabilities include: curated/versioned cybersecurity knowledge with provenance; security reasoning; evidence-based vulnerability and code analysis; network/infrastructure interpretation; static-first malware assistance; exploit/PoC explanation without automatic execution; timestamped CVE/threat intelligence; remediation drafts; and evidence-grounded reports. It should explain its basis, separate facts from indications and hypotheses, expose limitations, and never claim that a system is secure merely because checks found nothing.

Future findings use four labels: **Confirmed Finding**, **Potential Finding**, **Informational**, and **False Positive**. Each result separates confidence from risk and carries evidence/source references, an “as of” date for changing intelligence, limitations, impact, and next steps. CVE details must not be invented.

The model is an untrusted planner/interpreter. It cannot access arbitrary shell commands, raw credentials, or direct tool adapters. Any proposed action must use a registered Tool ID and typed parameters, then pass independently through the Tool Registry, Policy Engine, and Tool Orchestrator. Active checks require the existing authorization/scope controls and explicit user approval. No automatic exploit or malware execution is allowed. Evidence stays local by default; sending code, findings, or other sensitive data to cloud AI requires informed consent.

Planned providers are Gemini, OpenAI, Anthropic Claude, OpenRouter, custom OpenAI-compatible APIs, and optional local `llama.cpp`/GGUF inference. This is BYOK and local-first hybrid AI: no developer key, mandatory paid provider, or silent cloud fallback. Provider/model managers, smart routing, usage controls, and the full AI engine are not implemented. The current Assistant screen and local rule-based Result Analyzer are not an AI engine. See [AI Cybersecurity Expert Engine — Architecture Blueprint](ai-cybersecurity-expert-engine.md) for full capabilities, source/version model, integration contracts, conceptual module map, security guardrails, current implementation ledger, and staged rollout.

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

Potential connectors include Cloudflare Workers, Firebase, Supabase, R2, S3-compatible storage, WebDAV, OpenAI, Gemini, Anthropic Claude, OpenRouter, custom OpenAI-compatible APIs, VirusTotal, Shodan, and URLScan. Each connection should provide endpoint/configuration fields, authentication setup, a **Test Connection** action, connection status, and provider-specific setup guidance. Tests should use the least-privileged request possible and avoid logging secrets or sending unnecessary data. AI providers remain optional BYOK integrations; no developer API key is bundled, no provider is active by default, and cloud data transfer requires explicit consent. The existing catalog is guide-only and stored credentials are not used by provider connectors.

API keys and tokens must be stored encrypted using Android Keystore-backed protection. Do not embed developer credentials or cloud administrator/master keys in the APK. Secret values should be masked in the UI and excluded from logs, reports, crash data, and analytics.

## 10. Operating modes

### Standalone Mode

- SQLite and local history.
- Locally available tools and registry.
- Local reports.
- Planned optional local AI after a compatible model/runtime is installed; not implemented.
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
ai/core
ai/reasoning
ai/knowledge_base
ai/vulnerability_analysis
ai/code_security
ai/network_security
ai/malware_analysis
ai/exploit_analysis
ai/threat_intelligence
ai/remediation
ai/report_intelligence
ai/providers
ai/local_inference
ai/cloud_inference
ai/model_manager
ai/smart_router
ai/context_manager
ai/security_guardrails
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
5. **Sprint 5 — AI foundations (future; gated):** contracts, guardrails, curated Knowledge Base, evidence/source formats, then local reasoning and opt-in BYOK/local providers. AI-assisted tool plans remain policy-mediated. Follow the phased gates in the [AI Engine blueprint](ai-cybersecurity-expert-engine.md); this documentation update does not start implementation.
6. **Sprint 6 — User-Owned Cloud:** backend, database, and storage connectors; Test Connection; optional synchronization.
7. **Sprint 7 — Security and Release:** encryption, compatibility and security testing, documentation, and APK release.

## 14. Final decision

Cybersecurity Assistant is more than a directory of tool links. It is an Android platform integrating a tool catalog, registry, download and execution systems, AI assistance, GitHub sources, and optional user-owned infrastructure.

- **GitHub:** source code, catalog references, documentation, and distribution.
- **Tool Registry:** source of truth for tool metadata and compatibility.
- **Download Manager:** controlled retrieval, validation, installation, and updates.
- **Android Execution Engine:** runs supported tools on-device.
- **AI Cybersecurity Expert Engine (planned):** will help select, configure, and interpret tools through guarded, policy-mediated orchestration; the current Assistant is only a UI placeholder.
- **User-owned cloud:** optional backend, database, storage, synchronization, and coordination.
- **SQLite:** primary local persistence.
- **Connection Manager:** configuration and testing of user-owned external services.

The project builds the platform and integrations; users control which tools they install, which AI they use, and which cloud infrastructure they connect. Local-first behavior, explicit consent, authorization boundaries, and accurate compatibility reporting are core requirements.
