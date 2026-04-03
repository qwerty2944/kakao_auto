#!/bin/bash
### BEGIN INIT INFO
# Provides:          irispy_service
# Required-Start:    $local_fs $network
# Required-Stop:     $local_fs $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       Irispy Python Application
### END INIT INFO

SERVICE_NAME="irispy_service"
SERVICE_USER="ubuntu"
WORK_DIR="/home/ubuntu/ipy2"
PYTHON_BIN="$WORK_DIR/venv/bin/python"
APP_SCRIPT="$WORK_DIR/irispy.py"
PID_FILE="/var/run/$SERVICE_NAME.pid"
LOG_FILE="/var/log/$SERVICE_NAME.log"

start() {
    echo "Starting $SERVICE_NAME..."
    cd "$WORK_DIR"
    sudo -u "$SERVICE_USER" setsid "$PYTHON_BIN" "$APP_SCRIPT" --host 127.0.0.1 --port 3000 \
        >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    echo "$SERVICE_NAME started."
}

stop() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        echo "Stopping $SERVICE_NAME (PID: $PID)..."
        kill -- -"$(ps -o pgid= "$PID" | tr -d ' ')" 2>/dev/null
        rm -f "$PID_FILE"
        echo "$SERVICE_NAME stopped."
    else
        echo "$SERVICE_NAME is not running."
    fi
}

status() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo "$SERVICE_NAME is running (PID: $PID)"
        else
            echo "$SERVICE_NAME is dead but PID file exists"
            rm -f "$PID_FILE"
        fi
    else
        echo "$SERVICE_NAME is not running"
    fi
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 2; start ;;
    status) status ;;
    *) echo "Usage: $0 {start|stop|restart|status}" ;;
esac
