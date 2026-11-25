# CYBERSECURITY-ASSISTANT

Local-first, Android-first cybersecurity assistant with a user-controlled tool ecosystem and optional user-owned infrastructure. The full AI Cybersecurity Expert Engine remains planned; the Assistant now includes a narrow opt-in Gemini provider and guarded registered-tool loop. Gemini calls require a user-owned key and explicit per-request data-sharing consent.

## Project documentation

- [Final Technical Blueprint](docs/technical-blueprint.md) — product architecture, boundaries, and roadmap.
- [AI Cybersecurity Expert Engine Blueprint](docs/ai-cybersecurity-expert-engine.md) — planned AI capabilities, reasoning and provider boundaries, guardrails, phases, and current implementation ledger.
- [Embedded Android Runtime Blueprint](docs/embedded-runtime-implementation.md) — future in-app runtime boundary; no external Termux dependency for supported core functions, but no embedded terminal/runtime is implemented.
- [Market Modular Delivery](docs/market-modular-delivery.md) — persistent Market and staged module strategy: stabilize the base APK, test signed modules from the official server, evaluate Play delivery near release.
- [Documentation index](docs/README.md) — all architecture and verification documents.
- [Diagnostics Relay setup](docs/diagnostics-relay.md) — local-first reporting, consent flow, and Cloudflare Workers + D1 deployment.
- [Static security audit](docs/security-audit.md) — current review findings and verification blockers.
- [Android hardening checklist](docs/android-hardening.md) and [manual device-testing guide](docs/android-device-testing.md).
- [Flutter app foundation](apps/android/README.md) — existing capabilities, limitations, and setup.

The blueprints describe the broader roadmap and do not imply that the full AI engine or embedded runtime is complete. Gemini is opt-in and no provider is called without explicit consent; local registered tools and existing policy boundaries remain the only executable security checks.
