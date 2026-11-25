# Contributing

## Local check before you push

Before every push: `scripts/check.sh`. It always runs the unit tier, the same command as the `unit` job of `.github/workflows/image.yml` (`scripts/check.sh --unit`; under a minute on an Apple-silicon Mac; needs bash, python3 and shellcheck).

It also runs the image tier, by itself, unless every path your branch changes is on its fixed list of paths no image build reads: `WORKSHOP.md`, `CONTRIBUTING.md`, `docs/`, `studio/`, and workflows other than `image.yml`. Anything else counts as an input of the image, so an unlisted path costs a build, never a skipped one. It compares your branch with its merge base on `origin/main` (both sides of a rename, and deletions) and includes uncommitted and untracked files, so fetch `origin` first. If you add a path no image build reads, you may add it to that list in `scripts/check.sh`; `scripts/check.sh --self-test` checks the rule. The image tier builds the arm64 image and runs the same image tests as CI's build job (`scripts/check.sh --image-tests`): the size check, the secret scan, the in-image tests, the console relay and S08. It took about 65 minutes on an Apple-silicon Mac with an empty build cache, in a Docker VM with 4 CPUs and 8 GB. It needs Docker with buildx, curl, network access for the build's downloads, and Docker disk for the image and its build cache (about 30 GB). It removes the images, containers and volumes it created; the build cache stays (`docker builder prune` reclaims it). `scripts/check.sh --full` runs the image tier whatever changed.

No local check builds amd64. The amd64 image and its in-image tests are built and tested only by the run on main, which builds both architectures before it parks at the `image-release` approval, so nothing untested is published; a red main run opens or comments on a `ci-red` issue.

Pull requests run only the fast set (`unit`, and `studio` when the Studio layer's inputs change). The image builds and their tests run on push to main when an input of the image changed, and on a manual run; there is no nightly, because a non-PR run on main asks to publish.
