# Terms

This document defines the core path and workflow terms used by Scriptorium.

## Project Repository Root

The original repository root that the engineer runs `scriptorium` against.

This path is used for:

- Project source context.
- Project-level instructions such as `AGENTS.md`.
- The main `master` branch checkout.

This path is not the same as the active working directory for Architect, Manager, or Coding agent runs.

## Plan Branch

The `scriptorium/plan` Git branch that stores planning state as files and commits.

This branch contains:

- `spec.md`
- `areas/`
- `tickets/`
- `decisions/`
- `queue/merge/`

## Plan Worktree

A temporary or managed checkout of the `scriptorium/plan` branch.

Architect and Manager runs execute in the plan worktree. Planning files such as `spec.md`, `areas/`, and `tickets/` are read and written here.

## Ticket Worktree

A managed checkout for one ticket branch such as `scriptorium/ticket-0001`.

The Coding agent executes in the ticket worktree. This is the active repository checkout for code edits, builds, tests, and commits during ticket implementation.

## Working Directory

The current directory an agent process is running in.

Depending on the role:

- Architect: the plan worktree.
- Manager: the plan worktree.
- Coding agent: the ticket worktree.

Prompts should tell the agent explicitly what the working directory is for that role.

## Architect

The planning role that reads `spec.md` and writes `areas/*.md` in the plan worktree.

## Manager

The planning role that reads area documents and writes `tickets/open/*.md` in the plan worktree.

## Coding Agent

The implementation role that reads one assigned ticket and edits code in the ticket worktree.

When work is complete, the Coding agent must call `submit_pr`.

## Merge Queue

The queue that serializes ticket integration back to `master`.

It merges `master` into the ticket branch, runs required quality gates, and either:

- moves the ticket to `done/` and fast-forwards `master`, or
- reopens the ticket with failure notes.

## Master Health

The state of required quality checks on `master`.

If `master` is red, orchestration should halt rather than assign or merge more work.

## submit_pr

The MCP tool the Coding agent calls to signal that a ticket is ready for merge-queue processing.

Scriptorium should rely on this tool call as the completion signal rather than stdout text matching.
