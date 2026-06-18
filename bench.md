# Shared-VM CPU contention benchmark

Purpose: measure how much a shared-tenant cloud VM gets descheduled by the
hypervisor ("swapped for another tenant") and how much CPU-access jitter that
causes. Steal-time accounting is unreliable on some hypervisors, so this suite
deliberately cross-checks the kernel's `%steal` counter against a wall-clock
jitter probe — the two disagreeing is itself the headline result.

**Results are first.** To reproduce this on another machine, see [How to run this on another machine](#how-to-run-this-on-another-machine) at the bottom — the full procedure is still there.

---

## Results

### Overview — all metrics, all machines

| Metric | Machine A (CX33) | Machine B (CPX32) | Machine C (CCX23) | Machine D (Infomaniak PubCloud) | Machine E (Infomaniak VPS) |
|---|---|---|---|---|---|
| Instance type | Hetzner CX33 (shared vCPU) | Hetzner CPX32 (shared vCPU) | Hetzner CCX23 (**dedicated vCPU**) | Infomaniak `a4-ram8-disk80-perf1` (shared, OpenStack) | Infomaniak VPS (4 vCPU/4 GB; **manual order — no create API**) |
| CPU model | AMD EPYC-Rome (Zen 2) | AMD EPYC-Genoa (Zen 4) | AMD EPYC-Milan (Zen 3) | AMD EPYC-Rome (Zen 2) | **AMD EPYC-Genoa (Zen 4)** |
| vCPUs / topology | 4 (1s × 4c × 1t) | 4 (1s × 4c × 1t) | 4 (1s × 2c × **2t, SMT**) | 4 (**2s × 2c** × 1t) | 4 (2s × 2c × 1t) |
| Reported clock | ~2.45 GHz | ~2.40 GHz (2396 MHz) | ~2.40 GHz (2399.996 MHz) | **~2.00 GHz** (1996 MHz) | ~2.40 GHz (2396 MHz) |
| BogoMIPS | 4890.8 | 4792.8 | 4799.99 | **3992.5** | 4792.8 |
| RAM | 8 GB | 8 GB | 16 GB | 8 GB | **4 GB** |
| Disk | 80 GB | 160 GB | 160 GB | 80 GB | 80 GB |
| Virtualization | KVM full | KVM full | KVM full | KVM full | KVM full |
| Gross / month (EU, incl. VAT) | **€10.10** (net €8.49) | €42.23 (net €35.49) | €102.33 (net €85.99) | **~€20.0 net** (ex VAT — see note) | **€10.80** (as ordered) |
| Gross / hour (EU) | **€0.0162** | €0.0677 | €0.1640 | ~€0.0274 net | ~€0.0148 |
| Included traffic | 22 TB | 22 TB EU / 2 TB sin | 22 TB EU / 2 TB US+sin | metered / fair-use | fair-use |
| Price ratio (vs CX33) | 1× | 4.18× | **10.13×** | ~2.4× (net vs A net) | ~1.07× (vs A gross) |
| `%steal` under 12s full load | **0.00** (every sample) | **0.00** (every sample) | **0.00** (every sample) | **0.04 avg — nonzero** (0.25 in 2/12) | **0.00** (every sample) |
| Aggregate during load | ~99.4% usr, 0% idle | ~99.7% usr, ~0.02% idle | ~99.9% usr, 0% idle | ~99.8% usr, 0% idle | ~99.9% usr, 0% idle |
| Cumulative steal counter moved? | **No** (0) | **No** (89 ticks) | **No** (0) | **Yes** (steal exposed) | exposed; ~nil (cpu0 +0–1) |
| Wall-time lost to >200µs stalls | **2.9–4.0%** | **0.00%** | **0.00%** | **0.6–0.9%** | **0.02–0.03%** |
| Stalls > 200µs | ~41–45 /s | **0** | **0** | ~3–9 /s | ~0–1 /s (5–8 total) |
| Stalls > 1ms | ~8–12 /s | **0** | **0** | ~2 /s | 0–1 total |
| Worst single stall | **5.7–7.9 ms** | 0.09–0.10 ms | 0.12–0.14 ms | **5.0–5.4 ms** | 0.95–1.12 ms |
| Involuntary ctx switches | ~6.5 /s (65/10s) | ~4.9 /s (46–52/10s) | ~4.4 /s (41–46/10s) | ~7–8 /s (70–77/10s) | ~5 /s (49–51/10s) |
| cpu0 steal ticks delta | **0** | **0** | **0** | **1** (nonzero) | 0–1 |
| Single-core loop rate | ~2.2M/s (0.46µs median) | ~3.6M/s (~0.27µs mean) | ~3.55–3.65M/s (~0.27µs mean) | ~2.0–2.4M/s (~0.41–0.49µs mean) | **~4.3–4.4M/s** (~0.23µs mean) |
| Throughput per €/mo (gross) | **~0.218M /s** | ~0.085M /s | ~0.035M /s | ~0.11M /s (net) | **~0.40M /s** |

Per-test detail and interpretation follow below. (D and E are both Infomaniak but
*different products*: D is Public Cloud / OpenStack — API-creatable, Zen 2; E is
the VPS product — ordered by hand, Zen 4. They are not the same platform.)

### Test 0 — identity

| | Machine A (CX33) | Machine B (CPX32) | Machine C (CCX23) | Machine D (Infomaniak PubCloud) | Machine E (Infomaniak VPS) |
|---|---|---|---|---|---|
| Instance type | Hetzner CX33 | Hetzner CPX32 (user-stated) | Hetzner CCX23 (user-stated) — **dedicated vCPU** | Infomaniak `a4-ram8-disk80-perf1` (dc3-a) | Infomaniak VPS (4 vCPU/4 GB) |
| Model name | AMD EPYC-Rome | AMD EPYC-Genoa (Zen 4 class) | AMD EPYC-Milan (Zen 3 class) | AMD EPYC-Rome (Zen 2 class) | AMD EPYC-Genoa (Zen 4 class) |
| vCPUs | 4 (1s × 4c × 1t) | 4 (1s × 4c × 1t) | 4 (1s × 2c × **2t / SMT on**) | 4 (**2s × 2c × 1t**) | 4 (2s × 2c × 1t) |
| Reported clock | ~2.45 GHz (fixed) | ~2.40 GHz (2396 MHz) | ~2.40 GHz (2399.996 MHz) | **~2.00 GHz** (1996.25 MHz) | ~2.40 GHz (2396.388 MHz) |
| BogoMIPS | 4890.8 | 4792.8 | 4799.99 | **3992.5** | 4792.77 |
| RAM | 8 GB | 8 GB | 16 GB | 8 GB (7.8 GiB) | **4 GB** (3.8 GiB) |
| Disk | 80 GB | 160 GB | 160 GB | 80 GB | 80 GB |
| Price / month (gross) | €10.10 | €42.23 | €102.33 | ~€20.0 (net, ex VAT) | €10.80 |

### Pricing (live from Hetzner Cloud API `/v1/pricing`)

Pulled 2026-06-16 via `GET /v1/pricing`. EUR, EU locations (fsn1 / nbg1 / hel1 —
all priced identically); Singapore is dearer (see note). **All figures below are
gross, incl. 19% VAT** (net shown in parentheses for reference).

| | Machine A (CX33) | Machine B (CPX32) | Machine C (CCX23) | Machine D (Infomaniak PubCloud) | Machine E (Infomaniak VPS) |
|---|---|---|---|---|---|
| Gross / month (incl. VAT) | **€10.10** (net €8.49) | €42.23 (net €35.49) | €102.33 (net €85.99) | **~€20.0 net** (no VAT in quote) | **€10.80** (as ordered) |
| Gross / hour (incl. VAT) | **€0.0162** (net €0.0136) | €0.0677 (net €0.0569) | €0.1640 (net €0.1378) | ~€0.0274 net | ~€0.0148 |
| Included traffic | 22 TB | 22 TB (EU) / 2 TB (sin) | 22 TB (EU) / 2 TB (US+sin) | metered / fair-use | fair-use |
| Price ratio | 1× (baseline) | **4.18× more expensive** | **10.13× more expensive** | ~2.4× net (vs A net €8.49) | ~1.07× (vs A gross) |

#### Machine D — Infomaniak Public Cloud pricing (pulled 2026-06-18)

Infomaniak Public Cloud is pay-as-you-go OpenStack, billed hourly in EUR **ex
VAT** (the others' figures are German gross, incl. 19% VAT — so D's price is not
directly comparable; for the per-euro comparison below the *net* figures are
used for all four). Live per-resource rates from the
[pricing page](https://www.infomaniak.com/en/hosting/public-cloud/prices):

| Component (for `a4-ram8-disk80-perf1`) | Rate | €/hour | €/month (×730h) |
|---|---|---|---|
| Compute — 4 vCPU + 8 GB RAM | €0.0145/h | 0.0145 | 10.59 |
| Block storage — 80 GB, perf1 | €0.00011/GB/h | 0.0088 | 6.42 |
| Public IPv4 (reserved) | €0.00411/h | 0.0041 | 3.00 |
| **Total** | | **0.0274** | **~20.0** |

Compute+storage alone (no public IP) is ~€17.0/mo net. The box's public IPv4
comes from the shared `ext-net1` network and is billed at the reserved-IPv4
rate. Storage tiers: perf1 €0.00011, perf2 €0.00021, perf3 €0.00031 /GB/h.
Note the clock: D runs at **~2.0 GHz vs the Hetzner boxes' ~2.4 GHz** — same
EPYC-Rome (Zen 2) silicon as A but ~18% lower BogoMIPS.

Note: CPX32 in Singapore (sin) is gross €58.30/mo (net €48.99) with only 2 TB
included traffic. A and B are shared-vCPU x86 SKUs despite the performance gap —
CPX just lands on newer/less-contended AMD silicon in this account. **C is a
different product line: CCX = dedicated vCPU** (guaranteed whole physical
threads, not time-shared), which is why it costs ~2.4× the CPX32 and ~10× the
CX33. CCX23 is dearer outside the EU: Ashburn/Hillsboro (US) €104.11/mo gross
and Singapore €129.10/mo gross, both with only 2 TB included traffic.

### Test 1 — steal under full load

| | Machine A (CX33) | Machine B (CPX32) | Machine C (CCX23) | Machine D (Infomaniak PubCloud) | Machine E (Infomaniak VPS) |
|---|---|---|---|---|---|
| `%steal` under 12s full load | **0.00** (every sample) | **0.00** (every sample) | **0.00** (every sample) | **0.04 avg — nonzero** (0.25 in 2/12 samples) | **0.00** (every sample) |
| Aggregate during load | ~99.4% usr, 0% idle | ~99.7% usr, ~0.02% idle | ~99.9% usr, 0% idle (~0.1% sys) | ~99.8% usr, 0% idle (~0.08% sys) | ~99.9% usr, 0% idle (~0.04% sys) |
| Cumulative steal counter moved? | **No** (stayed 0) | **No** (stayed at 89 ticks) | **No** (stayed 0) | **Yes** — steal accrues (cpu0 +1 tick in Test 2) | exposed (58 ticks at boot); ~nil under load |

### Test 2 — single-core jitter (10s, pinned to vCPU0)

| Metric | Machine A (CX33) | Machine B (CPX32) | Machine C (CCX23) | Machine D (Infomaniak PubCloud) | Machine E (Infomaniak VPS) |
|---|---|---|---|---|---|
| Wall-time lost to >200µs stalls | **2.9–4.0%** | **0.00%** (both runs) | **0.00%** (both runs) | **0.60–0.87%** (both runs) | **0.02–0.03%** (both runs) |
| Stalls > 200µs | ~41–45 /s | **0 /s** (zero total) | **0 /s** (zero total) | ~3–9 /s (27 and 87 total) | ~0–1 /s (8 and 5 total) |
| Stalls > 1ms | ~8–12 /s | **0 /s** (zero total) | **0 /s** (zero total) | ~2 /s (18 total each run) | 0–1 total (1 and 0) |
| Worst single stall | **5.7–7.9 ms** | **0.09–0.10 ms** | **0.12–0.14 ms** | **5.02–5.41 ms** | 0.95–1.12 ms |
| Involuntary ctx switches | ~6.5 /s (65 in 10s) | ~4.9 /s (46–52 in 10s) | ~4.4 /s (41–46 in 10s) | ~7–8 /s (70–77 in 10s) | ~5 /s (49–51 in 10s) |
| cpu0 steal ticks delta | **0** | **0** | **0** | **1** (nonzero) | 0–1 |
| Single-core loop rate | 0.46 µs median gap (~2.2M/s inv.) | ~3.6M iters/s (mean gap ~0.27µs) | ~3.55–3.65M iters/s (mean gap ~0.27–0.28µs) | ~2.0–2.4M iters/s (mean gap ~0.41–0.49µs) | **~4.3–4.4M iters/s** (mean gap ~0.23µs) |

(Machine A ranges come from two runs: 12s and 10s. Machine B and C each from two
10s runs. Single-core loop rate: B and C ~3.6M iters/s **measured** (mean gap
~0.27µs). A is not directly measured — only a 0.46µs *median* gap is recorded
(~2.2M iters/s if inverted, and that median excludes stall time so it overstates
A's real rate). So both B and C are ~1.6–1.7× faster per core than A at the same
clock — but mean-vs-median on a crude perf_counter loop, so directional only.
B (Genoa/Zen 4) and C (Milan/Zen 3) are statistically indistinguishable on this
loop despite the one-generation gap.)

---

## Machine A interpretation (carry forward when comparing)

1. **Steal accounting is not exposed on this VM.** `%steal` read 0.00 through a
   full-load run and the steal counter never moved even while we were
   measurably stalling. Conclusion: do **not** trust `%steal`/`vmstat st` here.
2. **Wall-clock jitter proves real descheduling anyway.** A loop that should
   never pause lost ~3–4% of real time, with ~8–12 hiccups/sec over 1ms and
   worst cases of 6–8ms.
3. **It looks like hypervisor vCPU preemption, not guest-local scheduling.**
   Only ~65 involuntary ctx switches in 10s vs ~412 stalls — most stalls have
   no corresponding guest context switch, the signature of the host pausing the
   whole vCPU invisibly to the guest.
4. **Throughput is fine, latency tail is not.** Aggregate cycles are delivered
   (99.4% usr, 0 idle under load); the cost is p99/p99.9 latency. Good batch
   worker, poor low-latency host.

## Comparison — Machine B (CPX32)

- **Identity diff:** Same core count (4 vCPU, 1 socket × 4 cores × 1 thread) and
  near-identical clock (~2.40 GHz on B vs ~2.45 GHz on A, ~2% lower). The
  generational gap is the real difference: B is EPYC **Genoa** (Zen 4) vs A's
  EPYC **Rome** (Zen 2) — two microarchitecture generations newer. BogoMIPS are
  within ~2% (4792.8 vs 4890.8), as expected since they track clock not IPC.
  Both are KVM full-virt guests.

- **Steal accounting:** Identical behavior — **not exposed on either box.**
  `%steal` read 0.00 on every sample on B too, and the cumulative steal counter
  never moved. So the doc's headline caveat holds for B as well: `%steal` /
  `vmstat st` are useless here. The difference is that on B this is honest —
  there genuinely was no descheduling to report (see jitter below) — whereas on
  A the 0 was a lie masking real preemption.

- **Jitter — B wins decisively, by an effectively infinite factor.** A lost
  **2.9–4.0%** of wall time to stalls; B lost **0.00%** — not a single stall
  over 200µs in 20s of probing across two runs. This isn't "a bit better," it's
  a categorical difference: A is being descheduled by the hypervisor, B is not.

- **Tail:** A's worst single stall was **5.7–7.9 ms** with **~8–12 stalls/s
  over 1ms**; B's worst was **~0.10 ms** (100µs) with **zero** stalls over 1ms
  (or even over 200µs). B's tail is ~60–80× tighter at the max and clean of the
  multi-ms spikes entirely. Involuntary ctx switches are comparable and low on
  both (~5–6.5/s), confirming neither is being preempted by its *own* guest
  kernel — the difference is purely host-side.

- **Single-core speed:** clock is the same (~2.40 vs ~2.45 GHz), but per-core
  *performance* is not: B runs the loop at ~3.6M iters/s (mean gap ~0.27µs) vs
  A's ~0.46µs median gap — roughly **1.6–1.7× faster per core at equal clock**,
  the Zen 4 vs Zen 2 IPC gap. (Mixed-metric, crude loop — directional only.)

- **Price / performance:** B costs **4.18× more** (gross €42.23 vs €10.10/mo,
  incl. VAT) for ~1.6× the single-core throughput, so on raw throughput-per-euro
  **A wins by ~2.5×** (~0.218M vs ~0.085M iters/s per €/mo gross). The two SKUs
  are matched on
  vCPU (4) and RAM (8 GB); B additionally gives 2× disk (160 vs 80 GB). What the
  4× premium actually buys is the clean latency tail, not bulk compute.

- **Overall verdict:** **B is the better low-latency host by a wide margin** and
  also edges single-core throughput (~1.6× per core, the Zen 4 IPC + newer
  silicon). A delivers full aggregate throughput (99.4% usr, 0 idle) but pays a
  bad p99/p99.9 latency tail — a fine batch worker, poor for latency-sensitive
  work. **Neither box reports steal**, but only A is *actually* being starved by
  neighbors; B shows no sign of a noisy neighbor at all during this run. If you
  must pick one host for a low-latency service, pick B; A is acceptable only for
  throughput-bound batch jobs that tolerate multi-ms hiccups. **But factor in
  price:** B is 4.18× dearer (gross €42.23 vs €10.10/mo, incl. VAT), so for
  throughput-bound batch work A is ~2.5× better value — B is worth its premium
  only when the p99/p99.9 tail matters.

  Caveat: these are point-in-time snapshots on otherwise-idle VMs. Shared-tenant
  contention is bursty, so B's clean result reflects *this* run, not a guarantee
  it never gets descheduled.

## Comparison — Machine C (CCX23, dedicated vCPU)

- **Identity diff:** C is a Hetzner **CCX23**, the *dedicated-vCPU* line — a
  different product class from A (CX33) and B (CPX32), which are both
  shared-vCPU. Core count matches (4 vCPU), but the topology differs: C presents
  **1 socket × 2 cores × 2 threads (SMT on)**, whereas A and B both presented
  4 cores × 1 thread. Silicon is EPYC **Milan (Zen 3)** — one generation newer
  than A's Rome (Zen 2), one older than B's Genoa (Zen 4). Clock is ~2.40 GHz
  (2399.996 MHz), within ~2% of both peers; BogoMIPS 4799.99 tracks clock as
  expected. RAM is **16 GB** (2× A and B's 8 GB); disk 160 GB (matches B).
  KVM full-virt guest like the others.

- **Steal accounting:** Same as both peers — **not exposed.** `%steal` read
  0.00 on every sample under full load and the cumulative counter never moved.
  So the doc's caveat holds on all three boxes: `%steal` / `vmstat st` are
  useless here. As with B (and unlike A), the 0 is *honest* — there was no
  descheduling to report (see jitter). The reason is structural: C is a
  dedicated-vCPU instance, so there are no neighbors to be starved by.

- **Jitter — C is clean, tied with B.** C lost **0.00%** of wall time to stalls:
  zero stalls over 200µs in 20s of probing across two runs, identical to B and
  the categorical opposite of A's **2.9–4.0%**. Worst single stall was
  ~**0.12–0.14 ms** vs B's ~0.10 ms (effectively a tie; both ~50–65× tighter
  than A's 5.7–7.9 ms) and **zero** stalls over 1ms. Involuntary ctx switches
  were ~4.4/s (41–46 in 10s) — the lowest of the three, confirming the guest
  kernel barely preempts the probe and nothing host-side does either.

- **Single-core speed:** C runs the loop at **~3.55–3.65M iters/s** (mean gap
  ~0.27–0.28µs) — statistically identical to B and ~**1.6–1.7× faster per core**
  than A at the same clock. Notably C (Zen 3) matches B (Zen 4) on this loop
  despite being a generation behind: the integer perf_counter loop doesn't
  exercise the IPC features that separate the two, so it saturates similarly.
  (Crude loop, directional only.)

- **Price / performance — C is the most expensive by far and the worst value
  on raw throughput.** C costs **€102.33/mo gross** (net €85.99), which is
  **10.13× the CX33** and **2.42× the CPX32**, for the *same* ~3.6M iters/s as B.
  Throughput-per-euro: ~**0.035M iters/s per €/mo gross**, vs A's ~0.218M and
  B's ~0.085M — so **A is ~6.2× better value than C** and B is ~2.4× better than
  C on bulk compute. What the CCX premium buys is not speed (B matches it) but a
  *contractual* guarantee: dedicated physical threads, so the clean latency tail
  is structural rather than luck-of-the-draw. C also has 2× the RAM of A/B
  (16 GB), which the per-core compute comparison ignores.

- **Overall verdict:** **C and B are both excellent low-latency hosts** (clean
  tail, ~3.6M iters/s/core); A is the latency laggard (multi-ms hiccups, 3–4%
  lost). The decisive split is *why* B and C are clean: **B got a quiet
  shared-tenant draw this run (not guaranteed); C is dedicated vCPU, so its clean
  tail is structural and should hold under neighbor pressure.** That reliability
  is exactly what C's price premium pays for. Ranking:
  - **Lowest, most predictable latency tail:** **C** (dedicated → guaranteed),
    with B a near-tie *for this run only*.
  - **Best throughput-per-euro:** **A** by a wide margin (~6× C, ~2.5× B) — if
    you can tolerate the multi-ms tail.
  - **Best single-core compute:** **B ≈ C** (tie), both ~1.6× A.
  Pick C when you need a *guaranteed* low-latency tail and can pay ~10× the CX33;
  pick B for the same speed at ~2.4× less when an occasional noisy-neighbor risk
  is acceptable; pick A for throughput-bound batch work where price dominates and
  multi-ms hiccups are fine.

  Caveat: same as above — point-in-time, otherwise-idle VMs. C's dedicated-vCPU
  result should be the *most* repeatable of the three precisely because it isn't
  subject to shared-tenant bursting, but a single run still isn't a guarantee.

## Comparison — Machine D (Infomaniak Public Cloud, OpenStack)

Machine D is a different provider *and* a different hypervisor stack — Hetzner's
in-house KVM vs Infomaniak's OpenStack — so it's the most interesting contrast
in the set. Run date 2026-06-18, flavor `a4-ram8-disk80-perf1`, region dc3-a.

- **Identity diff:** D is **AMD EPYC-Rome (Zen 2)** — the *same microarchitecture
  family as A* (CX33), and two/one generations behind B (Genoa/Zen 4) / C
  (Milan/Zen 3). Topology differs from everyone: **2 sockets × 2 cores × 1
  thread** (A and B were 1×4×1, C was 1×2×2 SMT). The headline hardware
  difference is clock: D is presented at **~2.00 GHz (1996 MHz), ~18% below** the
  Hetzner boxes' ~2.40–2.45 GHz, and BogoMIPS track it (3992.5 vs ~4800–4890).
  RAM 8 GB and disk 80 GB match A. KVM full-virt guest like all of them.

- **Steal accounting — the standout result: D is the only box that reports it.**
  On all three Hetzner VMs `%steal` read exactly 0.00 on every sample and the
  counter never moved. On D, `%steal` showed **0.25 in 2 of 12 load samples
  (avg 0.04)** and the **cpu0 steal counter advanced by 1 tick** during the 10s
  jitter probe. So the doc's central caveat — "don't trust `%steal` here" —
  **does not hold on Infomaniak**: its OpenStack/KVM stack exposes steal honestly,
  even if the magnitude is small. This is a qualitative platform difference, not
  just a number.

- **Jitter — D is descheduled, but middling: worse than B/C, clearly better than
  A.** D lost **0.6–0.9%** of wall time to >200µs stalls (vs A's 2.9–4.0%, and
  B/C's 0.00%). Stall *frequency* is much lower than A (~3–9/s over 200µs vs A's
  ~41–45/s; ~2/s over 1ms vs A's ~8–12/s), but the **worst-case tail is the same
  order as A**: max single stall **5.0–5.4 ms** (A: 5.7–7.9 ms; B/C: ~0.1 ms).
  So D hiccups *less often* than A but *just as hard* when it does — and unlike
  A, part of that lost time shows up in the steal counter. Involuntary ctx
  switches were the highest of the four (~7–8/s), but still far below the stall
  count, so most stalls are host-side vCPU preemption (same signature as A).

- **Single-core speed:** ~2.0–2.4M iters/s (mean gap ~0.41–0.49µs) — **on par
  with A** (~2.2M/s) and ~**1.6× slower than B/C** (~3.6M/s). Notable that D
  matches A despite a ~18% lower nominal clock (same Zen 2 IPC; the loop likely
  sees opportunistic boost not reflected in `/proc/cpuinfo`). Crude loop,
  directional only.

- **Price / performance:** D is billed **ex VAT** (~€20.0/mo net incl. its public
  IPv4, or ~€17.0/mo net without), so it isn't directly comparable to the
  German-gross Hetzner figures. On a consistent **net** basis: A is €8.49/mo,
  D ~€20.0/mo — D is **~2.4× dearer than A** for ~the same single-core
  throughput, i.e. **A is ~2.4× better throughput-per-euro** (~0.26M vs ~0.11M
  iters/s per net €/mo). D still beats B and C on value (B net €35.49, C net
  €85.99 for ~3.6M/s → ~0.10M and ~0.042M per net €), landing between A and B.

- **Overall verdict:** D behaves like a **shared-tenant box of A's generation,
  but a better-behaved one** — same Zen 2 silicon and per-core speed, yet ~4–5×
  fewer stalls and ~4× less wall-time lost than A, with an *honest* steal counter
  to boot. It does not reach B/C's perfectly clean tail (it is still descheduled,
  with occasional ~5 ms spikes), and at ~2.4× A's net price it's worse value for
  pure throughput. Where it wins is **observability and a milder tail than A at a
  fraction of B/C's cost**: if you want steal accounting you can actually trust
  and can tolerate a rare multi-ms hiccup, D is a reasonable middle option.

  Ranking refresh across all four:
  - **Lowest latency tail:** **C** (dedicated, guaranteed) ≈ **B** (clean this
    run) ≫ **D** (mild, ~5 ms spikes, honest steal) ≫ **A** (worst, 3–4% lost).
  - **Best throughput-per-euro:** **A** ≫ **D** ≈ **B** ≫ **C**.
  - **Best single-core compute:** **B ≈ C** (~3.6M/s) ≫ **A ≈ D** (~2.2M/s).
  - **Only box where `%steal` is trustworthy:** **D**.

  Caveat: point-in-time, otherwise-idle VM, single short run, and D was probed
  over its tailnet immediately after provisioning — same bursty-contention
  disclaimer as the others applies.

## Comparison — Machine E (Infomaniak VPS, NOT Public Cloud)

Machine E is the *other* Infomaniak product — the **VPS line, not OpenStack**.
It can't be created via API (ordered by hand in the Manager; only management ops
are scripted), so it sits outside the `cmd/infomaniak/` automation. Benchmarked
directly over SSH (no provisioning), run date 2026-06-18, 4 vCPU / 4 GB / 80 GB,
Ubuntu 26.04, €10.80/mo as ordered.

- **Identity diff — completely different silicon from Infomaniak's own Public
  Cloud (D).** E is **AMD EPYC-Genoa (Zen 4) @ ~2.40 GHz** (BogoMIPS 4792.8) —
  i.e. the *same chip generation and clock as Machine B* (Hetzner CPX32), and a
  full two generations ahead of D's Zen 2 @ 2.0 GHz despite both being
  "Infomaniak." Topology 2s × 2c × 1t. The one downgrade vs the others is RAM:
  **4 GB** (half of A/B/D, a quarter of C) — irrelevant to this CPU/latency suite
  but worth noting for real workloads.

- **Single-core speed — fastest box in the entire set.** E ran the loop at
  **~4.3–4.4M iters/s** (mean gap ~0.23µs), *ahead of* B and C (~3.6M/s) on the
  same-or-newer silicon and ~**2× faster than D and A** (~2.2M/s). Whether E
  genuinely edges B or just caught a quieter moment, it is unambiguously in the
  top tier and laps the Zen 2 boxes. (Crude loop, directional — but the ~2×
  margin over D is far outside noise.)

- **Jitter — near-clean, B/C class, nothing like its Public-Cloud sibling.** E
  lost **0.02–0.03%** of wall time (D lost 0.6–0.9%; A 2.9–4.0%; B/C 0.00%). Just
  **one ~1 ms blip across 20s** of probing (worst 0.95–1.12 ms, 0–1 stalls over
  1 ms total) vs D's ~5 ms spikes at ~2/s. Involuntary ctx switches ~5/s, the low
  end of the set. So E is effectively as quiet as B/C here, a hair behind their
  literal-zero result (the single ~1 ms blip), and a different universe from D.
  Steal is exposed (counter nonzero at boot) but stayed ~nil under load.

- **Price / performance — the value winner, outright.** At **€10.80/mo** for the
  fastest core and a near-clean tail, E delivers ~**0.40M iters/s per €/mo** —
  the best in the set: ~1.8× A's gross value (~0.218M), ~3.6× D's (~0.11M net),
  ~4.7× B's (~0.085M), ~11× C's (~0.035M). It costs about the *same as the
  cheapest Hetzner box (A, €10.10)* but is ~2× faster per core with a far cleaner
  tail. The catch is structural, not performance: it's a **fixed product you
  click to order** (no create API, so no fleet automation), and it shipped with
  only 4 GB RAM at this price.

- **Overall verdict:** **E is the surprise standout.** Infomaniak's VPS gives you
  Zen 4 silicon, top-of-set single-core throughput, a near-dedicated latency tail,
  and the best €/perf of any box here — at the price of the *cheapest* option.
  The trade vs Public Cloud (D) is stark: same vendor, ~2× the per-core speed,
  ~20–40× less jitter, ~half the price — but you give up API provisioning and
  (at this tier) RAM. If the workload fits in 4 GB and you don't need to spin
  boxes up/down programmatically, E beats everything else on this page.

  Ranking refresh across all **five**:
  - **Best single-core compute:** **E** (~4.35M/s) > **B ≈ C** (~3.6M/s) ≫
    **A ≈ D** (~2.2M/s).
  - **Lowest latency tail:** **B ≈ C** (literal 0) ≈ **E** (one ~1 ms blip) ≫
    **D** (~5 ms spikes, honest steal) ≫ **A** (3–4% lost).
  - **Best throughput-per-euro:** **E** (~0.40M) ≫ **A** (~0.218M gross) ≫ **D ≈
    B** (~0.11M / ~0.085M) ≫ **C** (~0.035M).
  - **Best for fleet automation:** **A/B/C** (Hetzner API) ≈ **D** (OpenStack
    API) ≫ **E** (manual order only).

  Caveat: same as all the above — point-in-time, otherwise-idle VM, single short
  run. E in particular got only a 20s jitter probe and may have caught a quiet
  window; its 4 GB RAM also makes it not a like-for-like swap for the 8–16 GB
  boxes on memory-bound work.

---

## How to run this on another machine

You are Claude running on a **new machine**. Run every command in the
"Procedure" section below, in order, then **add the next free Machine column**
(the Results section above already has A–E, so add **Machine F**) to each results
table at the top, and add a matching **`## Comparison — Machine F`** subsection up
in the Results area: for each metric, state which machine is better and by how
much, and call out anything qualitatively different (e.g. steal accounting
working on one box but not the other). Keep all existing machines' numbers
exactly as recorded — they are the baseline.

Notes:
- No compiler is assumed; everything runs via `python3`, `mpstat`, and
  `/proc/stat`. If `mpstat` is missing: `apt-get install -y sysstat`.
- Record the machine identity first — a fair comparison needs to know the core
  count, model, and clock of each box.
- Run on an otherwise-idle VM (no other heavy processes), same as Machine A.

---

## Machine A — baseline (the machine that authored this doc)

User-stated instance type: **Hetzner CX33**.
Detected: **AMD EPYC-Rome** (Zen 2 class), **4 vCPU** (1 socket × 4 cores ×
1 thread), reported clock **~2.45 GHz** (fixed, no turbo range exposed), VM /
hypervisor-presented CPU model. Date of run: 2026-06-16.

---

## Procedure

### Test 0 — machine identity

```bash
echo "=== CPU ==="; lscpu | grep -E "Model name|Vendor|^CPU\(s\)|Socket|Thread|Core\(s\) per|MHz|BogoMIPS|Hypervisor|Virtualization"
echo "=== model name ==="; grep -m1 "model name" /proc/cpuinfo
echo "=== reported clock ==="; grep -m1 -i mhz /proc/cpuinfo
echo "=== uptime/load ==="; cat /proc/loadavg; uptime
```

### Test 1 — steal time under full load

Loads every vCPU to 100% for ~12s and samples per-second `%steal` with mpstat.
`%steal` = time the vCPU was runnable but the hypervisor ran someone else.
Set the loop count `1 2 3 4` to match the number of vCPUs on the box.

```bash
# adjust the seq range to the vCPU count of THIS machine
NPROC=$(nproc); for i in $(seq 1 "$NPROC"); do timeout 16 bash -c 'while :; do :; done' & done
sleep 1
echo "=== mpstat 1s x12, all CPUs busy (watch the %steal column) ==="
mpstat 1 12
wait 2>/dev/null
echo "=== cumulative steal field from /proc/stat (8th number on the 'cpu' line) ==="
grep "^cpu " /proc/stat
```

### Test 2 — single-core wall-clock jitter probe + steal disambiguation

Pins to vCPU0, spins a tight timestamp loop for 10s, and records:
- distribution of inter-iteration gaps (a gap >> median = we got descheduled),
- **involuntary context switches** (guest kernel preempting our process),
- **per-CPU steal ticks delta**.

If stall events vastly outnumber involuntary ctx switches AND steal stays 0,
the lost wall-clock time is hypervisor vCPU preemption that the steal counter
is not reporting.

```bash
python3 - <<'EOF'
import time, os, resource
os.sched_setaffinity(0, {0})  # pin to vCPU0

def cpu0_steal():
    with open('/proc/stat') as f:
        for ln in f:
            if ln.startswith('cpu0 '):
                return int(ln.split()[8])  # steal field, USER_HZ ticks (10ms)
    return None

r0 = resource.getrusage(resource.RUSAGE_SELF)
s0 = cpu0_steal()
dur = 10.0
prev = time.perf_counter_ns(); end = time.perf_counter() + dur
n = big = huge = 0; lost = 0; mx = 0
while time.perf_counter() < end:
    now = time.perf_counter_ns(); d = now - prev; prev = now; n += 1
    if d > 200_000:  big += 1; lost += d
    if d > 1_000_000: huge += 1
    if d > mx: mx = d
r1 = resource.getrusage(resource.RUSAGE_SELF)
s1 = cpu0_steal()
print(f"samples={n} dur={dur}s")
print(f"involuntary ctx switches (kernel preempted us): {r1.ru_nivcsw - r0.ru_nivcsw}")
print(f"voluntary   ctx switches:                       {r1.ru_nvcsw  - r0.ru_nvcsw}")
print(f"cpu0 steal ticks delta (each tick = 10ms):      {s1 - s0}")
print(f"stalls>200us={big} (~{big/dur:.0f}/s)  stalls>1ms={huge} (~{huge/dur:.0f}/s)  "
      f"max={mx/1e6:.2f}ms  wall-time lost to >200us stalls={lost/1e6:.0f}ms ({100*lost/1e9/dur:.2f}%)")
EOF
```
