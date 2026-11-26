# AI Cybersecurity Expert Engine — Architecture Blueprint

- **Status:** Approved blueprint for the full AI Expert Engine; that broader engine remains unimplemented. A narrow Gemini Assistant adapter and guarded registered-tool loop exist in the current app.
- **Scope:** Architecture and delivery plan for capabilities beyond the narrow current Gemini path. This document does not claim a knowledge base, full reasoning/inference engine, or comprehensive automated security analysis.
- **Platform:** Android-first; works without a cloud account. Cloud AI is opt-in and user-configured.
- **Parent architecture:** [Final Technical Blueprint](technical-blueprint.md).

> The current app has a secondary Assistant with opt-in Gemini chat using a user-owned key, explicit per-request data-sharing consent, and a guarded registered-tool proposal loop. A local Result Analyzer also operates on existing tool results. There is no full cybersecurity reasoning engine, knowledge retrieval, CVE intelligence service, code-analysis engine, smart AI router, local model runtime, or AI-authored report engine. Do not confuse the narrow Gemini integration with the full Expert Engine.

## 1. Product role and boundaries

The **AI Cybersecurity Expert Engine** is the planned cybersecurity reasoning and explanation layer of Cybersecurity Assistant. It is not a general-purpose chatbot, an unrestricted agent, or an execution environment. It may explain evidence, identify gaps, recommend registered checks, and prepare reviewed remediations. It cannot authorize itself, invent evidence, bypass policy, or run arbitrary commands.

The Engine must follow the existing product decisions:

- Android is the primary platform; the local-first application remains useful offline and without an AI account.
- BYOK and user-owned infrastructure are optional. No developer API key or mandatory developer-operated AI backend is permitted.
- Local model inference is an optional capability subject to device/runtime compatibility; it is not assumed to work on every handset.
- A provider receives only the minimum data needed after an explicit, informed user choice. Sensitive evidence is local by default.
- The Tool Registry is the source of truth for executable capabilities. The AI may suggest a tool, but only the trusted application path can validate and execute it; no free-form shell commands are exposed to the model.
- Active testing is limited to user-owned or explicitly authorized targets. Confirmation is a user assertion, not independent proof of legal authorization.
- No automatic exploitation, malware execution, unrestricted shell, or unbounded scanning.

## 2. Capabilities in the target design

| Capability | Planned responsibility | Evidence and safety boundary |
|---|---|---|
| Cybersecurity Knowledge Base | Versioned, attributable retrieval for official standards, advisories, protocol references, and reviewed project documentation. | Store source, canonical URL/identifier, publisher, version, retrieved/updated time, license/terms, and content hash where appropriate. A source's currentness must be visible. |
| Security Reasoning Engine | Interpret the question and context; identify unknowns; propose safe checks; connect results; explain reasoning and limitations. | Separate facts from interpretation and hypotheses. Cite evidence/source IDs. No direct tool execution. |
| Vulnerability Analysis | Assess the requested classes: SQLi, XSS, SSRF, RCE, path traversal, broken authentication, IDOR, misconfiguration, insecure deserialization, TLS and HTTP-header issues. | Classify only what the supplied evidence supports; a pattern match alone is not a confirmed finding. Do not trigger exploits automatically. |
| Code Security Analysis | Review supported source languages: Python, JavaScript/TypeScript, PHP, Java/Kotlin, Dart/Flutter, HTML/CSS, SQL, and Bash. Examine input flow, validation, authn/authz, secrets, unsafe APIs, and framework-specific patterns. | Static reasoning first; code is untrusted input. Do not execute supplied code. Cloud review requires a separate data-sharing consent step. |
| Network and Infrastructure Analysis | Explain DNS, TCP/IP, ports/services, TLS/SSL, HTTP(S), firewall/server configuration, cloud and edge-service configuration, and available security headers. | Only use facts returned by supported checks or explicitly supplied configuration. Cloudflare, Firebase, Supabase, and other services are reference categories, not active connectors unless separately implemented. |
| Malware Analysis Assistant | Help review static file metadata, hashes, strings, and supplied indicators of compromise (IOCs). | Never execute a suspicious file. Dynamic behavior analysis is out of scope until an isolated, separately threat-modeled sandbox exists. |
| Exploit and PoC Understanding | Explain vulnerability mechanisms, preconditions, impact, safe verification, and remediation for a supplied PoC. | No automatic exploit execution or target discovery. Keep validation within an authorized, bounded environment. |
| CVE Intelligence and Threat Analysis | Summarize CVE, CVSS, CWE, affected product/version, impact, advisory references, and patch/mitigation status. | Use attributable source data and an “as of” timestamp. If fresh data is unavailable, say so. Never fabricate CVE details, severity, affected versions, or patch status. |
| Security Remediation | Explain cause, risk-prioritized mitigation, safer configuration/code examples, and post-fix verification. | Clearly distinguish illustrative recommendations from changes actually applied. Do not silently modify a target or repository. |
| Security Report Intelligence | Draft an executive summary, scope/target, method, findings, evidence, risk and confidence, limitations, impact, remediation, and technical references. | Generated output is a draft derived from retained evidence; users review it before export or sharing. |

### Finding and confidence vocabulary

Every future finding should use one of these states and expose evidence, confidence, risk, limitations, and next steps:

1. **Confirmed Finding** — adequate direct evidence supports the vulnerability under the stated scope. It does not mean the entire system was comprehensively tested.
2. **Potential Finding** — an indicator exists, but needs safe verification or more context.
3. **Informational** — useful security context without direct evidence of a vulnerability.
4. **False Positive** — evidence reviewed within stated limits does not substantiate the proposed issue; retain the reason and do not present it as a confirmed weakness.

Risk/severity and confidence are different dimensions. Absence of findings must never be presented as proof that a system is secure.

## 3. Knowledge Base design

### Initial source families

- OWASP Top 10 and OWASP Web Security Testing Guide.
- MITRE ATT&CK.
- CVE records, CVSS data, CWE, and vendor/security advisories.
- NIST Cybersecurity Framework and relevant NIST publications.
- Official operating-system, networking, protocol, language, framework, and cloud-security documentation.
- Reviewed project tool metadata, adapter documentation, and result schemas.

Prefer canonical publisher sources. Third-party material may be included only with provenance and license/terms review. This plan does not imply that any source has already been ingested or that the app currently performs live threat-intelligence lookups.

### Record and update model

Each source/document record should include a stable source ID, title, publisher, canonical URL or standard identifier, version/release, source publication date if supplied, last retrieval/check time, content hash, license/usage notes, and parsing/index status. Retrieval results should preserve the source ID and relevant section/page/record locator so explanations can be traced to source material. Update jobs must be bounded, attributable, and report failures/staleness rather than quietly replacing known-good data.

A future implementation may use a small curated offline index first, then optionally add user-enabled remote lookup. Select a storage/index technology only after offline size, Android memory, license, update integrity, and deletion requirements are evaluated. No vector database or cloud index is mandated by this blueprint.

## 4. Reasoning and tool integration

### Trust boundary

The model is an untrusted planner and interpreter. It must not own network sockets, shell access, credentials, or a direct tool adapter. Structured requests go to application services, which validate them independently. The model output is never treated as policy authorization.

### Required sequence

```text
User question + scope/context
  → Assistant context manager (minimize and label data)
  → Security reasoning (identify intent, gaps, and safe plan)
  → Knowledge retrieval with source/version citations
  → Tool Registry + approved Plugin Manager metadata (registered capabilities only)
  → Runtime Manager (read-only compatibility/availability check; no installation)
  → Policy Engine (scope, parameters, consent, compatibility, rate/time bounds)
  → Tool Orchestrator (typed, allowlisted request; audit event)
  → Local Execution Engine / supported adapter
  → Result Analyzer + SQLite evidence/history (existing local foundation)
  → AI interpretation (facts vs indicators vs hypotheses; citations and confidence)
  → Remediation draft / Report Engine
  → User review before export or optional sharing
```

AI may propose a sequence, but each action is independently authorized and policy-checked. A denied, unsupported, or out-of-scope request returns an explanation; there is no fallback to arbitrary shell or an unregistered plugin. Sensitive result data remains local unless the user sees and accepts a specific cloud-sharing disclosure. The audit trail records tool IDs, scope/consent decisions, provider/model selection, timestamps, and outcome without recording API keys or unnecessary sensitive content.

### Integration contracts and dependency direction

- **Assistant UI → AI facade:** sends a user request and explicit context; receives a structured answer, citations, optional proposed actions, and uncertainty/limitations.
- **AI facade → Context Manager / Knowledge Base / Provider interface:** no access to platform secrets or execution internals.
- **Reasoning → Tool Registry / Plugin Manager:** read-only lookup of registered tools and reviewed plugin metadata. The AI cannot install, update, or activate a plugin.
- **Reasoning → Runtime Manager:** read-only check that a required, approved runtime/tool is installed and compatible; no automatic download, install, or runtime mutation.
- **Reasoning → Policy Engine → Tool Orchestrator:** typed request only; policy/orchestrator reject invalid or unauthorized plans regardless of model output.
- **Tool result → Result Analyzer / local store → AI analysis:** analyze normalized, locally retained evidence; keep source and result provenance.
- **Report Intelligence → Report Engine:** submit a structured draft built from evidence references; the report layer owns export and user confirmation.
- **Credential vault → Provider adapter:** secrets are obtained only for the selected provider call, never exposed to prompts, logs, reports, or tool adapters.

Keep the AI layer above shared result/request contracts; do not create circular dependencies from Tool Registry or Policy Engine back into model code.

## 5. Provider and model architecture

### Provider support and optional delivery target

- **Google Gemini:** a narrow provider adapter is currently implemented in the base app. The target is to move its provider-specific code/UI behind an optional Market module while preserving user-owned keys and per-request consent.
- **OpenAI, Anthropic Claude, OpenRouter, custom OpenAI-compatible APIs:** catalog/guidance entries only; provider requests are not implemented.
- **Local inference:** optional future `llama.cpp`/GGUF or another reviewed Android-compatible runtime, subject to ABI, memory, thermal, license, integrity, and actual inference checks. The target is a separately selectable Market module/runtime and model data package; neither currently exists.

The owner-confirmed Market delivery target and the distinction between provider module installation, provider connection, and model readiness are specified in [Market Modular Delivery](market-modular-delivery.md). The existing credential boundary and current Gemini flow must remain intact when optional delivery is implemented.

### Provider Manager, Model Manager, and Smart AI Router

- **Provider Manager / Connection Manager:** user-owned provider configuration, connection state, endpoint validation, key rotation/deletion through the secure credential boundary, and provider-specific data-sharing disclosures. The AI engine must not read raw credentials. BYOK only; no bundled developer credentials.
- **Model Manager:** model/source/license/version metadata, supported runtime/device requirements, integrity checks where published, storage estimate, download consent, and safe removal. Do not auto-download or execute a model artifact.
- **Smart AI Router:** optional user-selected routing among configured providers/local inference, with explicit fallback policy, usage/request limits, and clear reporting of provider/model used. No silent cloud fallback from a local-only choice.
- **Context Manager:** scope minimization, secret/PII redaction proposals, local evidence references, token/window budgeting, and explicit cloud consent. Redaction is best-effort and must not be described as perfect.
- **Security Guardrails:** structured output validation, prompt-injection/data-as-instruction handling, bounded requests, refusal/denial paths, tool allowlists, policy enforcement, and audit records.

Cloud consent is per clear operation or an equally explicit user setting, with a visible summary of which data and provider will receive it. Usage caps and provider fallbacks must be user-controlled. API credentials use the existing secure-storage design only after its Android behavior is verified; never put secrets in source, build assets, prompts, analytics, or test fixtures.

## 6. Conceptual module map

This is a target architecture map, not a request to create empty directories. Map components onto existing repository packages when implementation begins; avoid duplicate registries, policy engines, result stores, or provider managers.

```text
ai/
  core/                     # facade, typed request/response contracts
  reasoning/                # intent, evidence synthesis, safe plans
  knowledge_base/           # source catalog, retrieval, version/provenance
  vulnerability_analysis/   # evidence-based vulnerability reasoning
  code_security/             # non-executing source review
  network_security/          # interpretation of supported network evidence
  malware_analysis/          # static-only assistant initially
  exploit_analysis/          # PoC understanding; no auto-execution
  threat_intelligence/       # sourced CVE/advisory/CWE/CVSS interpretation
  remediation/               # prioritized, reviewable recommendations
  report_intelligence/       # structured report drafts
  providers/                 # provider abstraction and adapters
  local_inference/            # optional local model runtime integration
  cloud_inference/            # opt-in user-configured provider calls
  model_manager/              # model metadata, integrity, compatibility, lifecycle
  smart_router/               # user-governed provider/model selection and fallback
  context_manager/            # data minimization, provenance, consent boundary
  security_guardrails/        # validation, policy bridge, refusal, audit hooks
```

The existing repository currently contains `apps/android/` and core tool, policy, provider-catalog, credential, persistence, and report code inside that app package. The proposed `ai/` map is conceptual; actual extraction or package boundaries require a later design/implementation task.

## 7. Embedded Android runtime relationship

The AI Engine does not require an unrestricted terminal or Termux. A future app-managed Embedded Runtime may host specifically supported Android-compatible tools, while the AI can only refer to those tools through the same registry/policy/orchestrator path. The goal is that supported core functions do not require users to install the external Termux app, root, or Docker. This does **not** promise that arbitrary Linux tools will run inside the APK.

Runtime/package-management decisions, Android sandbox limits, ABI compatibility, licenses, and any optional terminal-like UI are documented separately in [Embedded Runtime Implementation Blueprint](embedded-runtime-implementation.md). That document is also conceptual; no such runtime is implemented in the current app.

## 8. Phased implementation plan

This sequence is a proposal for later approval and does not authorize feature implementation in this documentation task. UI/UX, Indonesian localization, and application foundations remain prerequisites before the AI feature work starts.

| Phase | Priority | Deliverable and exit checks |
|---|---:|---|
| 0. Blueprint and UX foundation | Current foundation / documentation | Keep existing Gemini capability accurately disclosed; approve full-Engine and optional-module flows, Indonesian terminology, privacy disclosures, and this architecture. No claim of full AI reasoning or Local AI inference. |
| 1. Contracts and guardrails | P0 | Typed AI request/answer, evidence/citation and finding schemas; threat model; authorization, scope, consent, audit, and refusal tests. No execution tool exposed to the model. |
| 2. Knowledge source foundation | P0 | Curated official-source metadata/version/provenance, update policy, offline baseline, staleness behavior, license review, and citation evaluation. |
| 3. Local result reasoning | P0 | Explain and correlate existing normalized tool results locally; label confirmed/potential/informational/false positive; demonstrate evidence traceability and limitations. |
| 4. Provider abstraction and consent | P1 | Provider/model interfaces, secure key lifecycle, per-operation cloud consent, usage limits, no silent fallback, and mock-provider tests. Then implement individual providers by priority. |
| 5. Local inference and routing | P1 | Device/ABI/memory/thermal checks, vetted model metadata and integrity, opt-in install/removal, local-only routing and model lifecycle tests. |
| 6. Code and vulnerability analysis | P1 | Non-executing supported-language analysis, evidence-grounded vulnerability classes, safe examples, false-positive handling, and adversarial prompt/input tests. |
| 7. CVE/threat intelligence | P1 | Bounded source-backed queries with retrieved-at dates, CVSS/CWE/product/version provenance, stale/unavailable/error states, and no-fabrication tests. |
| 8. Policy-mediated tool plans | P1 | Model proposals use registered tool IDs and typed parameters; orchestrator revalidates scope, authorization, compatibility, rate/time budgets; denied plans are not executed. |
| 9. Remediation and reports | P2 | Reviewable fix drafts and structured report output, source/evidence references, confidence/risk/limitations, user approval before changes or sharing. |
| 10. Malware/PoC and advanced integrations | P2 / gated | Static-only assistance first. Dynamic analysis remains blocked until a genuinely isolated, audited sandbox and separate threat model exist; no automatic exploit or malware execution. |
| 11. Evaluation and release gate | Required | Offline, provider, privacy, safety, authorization, prompt-injection, provenance, usability, localization, performance, Android compatibility, and regression suites pass before any release claim. |

## 9. Required validation and release criteria

Before describing any AI capability as implemented, verify at minimum:

- Answers identify evidence/source and timestamp where relevant, mark uncertainty, and do not claim comprehensive security from a clean scan.
- CVE data is never fabricated; unavailable/stale sources are clearly reported.
- No model output can invoke shell, arbitrary URLs, unregistered tools, or bypass a denial/authorization gate.
- Sensitive content is not sent to cloud without explicit informed consent; local-only mode has no network fallback.
- Secrets are absent from logs, reports, prompts, analytics, crash output, and repository artifacts.
- Result/report outputs preserve evidence provenance, risk/confidence distinction, limitations, and user review.
- Tests cover malicious prompt content, malformed model output, network/provider failure, denial paths, timeout/rate limits, data minimization, and Android compatibility.

## 10. Current implementation ledger

| Area | Current repository state | Blueprint status |
|---|---|---|
| Assistant interface | Secondary Assistant now has opt-in Gemini chat after a user-owned API key is saved; every request discloses provider data sharing. | Narrow live provider integration; not the full expert engine. |
| Knowledge Base / citations | No source ingestion, versioned retrieval, or citation engine. | Planned. |
| Tool Registry and orchestration | Registered-tool AI proposals pass the strict bridge, ready check, explicit proposal review, existing scope policy, and a second Tool Runner authorization step. Tool activities correlate to AI request IDs. | Narrow, bounded planner loop; no free-form commands or Market code execution. |
| Result analysis | Local rule-based analyzer operates on existing results; reports/session/SQLite foundations exist. | Not AI reasoning; evidence-correlated AI analysis is planned. |
| Provider catalog / credentials | Provider Manager uses a user-owned Gemini key from secure storage; fixed-origin HTTPS adapter sends prompts only after explicit per-request consent. Other cloud providers remain catalog-only. | Gemini connected; Local AI adapter contract is ready but no local runtime is bundled or activated. |
| Local inference / models | No local model runtime, model manager, or router. | Planned only. |
| Code, malware, exploit, CVE analysis | No AI engines or dynamic sandbox. | Planned only; execution constraints apply. |
| Remediation / report intelligence | Existing report/export foundation is not AI-generated. | AI draft/review intelligence is planned. |
| Embedded Runtime | No bundled general-purpose terminal or internal package/runtime manager. | Separate conceptual blueprint; not implemented. |

Do not use “AI Cybersecurity Expert Engine complete/active” in product copy until its implementation and release criteria are demonstrably met. See the [app foundation notes](../apps/android/README.md) and [security audit](security-audit.md) for more implementation limitations.
