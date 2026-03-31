# 0079 Add deprecation warning for --init flag

**Area:** cli-init

## Description

Per V11 §37, `scriptorium init [path]` is the canonical subcommand. The `--init` flag is kept as a deprecated alias. When `--init` is used, print a deprecation warning before running init:

```
Warning: --init is deprecated, use `scriptorium init` instead.
```

## Tasks

1. In `src/scriptorium.nim`, in the `--init` case branch (around line 179), add a stderr warning before calling `cmdInit`.
2. Update `tests/integration_cli.nim` test "--init flag works as alias for init subcommand" to also check for the deprecation warning in the output.
3. Run `make test` to confirm.
