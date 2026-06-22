# Performance Metrics and Measurement

Performance claims require a release build, a named Mac model, macOS version,
runtime build, backend, guest image, app version, display size/scale, and test
duration. Report median, p95, and worst observed values where meaningful.

| Metric | Start/stop points | Primary method |
| --- | --- | --- |
| Cold boot | launch request → Android ready event | Monotonic host signposts and guest readiness event |
| Warm resume | resume request → Android ready | Same event correlation |
| App-window creation | open request → first visible frame | Host signposts plus frame-present event |
| Resize latency | resize input → correctly sized frame | Window/display timestamps and video spot checks |
| Idle/active CPU | stable 60-second windows | Instruments Time Profiler / `powermetrics` where permitted |
| Host and guest memory | stable idle and representative workload | Instruments Allocations, VM statistics, guest metrics |
| Frame rate/pacing | representative 3D scene | Metal frame capture and guest renderer timestamps |
| Input latency | host event → guest consume/present | Correlated host/guest monotonic timestamps; high-speed camera validation |
| Audio latency/stability | guest submit → host output | Loopback test, underrun counters, long-run playback |
| Controller latency | GameController event → guest consume/present | Correlated event IDs and camera validation |
| Network throughput/latency | guest workload through virtual network | Controlled local endpoint before internet tests |
| Runtime size/download | manifest → installed footprint | Signed manifest sizes and filesystem accounting |
| Start/stop reliability | repeated clean and forced cycles | Automated soak count with corruption check |

## Measurement rules

- Use `os_signpost` categories with stable operation and correlation IDs.
- Use `ContinuousClock` or another monotonic clock for durations; wall time is
  for display only.
- Discard warm-up runs only when the report says so.
- Keep raw traces outside Git when large; commit compact summaries and scripts.
- Define performance modes only after measurements show a user-visible benefit.
