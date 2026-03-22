# Contributing to Dev Center

Thanks for your interest in contributing. This document explains how to get involved.

## Ways to contribute

- **Bug reports and feature ideas** — Open an issue describing the problem or suggestion.
- **Documentation** — Fix typos, improve clarity, or add guides in `docs/modules/`.
- **Code** — Fix bugs or implement features in the app (under `/app`) or tooling.
- **Reviews and feedback** — Comment on issues and pull requests.

## Before you start

- Check existing [issues](https://github.com/dev-centr/devcentr/issues) and [pull requests](https://github.com/dev-centr/devcentr/pull-requests) to avoid duplicates.
- For larger changes, open an issue first to discuss approach.

## Development setup

- **Repo:** Clone from `https://github.com/dev-centr/devcentr` (or your fork). Check the docs in `docs/modules/` for workspace and layout conventions.
- **App:** Application code lives under `/app`. Use the project’s preferred build/run instructions for your platform (Windows, macOS, Linux+GNU).
- **Docs:** Documentation is in `docs/modules/` and built with [Antora](https://docs.antora.org/). Use AsciiDoc (`.adoc`). The published site is at <https://devcentr.org> (docs at <https://devcentr.org/docs>).
- **unit-threaded override:** To silence DUB sub-package warnings (until upstream merges the fix), register our patched fork locally:
  `dub add-local path/to/unit-threaded 0.7.55`
  where `path/to/unit-threaded` is a clone of <https://github.com/dlang-supplemental/unit-threaded>. See xref:ROOT:dub-local-remote-paths.adoc[DUB Local vs Remote Paths] for details.

## Submitting changes

1. **Branch** — Create a branch from `main` (e.g. `fix/short-description` or `feature/short-description`).
2. **Commit** — Use clear, conventional-style messages (e.g. `fix: correct link in workspace docs`, `docs: add CONTRIBUTING`).
3. **Push** — Push your branch to your fork.
4. **Pull request** — Open a PR against `dev-centr/dev-center` `main`. Describe what changed and why; reference any related issues.

The maintainers may ask for edits. Once approved, your PR will be merged. Tagged releases follow the project’s [Git release workflow](https://docs.devcentr.org/general-knowledge/latest/how-to/git-release-workflow.html).

## License and branding

By contributing, you agree that your contributions will be licensed under the same terms as the project. See [LICENSE](LICENSE) in the repo root. The license keeps most of the project open while reserving **branding** (names, logos, trade dress) and prohibiting certain abusive distributions (e.g. duplicate or ad-stuffed app-store forks). Do not use Dev Center branding to imply official endorsement without permission.

## Questions

- Open a [discussion](https://github.com/dev-centr/devcentr/discussions) or an issue.
- For funding and sponsorship, see the [Sponsor](https://github.com/sponsors/dev-centr) button and [.github/FUNDING.yml](.github/FUNDING.yml).

