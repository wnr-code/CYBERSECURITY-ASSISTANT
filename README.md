# CYBERSECURITY-ASSISTANT

Local-first, Android-first cybersecurity assistant with a user-controlled tool ecosystem and optional user-owned infrastructure. The AI Cybersecurity Expert Engine is a planned architecture—not an implemented or connected AI feature. The current Assistant screen is a placeholder; no AI provider is active.

## Project documentation

- [Final Technical Blueprint](docs/technical-blueprint.md) — product architecture, boundaries, and roadmap.
- [AI Cybersecurity Expert Engine Blueprint](docs/ai-cybersecurity-expert-engine.md) — planned AI capabilities, reasoning and provider boundaries, guardrails, phases, and current implementation ledger.
- [Embedded Android Runtime Blueprint](docs/embedded-runtime-implementation.md) — future in-app runtime boundary; no external Termux dependency for supported core functions, but no embedded terminal/runtime is implemented.
- [Documentation index](docs/README.md) — all architecture and verification documents.
- [Static security audit](docs/security-audit.md) — current review findings and verification blockers.
- [Android hardening checklist](docs/android-hardening.md) and [manual device-testing guide](docs/android-device-testing.md).
- [Flutter app foundation](apps/android/README.md) — existing capabilities, limitations, and setup.

The blueprint additions are documentation only. They do not enable AI, add provider connections, execute a runtime, or change application behavior. Local tools and existing safety boundaries remain the source of executable functionality.
