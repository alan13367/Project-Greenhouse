# ADR 0002: Do not select a production backend after Phase 2

- Status: superseded by ADR 0004
- Date: 2026-06-23

## Context

Greenhouse requires one persistent Android system, independent Mac windows for
Android tasks, accelerated games, native input and audio, authorized Google
Play, and distributable signed software. Phase 2 compared
Virtualization.framework with QEMU/HVF against that whole product.

## Decision drivers

- Accelerated OpenGL ES and Vulkan are release requirements.
- Two Android tasks must become independently resizable Mac windows.
- Controller and relative-pointer input must reach the correct task.
- Google Play must use a written licensing and certification path.
- The selected stack must survive Developer ID signing and notarization.

## Options considered

### Virtualization.framework

ARM64 Linux boot, lifecycle, storage, DHCP networking, keyboard, absolute
pointer, audio, VirtioFS, vsock, and `VZVirtualMachineView` all work. The public
Linux GPU supports one 2D scanout and exposes no accelerated 3D/Vulkan path.

### QEMU with HVF

ARM64 Linux boot, Virtio devices, two 2D scanouts, and QMP work. The tested
macOS QEMU build exposes no VirGL/Venus renderer or OpenGL-capable display
backend. QEMU would also add a large GPL-2.0 distribution and maintenance
surface.

## Decision

Select neither candidate for production. At the time, stop product expansion
until a credible accelerated graphics and independent-surface path is
demonstrated.

Google Play and release notarization remain independent blockers even if the
technical graphics gap is solved.

## Consequences

- Phase 2 is complete with a no-go outcome.
- The fake-backend product foundation remains valid and testable.
- No Android runtime, unofficial Google bundle, or production VM backend is
  added to the main app.
- Future work is focused on graphics/surface research and external
  authorization rather than UI polish.

## Validation

The measured conclusions are summarized in `docs/backend-decision.md` and
`docs/graphics-architecture.md`. The one-off probe code and downloaded guest
artifacts were intentionally removed after the decision was recorded.

## Revisit triggers

- Apple exposes an accelerated Linux graphics API with multiple exportable
  displays or custom-device primitives sufficient to implement one.
- A redistributable QEMU renderer provides accelerated GLES/Vulkan on macOS and
  separate host surfaces with acceptable performance.
- Another backend satisfies the same security, licensing, and distribution
  criteria.
- Google confirms the hosted Android form factor is eligible for GMS.
