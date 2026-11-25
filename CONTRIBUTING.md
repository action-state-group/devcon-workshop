# Contributing

## Local checks before you push

Before every push: `scripts/check.sh` (under a minute on an Apple-silicon Mac; needs shellcheck, python3 and bash). It is the unit tier, the `unit` job of `.github/workflows/image.yml`, which runs the same command.

Before pushing any change to an input of the image (every path in the `push: paths:` list of `.github/workflows/image.yml`: the `Dockerfile`, `.dockerignore`, `versions.lock`, `package.json`, `package-lock.json`, `README.md`, `agent/`, `bin/`, `build/`, `demos/`, `examples/`, `lib/`, `patches/`, `scripts/`, `tests/`, the workflow and its reporter script), `scripts/check.sh --full` is mandatory. It runs the unit tier, builds the image for your machine's native architecture (arm64 on an Apple-silicon Mac) and runs the same image tests as CI's build job (`scripts/check.sh --image-tests`): the size check, the secret scan, the in-image tests, the console relay and S08. It takes about 65 minutes on an Apple-silicon Mac (measured with an empty build cache in a Docker VM with 4 CPUs and 8 GB). It needs Docker with buildx, curl, network access for the build's downloads, and Docker disk for a 3+ GB image and its build cache. It removes the images, containers and volumes it created; the build cache stays (`docker builder prune` reclaims it).

`--full` does not build amd64. amd64 is built and tested only by the run on main, which builds both architectures and then still parks at the `image-release` approval before anything is published.

Pull requests run only the fast set (`unit`, and `studio` when the Studio layer's inputs change). The image builds and their tests run on push to main when an input of the image changed, and on a manual run; there is no nightly, because a non-PR run on main asks to publish.
