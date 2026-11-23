# GitHub Actions Runner with SSH Support

This repository contains a Docker-based GitHub Actions Runner that supports:

- **Multi-architecture** builds (amd64, arm64).
- **SSH access** for debugging (injected automatically during build).
- **Persistent logs and workspace** via Docker volumes.

> [!WARNING]
> **Security Notice**: Be extremely cautious when using Self-Hosted Runners on
**Public Repositories**! Malicious pull requests from forks can automatically
run on your infrastructure and access secrets or local network resources. It is
recommended to use **"Require approval for all outside collaborators"** in your
repository settings.

## Project Structure

- `docker/`: Contains the `Dockerfile`, `entrypoint.sh` and configuration files.
- `scripts/`: Helper scripts for building and managing the runner.
- `LICENSE.md`: Project license.
- `README.md`: Project documentation.
- `CONTRIBUTING.md`: Project contribution guidelines.

## Prerequisites

- Docker Desktop (or Docker Engine with Buildx support).
- A GitHub Repository (URL + Token).

## Building the Image

Use the provided build script to create the Docker image.

```bash
./scripts/build.sh <image-name> [push|load]
```

- `push`: Builds for both `amd64` and `arm64` and pushes to the registry
(requires `docker login`).
- `load`: Builds for your local architecture only and loads it into your local
Docker daemon (for testing).

### SSH Key Injection logic

The build script automatically secures the runner by injecting
**your strongest local public SSH key** into the image's `authorized_keys`.

1. It searches `~/.ssh/` for public keys in this preference order:
    - `id_ed25519.pub` (preferred)
    - `id_ecdsa.pub`
    - `id_rsa.pub`
    - `id_dsa.pub`
2. It copies **only one** (the strongest found) into the container.
3. **Result**: You can SSH into the running container without managing passwords
  or copying keys manually.

### Building using Github workflow

It's simple, but some [variables and secrets][encryptedSecretsLink] are
necessary to be set before you start the build

#### Variables

My values as examples

- **DOCKER_IMAGE_NAME**=`docker-github-runner`
- **DOCKER_NAMESPACE**=`hqcz`

#### Secrests

No examples here, see [scripts/build.sh] for details.

- DOCKER_TOKEN (your docker hub token)
- DOCKER_USERNAME (your docker hub username)
- SSH_KEY_PUBLIC (usually `~/.ssh/id_ed25519.pub`)

## Running the Runner

To run the container, you must provide the GitHub URL and a Registration Token.

### Single Runner (Legacy)

```bash
docker run -d \
  -e GITHUB_URL="https://github.com/your-org/your-repo" \
  -e GITHUB_TOKEN="A1B2C3D4..." \
  --name my-runner \
  <image-name>
```

### Multi-Runner (Recommended)

Run multiple self-hosted runners in a single container by providing
a comma-delimited list of repository URLs and a runner name prefix.

```bash
docker run -d \
  -e GITHUB_URL="https://github.com/org/repo1,https://github.com/org/repo2" \
  -e GH_PAT="ghp_..." \
  -e RUNNER_NAME_PREFIX="my-runner" \
  <image-name>
```

**Abbreviated URL syntax** (for repos under the same owner):

```bash
docker run -d \
  -e GITHUB_URL="https://github.com/org/repo1,/repo2,/repo3" \
  -e GH_PAT="ghp_..." \
  -e RUNNER_NAME_PREFIX="my-runner" \
  <image-name>
```

This will create runners named `my-runner-repo1`, `my-runner-repo2`, and
`my-runner-repo3`.

### Environment Variables

#### Auto-Registration (Required for Multi-Runner)

Instead of manually generating a short-lived token, you provide
a **Personal Access Token (PAT)** with `repo` scope. The runner will
automatically generate a registration token for each repository.

##### `GITHUB_URL`

**Single runner**: Full HTTPS URL to the repository or organization (without
  '.git' at the end)

**Multi-runner**: Comma-delimited list of HTTPS URLs to repositories/organizations.
Supports **abbreviated URLs** for repositories under the same owner.

- **Full URLs**: `"https://github.com/owner/repo1,https://github.com/owner/repo2"`
- **Abbreviated URLs**: `"https://github.com/owner/repo1,/repo2,/repo3"`
  - First URL must be full (establishes the base `https://github.com/owner`)
  - Subsequent URLs starting with `/` are expanded using that base
  - Example above expands to: `repo1`, `repo2`, `repo3` all under `owner`
- Spaces around commas are trimmed automatically

##### `GH_PAT`

Personal Access Token with `repo` scope. Auto-generates registration tokens.
**Required for multi-runner mode.** Also works for single runner.

##### `GITHUB_TOKEN`

*Legacy*: Registration Token (short-lived).
Only for single-runner mode. Not supported with multiple URLs.

##### `RUNNER_NAME_PREFIX`

**Multi-runner only**: Prefix for runner names.
Each runner will be named `${RUNNER_NAME_PREFIX}-${repo_name}`.

- Example: `RUNNER_NAME_PREFIX="ci-runner"` with repo `my-app` →
  `ci-runner-my-app`
- **Required** when using multiple URLs in `GITHUB_URL`

##### `RUNNER_NAME`

**Single runner only**: Name of the runner in GitHub UI.
If not provided defaults to `hostname`.
Ignored when `RUNNER_NAME_PREFIX` is set.

##### `RUNNER_LABELS`

**Optional** comma-separated labels applied to all runners (e.g. `gpu,linux,
insecure`).
Default: `default`

##### `RUNNER_WORKDIR`

**Optional** base work directory for all runners.
Default: `_work`
Each runner gets a subdirectory: `${RUNNER_WORKDIR}/${repo_name}`

##### `UNREGISTER_TOKENS`

**Optional** comma-separated list of runner removal tokens.
Use this to clean up previously registered runners when the container is
recreated.
Tokens can be obtained from GitHub UI (Settings → Actions → Runners → click
runner → "Remove runner" → copy token from command).

Example: `UNREGISTER_TOKENS="token1,token2,AAW63K6VAWLL6XJ24GA5CFTLARVMS"`

Each token will be used to run `./config.sh remove --token <token>` before configuring new runners.

### SSH Access

Port 22 is exposed by default. Map it to a custom port (e.g. 2222)
to avoid conflict with the host.

```bash
docker run -d \
  -p 2222:22 \
  -e GITHUB_URL="..." \
  -e GITHUB_TOKEN="..." \
  <image-name>
```

Connect using:

```bash
ssh -p 2222 runner@localhost
```

ℹ️ **(Your local SSH key is already authorized!)**

### Data Persistence (Logs & Cache)

To inspect logs from the host or persist the build cache between restarts,
map volume mounts to these internal paths:

- `_diag`: Runner logs.
- `_work`: Build workspace (repo checkout, build artifacts).

**Example:**

```bash
mkdir -p ./.runner/logs ./.runner/work

docker run -d \
  -v $(pwd)/.runner/logs:/home/runner/_diag \
  -v $(pwd)/.runner/work:/home/runner/_work \
  -e GITHUB_URL="..." \
  -e GH_PAT="..." \
  <image-name>
```

**Note on Permissions:** The runner runs as user `runner` (uid 1000).
Ensure your host directories are accessible/writable by this user,
or use Docker Desktop's loose permission model.

## Troubleshooting

- **SSH Permission Denied**: Check `docker logs <container-id>`
  to ensure `sshd` started. Verify your local key matches the one
  injected during build.
- **404 Auth Error**: Check your `GITHUB_TOKEN` expiration and scope.

[encryptedSecretsLink]: https://docs.github.com/actions/automating-your-workflow-with-github-actions/creating-and-using-encrypted-secrets
