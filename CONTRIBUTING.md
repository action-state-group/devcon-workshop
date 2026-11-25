# Contributing

## Local checks before you push

Before every push: `scripts/check.sh` (under a minute on an Apple-silicon Mac; needs shellcheck, python3 and bash). It is the `unit` job of `.github/workflows/image.yml`, which runs the same command.

Before pushing a change to the `Dockerfile`, `.dockerignore`, `build/`, `versions.lock`, `package.json`, `package-lock.json` or anything else the Dockerfile copies (`bin/`, `lib/`, `agent/`, `demos/`, `examples/`, `patches/`, `tests/`, `README.md`), also `scripts/check.sh --full`. It needs Docker with buildx, curl, network access for the build's downloads and enough Docker disk for a 3+ GB image and its build cache. It builds the image for your machine's native architecture only (arm64 on an Apple-silicon Mac; it does not build amd64), then runs the size check, the secret scan and the in-image tests the image build job runs. It removes the image and containers it created. Its time on a Mac has not been measured yet; one architecture's build and tests take about 80 to 110 minutes on a CI runner.

Pull requests run only the fast set (`unit`, and `studio` when the Studio layer's inputs change). The amd64 and arm64 image builds and their in-image tests run on push to main when an input of the image changed, and on a manual run; there is no nightly, because a non-PR run on main asks to publish.
