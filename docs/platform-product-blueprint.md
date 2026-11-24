# Cybersecurity Assistant — Platform Product Blueprint

**Status:** Approved product direction. This document describes the platform boundary and roadmap; it does not claim future engines are implemented.

## Product identity

Cybersecurity Assistant is an Android cybersecurity platform with a user-controlled ecosystem of registered assessment adapters. It is not a website-scanner directory. Android is the control plane; specialized tools are validated engines behind one assessment and findings workflow.

## Navigation and responsibilities

- **Dashboard:** operational overview, recent authorized assessments, unresolved findings, target summaries, and a primary “New assessment” action. Metrics must be derived from completed local data, not placeholders.
- **Assessment:** target/scope consent, explicit check selection, orchestration, actual per-check progress/status, cancellation where supported, and a consolidated result. It is the normal entry point for multiple checks.
- **Findings:** normalized technical observations across assessments. Each finding has evidence/provenance, severity, confidence where available, affected target, status, and remediation guidance. Findings are not synonymous with a scan run.
- **Reports:** a reviewed/exportable snapshot of one or more assessments, with scope, timestamps, checks attempted/completed/failed, evidence, findings, limitations, and optional user-selected export destination.
- **Activity:** chronological audit trail of user actions and assessment/check lifecycle (queued, started, completed, failed, cancelled, exported, deleted). It is not a finding list or a report. Audit entries must not contain secrets or raw response bodies.
- **Tool Registry/catalog:** a supporting capability browser and manual single-tool launch. Assessment remains the default workflow; catalog entries never imply executability unless a tested adapter exists.
- **Settings / Connections:** local privacy and optional BYOI/BYOK configuration. No provider, cloud service, database, storage, AI, or remote API is mandatory for local checks.

The existing primary navigation can evolve incrementally; this blueprint does not require a large rewrite or deletion of working screens.

## Assessment and shared result flow

```text
User-owned/authorized target + explicit scope
  → Assessment plan (registered Tool IDs only)
  → Policy and local capability checks
  → Tool Orchestrator (bounded, observable execution)
  → per-check status + evidence + limitations
  → normalized Findings (local by default)
  → Activity event stream + optional Reports/export
  → optional, separately consented user-owned integrations
```

Each check reports a real outcome (`completed`, `partial`, `failed`, `skipped`, or `cancelled`). Failed checks remain visible and do not become “no findings.” A clean result means only that the checks actually run did not observe their defined indicators; it is not proof that a target is secure.

## Tool ecosystem and planned domains

The registry must support multiple capability domains without treating them as different apps: Web Security, Network Security, OSINT, APK/Mobile Security, Code Security, Cloud Security, Vulnerability Assessment, Malware Analysis, and Threat Intelligence. A category is metadata, not evidence that an engine exists.

Long-term ecosystem components remain in the architecture: Embedded Runtime, Plugin Store, Plugin Manager, Dependency Manager, and verified Download/Update Manager. They are **planned**, not currently available. Any future plugin/runtime requires source/license review, Android/device compatibility checks, dependency and integrity verification, least privilege, user approval, sandbox/isolation design, and a no-auto-execution policy. No arbitrary shell, downloaded code execution, or plugin execution is part of the current implementation.

## Local-first and BYOI/BYOK

Built-in supported checks must work without cloud accounts, developer-controlled services, AI providers, or user API keys. Results remain on-device unless the user explicitly exports or configures their own backend/database/storage. Optional connections must identify their owner, data sent, credentials requested, cost implications, and implementation status. A guide/catalog entry is not an active connector.

## Phased delivery gates

1. **P0 verification and evidence:** make DNS, TLS, HTTP headers, and response analysis technically real; test deterministic logic and safe request bounds; clearly report unsupported DNS record types and other limitations.
2. **Unified assessments:** execute multiple registered checks under one target/scope, preserve per-check failures and timestamps, and consolidate results without losing individual evidence.
3. **Separate findings, reports, activity:** introduce explicit contracts and local persistence, with privacy-safe audit events and export review.
4. **Navigation integration:** make Dashboard and Assessment central, keep the catalog supporting, and make Connections optional. Do not use UI to imply missing capabilities.
5. **Future engines (gated):** only after design and security review, separately plan AI Cybersecurity Expert, user-owned connectors, Embedded Runtime, Plugin Store/Manager, Dependency Manager, and domain-specific engines. No future engine may be marked available until implemented and tested on-device.

## Non-claims

The current assistant UI is not an AI expert. The local rule-based response/findings analyzer is not an AI model. Current registry metadata is not a plugin manager. A catalog/download reference is not an embedded runtime. A successful HTTP response is reachability evidence, not a security assessment.
