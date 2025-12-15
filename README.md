# GitHub Actions Runner with SSH Support

This repository contains a Docker-based GitHub Actions Runner that supports:
- **Multi-architecture** builds (amd64, arm64).
- **SSH access** for debugging (injected automatically during build).
- **Persistent logs and workspace** via Docker volumes.

## Project Structure

*   `docker/`: Contains the `Dockerfile`, `entrypoint.sh` and configuration files.
*   `scripts/`: Helper scripts for building and managing the runner.
*   `LICENSE`: Project license.

## Prerequisites

*   Docker Desktop (or Docker Engine with Buildx support).
*   A GitHub Repository (URL + Token).

## Building the Image

Use the provided build script to create the Docker image.

```bash
./scripts/build.sh <image-name> [push|load]
```

*   `push`: Builds for both `amd64` and `arm64` and pushes to the registry (requires `docker login`).
*   `load`: Builds for your local architecture only and loads it into your local Docker daemon (for testing).

### SSH Key Injection logic

The build script automatically secures the runner by injecting **your strongest local public SSH key** into the image's `authorized_keys`.

1.  It searches `~/.ssh/` for public keys in this preference order:
    *   `id_ed25519.pub` (Best)
    *   `id_ecdsa.pub`
    *   `id_rsa.pub`
    *   `id_dsa.pub`
2.  It copies **only one** (the strongest found) into the container.
3.  **Result**: You can SSH into the running container without managing passwords or copying keys manually.

## Running the Runner

To run the container, you must provide the GitHub URL and a Registration Token.

### Basic Usage

```bash
docker run -d \
  -e GITHUB_URL="https://github.com/your-org/your-repo" \
  -e GITHUB_TOKEN="A1B2C3D4..." \
  --name my-runner \
  <image-name>
```

### Environment Variables

| Variable | Description | Required | Default |
| :--- | :--- | :--- | :--- |
| `GITHUB_URL` | Full URL to the repository or organization. | **Yes** | - |
| `GITHUB_TOKEN` | Registration Token (from Settings -> Actions -> Runners). | **Yes** | - |
| `RUNNER_NAME` | Name of the runner in GitHub UI. | No | `hostname` |
| `RUNNER_LABELS` | Comma-separated labels (e.g. `gpu,linux`). | No | `default` |

### SSH Access

Port 22 is exposed by default. Map it to a custom port (e.g. 2222) to avoid conflict with the host.

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
*(Your local SSH key is already authorized!)*

### Data Persistence (Logs & Cache)

To inspect logs from the host or persist the build cache between restarts, map volume mounts to these internal paths:

*   `_diag`: Runner logs.
*   `_work`: Build workspace (repo checkout, build artifacts).

**Example:**

```bash
mkdir -p ./data/logs ./data/work

docker run -d \
  -v $(pwd)/data/logs:/home/runner/_diag \
  -v $(pwd)/data/work:/home/runner/_work \
  -e GITHUB_URL="..." \
  -e GITHUB_TOKEN="..." \
  <image-name>
```

**Note on Permissions:** The runner runs as user `runner` (uid 1000). Ensure your host directories are accessible/writable by this user, or use Docker Desktop's loose permission model.

## Troubleshooting

*   **SSH Permission Denied**: Check `docker logs <container-id>` to ensure `sshd` started. Verify your local key matches the one injected during build.
*   **404 Auth Error**: Check your `GITHUB_TOKEN` expiration and scope.
