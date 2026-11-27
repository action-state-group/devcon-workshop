# Contributing

## Local check before you push

Before every push: `scripts/check.sh`. It runs everything the pull request jobs run for your branch, with the same commands, so a branch that passes it passes them.

- **Unit tier, always:** `scripts/check.sh --unit`, the `unit` job of `.github/workflows/image.yml` on every pull request. actionlint on every workflow (with shellcheck on their `run:` steps), shellcheck on the scripts, and the python and bash unit tests. About 25 seconds on an Apple-silicon Mac. Needs bash, curl, python3 and shellcheck; the first run downloads actionlint (pinned version and sha256) into `~/.cache/devcon-workshop/`.
- **Studio tiers, when your branch changes a path that starts `.github/workflows/studio.yml`:** `scripts/check.sh --studio-unit` and `--studio-layer`, its `unit` and `layer` jobs. They need Docker; the first run pulls the pinned base image named in `studio/versions.lock`. The list is `studio_path` in `scripts/check.sh`, kept in step with the workflow's `paths:`; `scripts/check.sh --self-test` checks the rule.

Changed paths are your branch's diff from its merge base on `origin/main` (both sides of a rename, and deletions) plus uncommitted and untracked files, so fetch `origin` first.

## What runs after a merge

These take longer than a pull request job may (10 minutes), so they run on `main` after the merge, and a red run opens or comments on a `ci-red` issue the same day:

- **The image** (`image.yml`, on a push that changes an input of the image, or a manual run): the amd64 and arm64 builds, then on each the size check, the secret scan, the in-image tests, the console relay and S08 (`scripts/check.sh --image-tests`). Its `publish` job then waits for the `image-release` approval, so nothing untested is published. About 15 to 25 minutes with a warm build cache; a bump of a Rust source pin in `versions.lock` recompiles that stage (up to about an hour).
- **The mesh-llm lab release build** (`mesh-llm-lab-release.yml`, on a push that changes it): all three native targets, uploading nothing. Its pull request gets actionlint from the unit tier.

To run the image tier yourself before a push anyway: `scripts/check.sh --full` (every tier, plus the arm64 image build and `--image-tests`). It needs Docker with buildx and about 30 GB of Docker disk, and takes most of an hour on an empty build cache. No local check builds amd64. The check removes the images, containers and volumes it created; the build cache stays (`docker builder prune` reclaims it).

There is no nightly, because a non-PR run of `image.yml` on main asks to publish.
