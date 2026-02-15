## Test strategy rubric (for `test_strategy_decider`)

Choose **exactly one** strategy: `fuzz` (Hypothesis/PBT), `assertion` (deterministic regression), or `simple_test` (minimal repro).

### 1) Choose `fuzz` only when you have a general oracle

Use `fuzz` when you can state a **general, automation-friendly oracle/invariant** that does **not** depend on hidden tests or deep domain knowledge.

Good fits:
- **Round-trip / reversibility**: `encode→decode`, `dump→load`, `parse→format→parse`, `serialize→deserialize` preserve semantics.
- **Parser/IO robustness**: “never crash” for malformed inputs; whitespace/encoding variations; NUL bytes; extreme sizes.
- **Algebraic/structural invariants**: idempotence, commutativity/associativity, monotonicity, shape/length/order constraints.
- **Differential testing**: compare against a trusted reference implementation.

Bad fits (prefer `assertion`/`simple_test`):
- Expected behavior is **highly test-specific** (exact error message formatting, internal details).
- Correctness requires **framework/integration semantics** you can’t reliably assert without the official suite.
- The failure is mostly **environment/integration** (dependencies, filesystem layout, network, flaky timing).

When you pick `fuzz`, your output must include:
- A concrete **oracle** (1–2 sentences).
- Input constraints + edge-case emphasis.
- A plan to **seed** at least one deterministic regression example if fuzz finds a falsifying input.

### 2) Choose `assertion` for deterministic regression tests

Use `assertion` when there is a **specific failing input** and the expected behavior is stable and can be asserted explicitly:
- Return values, state changes
- Raised exception type (and message only if the message is part of the public contract)
- Warning class (and message only if required)

Prefer narrow, stable assertions; avoid brittle string matching unless necessary.

### 3) Choose `simple_test` for minimal reproduction (1–5 cases)

Use `simple_test` when:
- The oracle is unclear/ambiguous/expensive right now, or
- The bug is integration-heavy and you first need a tiny repro to lock down the symptom.

Goal: a **small repro** that fails pre-fix and passes post-fix; later you can promote to `assertion` or `fuzz`.

### SWE-bench safety note (important)

In SWE-bench, the final patch is evaluated by running the official test suite. Avoid committing scratch test files.
- Put any temporary repro/wrapper files under **ignored directories** (recommended: `.openhands/` or `.fuzz_hypo/`) or run ad-hoc snippets via the terminal without creating tracked files.

### Output quality requirements (what your JSON must contain)

- `rationale`: 2–6 sentences, explicitly mention oracle availability and why this choice is lowest-cost/highest-signal.
- `recommended_next_steps`: 3–8 bullet strings, each starts with a verb and mentions concrete artifacts (file path, test name pattern, inputs, oracle/assertions, fixtures).
- `suggested_oracle`: non-null only if decision is `fuzz`.
