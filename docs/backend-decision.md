# Backend Selection Decision

Decision date: June 23, 2026.

Phase 2 decision: **no production backend selected**. That no-go remains valid
for the two candidates tested in Phase 2. See
[`adr/0002-platform-feasibility-no-go.md`](adr/0002-platform-feasibility-no-go.md).

Phase 3 decision: adopt the open-source Android Emulator engine with an ARM64
Goldfish/Ranchu guest, HVF, and gfxstream/MoltenVK. See
[`adr/0004-ranchu-emulator-engine.md`](adr/0004-ranchu-emulator-engine.md).

| Gate | Virtualization.framework | QEMU/HVF |
| --- | --- | --- |
| ARM64 Linux boot | Passed | Passed |
| Serial/lifecycle | Native APIs passed | Serial and QMP passed |
| Storage/network | Passed | Passed |
| Private guest transport | Virtio socket present | Not integrated |
| Keyboard/pointer | Passed | Passed |
| Audio device | Passed | Passed with host-input warning |
| Display | One working 2D scanout | Two working 2D scanouts |
| Per-app Mac windows | Failed | Not proven |
| Accelerated GLES/Vulkan | Failed | Failed |
| Controller/relative pointer | Failed | Not implemented |
| Android/CTS | Plan defined; Android not booted | Same |
| Google authorization | Blocked | Blocked |
| Developer ID/notarization | Blocked | Not pursued |
| Licensing | Apple system framework | QEMU GPL-2.0-only plus dependencies |

Virtualization.framework and generic QEMU remain rejected as Android display
backends. The Android Emulator engine is QEMU-derived but is treated as a
separate product backend because it supplies the Ranchu guest contract,
gfxstream renderer, emulator pipes, codecs, and macOS host integrations needed
by Android.
