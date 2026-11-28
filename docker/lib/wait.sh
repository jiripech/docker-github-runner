#!/bin/bash
# wait.sh - Summary and wait for runner PIDs with exit codes

wait_for_runners() {
    # Print failed repos summary
    if [ ${#FAILED_REPOS[@]} -gt 0 ]; then
        echo "=========================================="
        echo "WARNING: The following repositories failed:"
        for repo in "${FAILED_REPOS[@]}"; do
            echo "  $repo"
        done
        echo "=========================================="
    fi

    if [ ${#RUNNER_PIDS[@]} -eq 0 ]; then
        echo "Error: No runners started successfully."
        exit 1
    fi

    echo "=========================================="
    echo "All ${#RUNNER_PIDS[@]} runners started successfully."
    echo "Runner PIDs: ${RUNNER_PIDS[*]}"
    echo "=========================================="

    # Wait for each runner and capture exit codes
    local overall_exit=0
    for i in "${!RUNNER_PIDS[@]}"; do
        local pid="${RUNNER_PIDS[$i]}"
        local dir="${RUNNER_DIRS[$i]}"

        wait "$pid"
        local exit_code=$?

        if [ $exit_code -ne 0 ]; then
            echo "Runner in $dir exited with code $exit_code"
            overall_exit=1
        else
            echo "Runner in $dir exited successfully"
        fi
    done

    exit $overall_exit
}

# Cleanup function to stop all runners on exit
cleanup() {
    echo "Shutting down runners..."
    for pid in "${RUNNER_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    # Wait for all runners to stop
    for pid in "${RUNNER_PIDS[@]}"; do
        wait "$pid" 2>/dev/null || true
    done
    echo "All runners stopped."
    exit 0
}

# Trap signals for graceful shutdown
trap cleanup SIGTERM SIGINT