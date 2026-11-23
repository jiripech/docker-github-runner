FROM debian:stable-slim

# Arguments for architecture
ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive

# Install basic dependencies
RUN apt-get -y update && apt-get install -y --no-install-recommends sudo curl
RUN apt-get install -y --no-install-recommends jq git rsync ca-certificates
RUN apt-get install -y --no-install-recommends gnupg lsb-release openssh-server

# Create runner user and set shell/password to avoid locked account
RUN useradd -m -s /bin/bash runner
RUN echo "runner:runner" | chpasswd
RUN echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install Docker CLI
RUN mkdir -p /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
RUN apt-get -y update && apt-get install -y docker-ce-cli

# Install GitHub CLI
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh

# Install PHP
RUN curl -sSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb && \
    echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && \
    echo 'debconf debconf/frontend seen false' | debconf-set-selections && \
    dpkg -i /tmp/debsuryorg-archive-keyring.deb && \
    echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php-sury.list && \
    apt-get update && apt-get install -y php8.6-cli php-pear && rm -rf /var/lib/apt/lists/*

# SSH Server Configuration
RUN mkdir -p /var/run/sshd
COPY sshd_config /etc/ssh/sshd_config
# Authorized keys will be copied from build context (injected by build.sh)
COPY authorized_keys /home/runner/.ssh/authorized_keys
RUN chown -R runner:runner /home/runner/.ssh && \
    chmod 700 /home/runner/.ssh && \
    chmod 600 /home/runner/.ssh/authorized_keys

EXPOSE 22

WORKDIR /home/runner

# Download and install GitHub Runner
RUN GH_RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/v//') \
    && if [ "$TARGETARCH" = "amd64" ]; then GH_ARCH="x64"; elif [ "$TARGETARCH" = "arm64" ]; then GH_ARCH="arm64"; else echo "Unsupported arch: $TARGETARCH"; exit 1; fi \
    && echo "Downloading runner version ${GH_RUNNER_VERSION} for ${GH_ARCH}..." \
    && curl -O -L https://github.com/actions/runner/releases/download/v${GH_RUNNER_VERSION}/actions-runner-linux-${GH_ARCH}-${GH_RUNNER_VERSION}.tar.gz \
    && tar xzf ./actions-runner-linux-${GH_ARCH}-${GH_RUNNER_VERSION}.tar.gz \
    && rm ./actions-runner-linux-${GH_ARCH}-${GH_RUNNER_VERSION}.tar.gz \
    && ./bin/installdependencies.sh

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && chown runner:runner /entrypoint.sh

USER runner
ENTRYPOINT ["/entrypoint.sh"]
