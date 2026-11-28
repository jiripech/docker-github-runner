# CHANGELOG

## v1.3.1

- **Fixed** Dockerfile: added missing `COPY lib/ /lib/` to include modular entrypoint scripts
  (they were left out of the image in v1.3.0, making the container fail to start)

## v1.3.0

- **Refactored** `entrypoint.sh` into modular scripts under `docker/lib/`:
  - `validate.sh` - Environment validation and defaults
  - `ssh.sh` - SSH daemon startup
  - `unregister.sh` - UNREGISTER_TOKENS/RUNNERS logic
  - `urls.sh` - Parse GITHUB_URL into array
  - `runner.sh` - Per-repo runner setup and start
  - `wait.sh` - Summary and wait for runner PIDs with exit codes
- **Fixed** runner isolation: each runner now gets its own copied installation
  (via `rsync`) instead of symlinks, fixing "already configured" errors
- **Added** proper exit code capture for background runner processes

## v1.2.8

- **Fixed** typo in runner configuration command

## v1.2.7

- **Updated** timeout error code handling for registration token generation

## v1.2.6

- **Switched** `gh api` call to `curl` for better transparency while generating
  registration tokens
- **Simplified** directory structure in **/data** to remove '$REPO_NAME'
  duplications

## v1.2.5

- **Added** persistent mount folder to presere per runner **_diag** data and configurations

## v1.2.4

- **Added** chromium deps

## v1.2.3

- **Fixed** previously introduced auth issues

## v1.2.2

- **Added** '--install-suggests' to apt-get calls to make the resulting image more compatible with various CI tools
- **Added** more packages to support PlayWright install called from the CI

## v1.2.1

- **Enhanced** unregistration process with GitHub API support
  and error handling
- **Added** **FAIL_FAST** option to skip failed registrations during startup

## v1.2.0

- **Added** **UNREGISTER_TOKENS** parameter to support muliple existing runners
  to be unregistered first if they persist in github, (see
  [README.md](README.md) for details)

## v1.1.1

- **Fixed** 'entrypoint.sh' call to non-existing config.sh
- **Fixed** markdownlint issues

- **Improved** GITHUB_URL handling, so it can be shorter

## v1.1.0

- **Updated** source image to debian:stable-slim
- **Updated** the startup sequence in 'entrypoint.sh' to support multiple
  runners in a single container (see [README.md](README.md) for details)

- **Added** PHP from deb.sury.org and related packages

## v1.0.8

- **Fixed** markdown issues in 'CODE_OF_CONDUCT.md' and 'CONTRIBUTING.md'.

## v1.0.7

First tagged version able to make it through the whole workflow, but
missed 'CHANGELOG.md'.
