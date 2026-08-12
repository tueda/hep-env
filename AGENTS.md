# AGENTS.md

## Project

hep-env builds and publishes a multi-architecture container image for a
high-energy physics toolchain centered on MadGraph5_aMC@NLO and its HEPTools
ecosystem. The image supports amd64 and arm64, is published to GHCR, and can
be run with Docker or Apptainer.

## Critical Rules

- Preserve the container storage boundaries:
  - Keep installed tools under `/opt`.
  - Keep `/work` as the default user workspace.
  - Keep image-managed mutable state under `/data`.
  - Route additional image-managed runtime writes to `/data`, not `/opt`.
  - Preserve the existing mappings and symbolic links.
  - Keep `/work` and `/data` usable whether they are bind-mounted or kept
    inside the container.
- Preserve existing cryptographic checksum verification. For new artifacts
  downloaded directly by the `Dockerfile` or scripts, pin the source and
  verify its checksum. Update a pinned source and its checksum together. When
  changing an existing unverified direct download, add the same protection if
  its content can be pinned.
- Keep each upstream patch series under `patches/<upstream>/<purpose>/` with
  numbered filenames in application order. Preserve the intended target
  directory and patch level, and verify the series against the source fetched
  by the `Dockerfile` after an upstream update. Do not assume that applying a
  patch preserves Git file-mode metadata; verify permissions required by the
  build separately.
- When a `Dockerfile` setting depends on a patch in this repository, update or
  remove the setting and the patch together.
- Support both amd64 and arm64. Do not claim cross-architecture compatibility
  based on a successful build on only one architecture.

## Development Workflow

### Commands and Verification

- Install the local hooks with `pre-commit install`.
- During development, run focused checks with
  `pre-commit run <hook-id> --files <path>...`. Before finishing, run
  `pre-commit run --all-files`. Inspect the diff after running hooks because
  some of them modify files.
- For changes to the `Dockerfile`, patch series, or installation scripts used
  by the image build, run `make update-docker`. This build can be slow and
  requires Docker and network access. If the command cannot be run, report why
  and state exactly what remains unverified.
- When changing the base image or the Python/MG5 combination, re-evaluate and
  update the compatibility note at the top of the `Dockerfile`. When the note
  identifies a feature-specific risk, run an end-to-end test of the affected
  feature; starting the tool or printing its version is not sufficient.
- Run `make update-apptainer` after changing Docker-to-SIF conversion, the
  Docker image ID stamp check, Apptainer data initialization, bind mounts, or
  run behavior. Run a smoke test that exercises the affected path. If
  Apptainer is unavailable, report that fact and the remaining uncertainty.
- Use `make run-docker` or `make run-apptainer` for manual smoke tests that need
  an interactive shell or mount-behavior checks.
- For image-affecting changes, report the platforms on which checks completed
  and the smoke tests that ran, whether locally or in CI. Report required
  checks that have not run as pending CI or otherwise unverified. Do not claim
  cross-architecture verification until the relevant jobs pass for both
  supported architectures.

### Version Control and External Actions

- Inspect the worktree before editing and before finishing.
- Limit working-tree changes to those required by the request. Preserve all
  unrelated files and changes. Do not use destructive Git operations without
  explicit authorization.
- Unless explicitly requested, do not modify other local repository state or
  perform state-changing operations on the remote repository or related
  services. Examples include staging, committing, pushing, changing pull
  requests, manually managing workflow runs, and modifying GHCR images or
  tags.
- Authorization for one operation does not authorize another. For example, a
  request to commit does not authorize a push.
- Never commit secrets, credentials, private keys, access tokens, or private
  user data.
- When a requested and verified change forms a sensible commit, report that it
  is ready. List the exact paths that belong in the commit, suggest the safest
  staging command, and provide a concrete commit message. Do not stage or
  commit the change unless explicitly requested.
- Prefer `git add -- <paths>` with explicit paths. Recommend `git add -u` only
  after verifying that every tracked modification and deletion belongs in the
  commit and that no required file is untracked.
- Whether suggesting a commit message or creating a commit, use a Conventional
  Commit type allowed by `.gitlint`. Keep the subject and each body line within
  80 characters.
- Before changing a remote ref, inspect the workflows triggered by that
  operation and explain their automated external effects. Currently, pushing
  a branch or tag publishes an image to GHCR; pushing a tag matching `^v[0-9]`
  also updates `latest`; and deleting a remote branch deletes its
  branch-derived GHCR tag. If the request does not clearly authorize these
  effects, ask for confirmation before changing the ref.

## Repository Guide

### Layout and Architecture

- `Dockerfile` is the primary build recipe for the image, including its
  installed environment and runtime paths. It combines upstream sources,
  system packages, and the patch series in `patches/`.
- `patches/` contains changes applied to unpacked upstream projects during the
  image build. `scripts/apply-patches.sh` applies each series in filename order.
- `scripts/` also contains build-time fixes and the environment-version report
  used by CI.
- `Makefile` is the entry point for local Docker and Apptainer image updates,
  data setup, and interactive runs.
- `.github/workflows/publish.yml` builds the two platform images and publishes
  their manifest. The other workflows lint the repository or clean GHCR tags
  and images.
- `.data/` contains local Docker and Apptainer data, image files, and stamps. It
  is generated state and must not be committed.

### Project Conventions

- Treat `.pre-commit-config.yaml` and the tool-specific configuration files as
  the source of truth for formatting, linting, and type checking. Ruff targets
  Python 3.10, and ty provides Python type checking. Shell scripts use Bash
  and retain `set -euo pipefail`.
- Treat `.patch` files as patches to upstream sources. Do not run source
  formatters on them or rewrite their context merely to satisfy local style.
- Follow the line length set by the applicable formatter, linter, or
  `.editorconfig`. Where none is configured, keep lines at 80 columns when
  practical, including in `AGENTS.md`. Longer lines are acceptable when
  wrapping would damage a URL, command, generated content, patch, or other
  structured text. Do not reflow existing lines outside the scope of the
  current change solely to enforce this convention.

## Working Principles

### 1. Think Before Coding

- Inspect the relevant code, tests, configuration, and documentation before
  changing behavior. Separate repository facts from assumptions, and never
  invent files, APIs, requirements, behavior, or test results.
- Resolve ambiguity by inspecting the repository first. Ask only when different
  answers would materially change behavior, interfaces, data, safety, or
  scope. Otherwise use the smallest reversible assumption and state it.
- Treat requests to explain, review, diagnose, or plan as read-only unless the
  request also asks for changes. For non-trivial changes, define the intended
  result and its verification before editing.

### 2. Simplicity First

- Implement the smallest clear solution that fully solves the task. Do not add
  speculative features, options, dependencies, or extension points.
- Reuse or add an abstraction only when its meaning fits the task and it
  protects a real boundary, invariant, or testability requirement.
- Prefer clear code. Comment only on durable, non-obvious reasons or constraints
  that belong next to the code. Keep change history in Git, pull requests,
  changelogs, or design records.

### 3. Surgical Changes

- Every changed line must follow from the task or a necessary consequence of
  it. Required formatting, regeneration, manifest, and lockfile updates are
  necessary consequences, not unrelated changes.
- Avoid unrelated refactoring, renaming, formatting, dependency updates,
  comment rewriting, and cleanup. Preserve behavior, APIs, formats, ordering,
  and compatibility unless the task explicitly changes them.
- Preserve unrelated worktree changes. Do not weaken tests, errors, tolerances,
  or baselines merely to make checks pass.

### 4. Goal-Driven Execution

- Translate the request into concrete acceptance criteria. For bug fixes,
  reproduce the failure and add a focused regression test when practical.
- Run the narrowest relevant checks first, then every broader check required
  for the affected area. A check is evidence only when it has completed and
  its result has been inspected.
- Inspect the final diff. Report what changed, which checks ran, their results,
  and anything that remains unverified.

### 5. Evidence and Correctness

- Distinguish observations, assumptions, inferences, and hypotheses.
- For correctness-critical work, check preconditions, hidden assumptions, edge
  cases, invalid states, and realistic failure modes.
- Tests and examples support only the cases they cover. State unresolved
  uncertainty instead of claiming broader correctness without evidence.

## Definition of Done

A task is complete only when all applicable conditions hold:

- The requested result is present, with no behavior or scope beyond the
  request.
- Every check required by `Commands and Verification` for the affected area
  passes, or each missing check is reported with its reason and remaining
  uncertainty.
- The final diff and worktree state have been reviewed.
- Temporary files, debug output, and accidental formatting introduced by the
  current task are absent, and no secrets are exposed.
- Required documentation, generated files, manifests, lockfiles, schemas,
  snapshots, migrations, and baselines match the change.
- The final report states what changed, which checks ran, their results, and
  any remaining limits or risks.
