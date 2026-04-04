# AGENTS.md

This file gives AI coding agents the minimum project context needed to work in
this repository safely.

## Scope

This repository contains a MicroOCPP simulator setup with:

- Docker-based local runs
- generated multi-container simulator configs
- depot CSV to simulator generation
- CitrineOS integration helpers

## Rules

1. Prefer editing the generator scripts instead of hand-editing generated
   output files.
2. Keep the shared Docker network name aligned across scripts, configs, and
   checked-in compose examples. The current network is `fnx-platform-net`.
3. Do not edit vendored code under `lib/` unless the task explicitly requires
   it.
4. Keep shell output concise and readable. Avoid decorative emoji in scripts.
5. Update docs when changing workflow, file names, or runtime assumptions.

## Important Files

- `generate-depot.sh`: depot CSV workflow
- `generate-simulators.sh`: multi-container generator
- `start-simulators.sh`: generate and start workflow
- `cleanup-simulators.sh`: cleanup helper
- `simulator-config.yml`: main generator config
- `docker-compose.yml`: fixed local setup
- `README.md`: user-facing setup and usage

## Validation

- Use `bash -n` for edited shell scripts.
- Check for stale network references with targeted `rg` searches before and
  after network-related changes.
- If you change generated templates or generator output, review the checked-in
  generated YAML files too.
