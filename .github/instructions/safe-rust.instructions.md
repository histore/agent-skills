---
applyTo: "**/*.rs"
description: "Safe Rust Invariant: zero unsafe blocks, functions, traits, extern blocks, or Rust 2024 #[unsafe(...)] attributes."
---

# Safe Rust Engineering Guardrails

- **Zero `unsafe` Invariant**: `unsafe` blocks, `unsafe fn`, `unsafe trait`, `unsafe impl`, `unsafe extern`, and Rust 2024 `#[unsafe(...)]` attributes are strictly forbidden in production and test code.
- Prefer safe abstractions, checked arithmetic, iterators, slices, and idiomatic ownership/borrowing patterns.
- Validate changes via targeted `cargo test -q <test_name>` and Stage-1 `./.agents/scripts/run-fast-gate.ps1` (`.sh`); defer `cargo fmt` to `prepare-commit`.
