#!/bin/bash
# ssh.sh - SSH daemon startup

start_ssh() {
    echo "Starting SSH Daemon..."
    sudo /usr/sbin/sshd

    # Ensure data directory exists and is writable
    mkdir -p "$RUNNER_DATA_DIR"
    cd "$RUNNER_DATA_DIR" || exit 1
}