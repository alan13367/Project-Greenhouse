# Backend Selection Gate

Virtualization.framework is evaluated first. QEMU with HVF is the fallback
experiment, not a parallel product commitment.

A candidate is rejected if it only boots Android. It must prove the consumer
product.

| Gate | Required evidence |
| --- | --- |
| ARM64 Linux and target Android boot | Reproducible scripts, serial logs, readiness events |
| Lifecycle | 100 clean start/stop cycles plus sleep/wake and forced-stop recovery |
| Networking/control | Private authenticated host/guest channel and working guest network |
| Per-app windows | Two simultaneous tasks, independent surfaces, focus, resize, orientation |
| Input | Keyboard, IME, pointer, relative pointer, trackpad, and controller routing |
| Audio | Stable output, measured latency, no long-run underruns |
| Graphics | Accelerated GLES and Vulkan evidence, representative games, frame pacing |
| Compatibility | CDD gap analysis and viable CTS/CTS-V execution |
| Google | Plausible, authorized GMS/Play route confirmed by Google |
| Security | Minimal entitlements, no public bridge, runtime isolation |
| Distribution | Signed/notarized clean-machine launch and acceptable licenses |
| Operations | Structured events, diagnostics, crash recovery, update/rollback path |

The decision ADR must include measurements, known gaps, licensing, an explicit
Google impact, and why the losing candidate cannot close the gap economically.
