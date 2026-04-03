#!/data/data/com.termux/files/usr/bin/bash
# Iris Launcher Script for Termux
# Termux 내부에서 실행: bash ~/start_iris.sh

export IRIS_CONFIG_PATH="/data/data/com.termux/files/home/config.json"
export IRIS_RUNNER="com.termux"

IRIS_APK="$HOME/Iris.apk"

if [ ! -f "$IRIS_APK" ]; then
    echo "Iris.apk not found. Downloading..."
    curl -L -O https://github.com/dolidolih/Iris/releases/latest/download/Iris.apk
    if [ ! -f "$IRIS_APK" ]; then
        echo "ERROR: Download failed"
        exit 1
    fi
fi

echo "Starting Iris..."
echo "Dashboard: http://localhost:3000/dashboard"
echo "Press Ctrl+C to stop"
echo ""

app_process -cp "$IRIS_APK" / party.qwer.iris.Main
