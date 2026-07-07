#!/bin/sh
# Run the SQL Server database CompuOffice needs, as a container on your Mac.
# This is how you avoid Windows entirely: CompuOffice (the app) runs under Wine,
# and its SQL Server backend runs as a Linux container here. No Windows anywhere.
#
# Microsoft ships SQL Server for Linux as a container image. On Apple Silicon it
# runs under emulation (works, a little slower); on Intel it runs natively.
#
# Usage:
#   ./compuoffice-db.sh up       # start SQL Server (creates it the first time)
#   ./compuoffice-db.sh down     # stop it (data is kept)
#   ./compuoffice-db.sh status   # show container state
#   ./compuoffice-db.sh logs     # tail the SQL Server log
#   ./compuoffice-db.sh destroy  # remove the container AND its data (careful)
#
# Configure via env vars before running:
#   SA_PASSWORD  (default below)  -- must meet SQL Server complexity rules
#   HOST_PORT    (default 1433)   -- port CompuOffice connects to on localhost

set -e

NAME="compuoffice-sql"
VOLUME="compuoffice-sql-data"
SA_PASSWORD="${SA_PASSWORD:-CompuOffice#2024}"
HOST_PORT="${HOST_PORT:-1433}"
# SQL Server 2022. Apple Silicon runs this x86_64 image under emulation.
IMAGE="mcr.microsoft.com/mssql/server:2022-latest"

need_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker is not installed. Install Docker Desktop or Colima:" >&2
        echo "  brew install --cask docker      # Docker Desktop (GUI)" >&2
        echo "  brew install colima docker      # Colima (lightweight, CLI)" >&2
        exit 1
    fi
    if ! docker info >/dev/null 2>&1; then
        echo "Docker is installed but not running. Start Docker Desktop (or 'colima start')." >&2
        exit 1
    fi
}

platform_flag() {
    # On Apple Silicon, force the amd64 image (emulated) since MS ships no arm64.
    if [ "$(uname -m)" = "arm64" ]; then
        printf '%s' "--platform linux/amd64"
    fi
}

cmd_up() {
    need_docker
    if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
        docker start "$NAME" >/dev/null
        echo "Started existing container '$NAME'."
    else
        echo "Creating SQL Server container (first run pulls the image; be patient)..."
        # shellcheck disable=SC2046
        docker run -d \
            $(platform_flag) \
            --name "$NAME" \
            -e "ACCEPT_EULA=Y" \
            -e "MSSQL_SA_PASSWORD=$SA_PASSWORD" \
            -e "MSSQL_PID=Express" \
            -p "$HOST_PORT:1433" \
            -v "$VOLUME:/var/opt/mssql" \
            "$IMAGE" >/dev/null
        echo "Created and started '$NAME'."
    fi
    echo ""
    echo "SQL Server is coming up on: localhost,$HOST_PORT"
    echo "  Login:    sa"
    echo "  Password: $SA_PASSWORD"
    echo ""
    echo "In CompuOffice's database settings, use server 'localhost,$HOST_PORT'"
    echo "(or '127.0.0.1,$HOST_PORT'), SQL auth, the sa login above."
    echo "Give it ~30s to finish starting, then check:  ./compuoffice-db.sh status"
}

cmd_down() {
    need_docker
    docker stop "$NAME" >/dev/null 2>&1 && echo "Stopped '$NAME' (data kept)." \
        || echo "Container '$NAME' was not running."
}

cmd_status() {
    need_docker
    if docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
        echo "Running:"
        docker ps --filter "name=$NAME" --format '  {{.Names}}  {{.Status}}  {{.Ports}}'
        # readiness probe if sqlcmd is present in the image
        if docker exec "$NAME" sh -c 'ls /opt/mssql-tools*/bin/sqlcmd' >/dev/null 2>&1; then
            SQLCMD=$(docker exec "$NAME" sh -c 'ls /opt/mssql-tools*/bin/sqlcmd | head -n1')
            if docker exec "$NAME" "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" \
                -No -Q "SELECT 1" >/dev/null 2>&1; then
                echo "  SQL Server is accepting connections."
            else
                echo "  SQL Server is still starting (or password mismatch)."
            fi
        fi
    else
        echo "Not running. Start it with:  ./compuoffice-db.sh up"
    fi
}

cmd_logs() {
    need_docker
    docker logs -f "$NAME"
}

cmd_destroy() {
    need_docker
    printf "This deletes the container AND all its data. Type 'yes' to confirm: "
    read -r ans
    if [ "$ans" = "yes" ]; then
        docker rm -f "$NAME" >/dev/null 2>&1 || true
        docker volume rm "$VOLUME" >/dev/null 2>&1 || true
        echo "Removed container and data volume."
    else
        echo "Aborted."
    fi
}

case "${1:-}" in
    up)      cmd_up ;;
    down)    cmd_down ;;
    status)  cmd_status ;;
    logs)    cmd_logs ;;
    destroy) cmd_destroy ;;
    *)
        echo "Usage: $0 {up|down|status|logs|destroy}" >&2
        exit 1
        ;;
esac
