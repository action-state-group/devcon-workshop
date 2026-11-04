# Terms Pack Studio layer

An internal build on top of the workshop image, run from a laptop. It adds what the first Terms Pack
Studio demo needs and changes nothing in the published image, its `latest` tag or the USB files.

What it adds:

- `studio.yaml`, the sticker trader recipe plus a Studio section: goose may read the
  `terms-pack-author` skill and run `terms <verb>`; everything `terms` writes goes under `~/studio`. It is generated
  from `trader.yaml` by `studio/build-recipe.py` (CI fails if the committed file is stale), so the
  trading protocol exists once.
- `terms <verb>` (lint, test, run, compare, publish, ...), the evidencebook-skills scripts at the commit
  pinned in `versions.lock`, run with PyYAML from a venv under `/opt/devcon8/studio`, and the checkout sits under capsulectl's trusted plugin root (`/usr/local/lib/capsulectl/plugins/terms-pack-studio`).
- The `terms-pack-author` skill, from the same commit.
- `devcon8-studio`, the same as `devcon8 trade` with the Studio recipe.

## Build

The base is an immutable digest of the workshop image, pinned in `versions.lock`; `latest` is refused.
The build is local and pushes nothing.

    studio/build.sh                       # uses STUDIO_BASE from versions.lock
    studio/build.sh --base <image@sha256:...> mytag

## Run

    studio/run.sh                         # a second run resumes the stopped container
    docker start -ai devcon8-studio       # the same, by hand

Inside the container: `devcon8 brain claude` (a Claude subscription login; no API key), `devcon8 nanda
<your email>`, then `devcon8-studio`. Rehearsal pages and Result JSON land in `~/devcon8-studio` on
your laptop (mounted at `~/studio`), so you open them from the browser.

## Tests

- `python3 -I tests/test_build_recipe.py` and `python3 studio/build-recipe.py --check`
- `tests/studio-recipe.sh` renders `studio.yaml` with goose in both payment modes (CI runs it in the image)
- `tests/studio-layer.sh` checks the layer's contents (inside the built layer)
- `tests/studio-e2e.sh` runs demo steps 1-4 without a model over a replay of ten sticker trades (inside the built layer; CI runs it)
