# 0075 — Add `scriptorium audit` CLI entry point

**Area:** cli-init

## Problem

The spec (section 19) defines `scriptorium audit` as an on-demand CLI command that runs the audit agent. The CLI dispatcher in `src/scriptorium.nim` does not have an `audit` case, and the `Usage` string does not mention it.

## Task

1. Add `audit` to the `Usage` constant in `src/scriptorium.nim`:
