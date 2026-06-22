# ADR 0001: Swift-owned app with a backend-neutral core

- Status: accepted
- Date: 2026-06-23

## Context

Virtualization.framework lifecycle, SwiftUI/AppKit windows, macOS input, and
GameController integration are native platform concerns. Backend feasibility is
still unproven, so the product must not depend directly on one backend.

## Decision

Use a Swift-owned macOS application and domain model. Hide backend
implementations behind a small asynchronous protocol and versioned structured
events. Use SwiftPM for the Phase 1 build so the core and tests remain easy to
run while the final signing project is not yet fixed.

Rust or other tools may be added for isolated package verification, archive
handling, or build tasks when evidence justifies them. There is no default
long-running sidecar service.

## Consequences

The fake backend can drive the complete product state model and UI before a VM
backend is accepted. A later Xcode project may wrap the package for signing and
entitlements without moving domain behavior into UI code.

## Revisit triggers

- A backend requires a process boundary for security or licensing.
- Swift cannot meet a measured performance or safety requirement in an isolated
  subsystem.
- Production signing or packaging reveals a SwiftPM limitation that an Xcode
  project must own.
