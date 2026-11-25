# Documentation index

## Product and architecture

- [Final Technical Blueprint](technical-blueprint.md) — the parent architecture and product roadmap.
- [Platform Product Blueprint](platform-product-blueprint.md) — unified navigation, distinct Assessment/Findings/Reports/Activity responsibilities, local-first guarantees, future tool domains, and gated runtime/plugin/dependency roadmap.
- [AI Cybersecurity Expert Engine](ai-cybersecurity-expert-engine.md) — proposed cybersecurity knowledge, reasoning, analysis, provider, safety, integration, implementation phases, and current status. This is not an implemented AI feature.
- [Embedded Android Runtime](embedded-runtime-implementation.md) — conceptual in-app runtime and package-management boundaries. No arbitrary shell or external Termux requirement is planned for supported core functions; no runtime is implemented.
- [Market Modular Delivery](market-modular-delivery.md) — owner-confirmed staged target: stabilize the APK, test signed modules from a controlled server, then evaluate Play delivery near release.

## Security and verification

- [Static security audit](security-audit.md) — reviewed foundation, findings, and blockers.
- [Android hardening](android-hardening.md) — Android manifest, backup, network, and build configuration requirements.
- [Android device testing](android-device-testing.md) — manual test cases and device verification checklist.

## Implementation notes

- [Diagnostics Relay setup](diagnostics-relay.md) — local-first diagnostics, explicit consent, secure relay token storage, and Cloudflare Workers + D1 setup.
- [Android app foundation](../apps/android/README.md) — current Flutter features, limitations, setup, and CI verification.

Architecture documents describe intended or proposed work and must not be read as evidence that a feature is implemented. Consult the implementation notes and security audit for actual status.
