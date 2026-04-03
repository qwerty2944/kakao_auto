#!/bin/bash
###############################################################################
# Phase 5: Iris 설치 및 실행 (Redroid Termux 내부)
#
# 이 스크립트는 ADB를 통해 Termux 내부에서 명령을 실행하거나,
# 수동 실행 가이드를 제공합니다.
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    { echo -e "\n${CYAN}--- $* ---${NC}\n"; }

ADB_TARGET="localhost:5555"

# ─── ADB 연결 확인 ───────────────────────────────────────────────────

check_adb() {
    if ! command -v adb &>/dev/null; then
        log_error "ADB가 설치되어 있지 않습니다."
        return 1
    fi

    adb connect "$ADB_TARGET" &>/dev/null
    if adb -s "$ADB_TARGET" shell echo ok &>/dev/null; then
        log_success "ADB 연결됨: $ADB_TARGET"
        return 0
    else
        log_warn "ADB 연결 실패. 수동 가이드를 참고하세요."
        return 1
    fi
}

# ─── Termux에서 명령 실행 헬퍼 ────────────────────────────────────────

# Run a command inside Termux via ADB using run-as
run_in_termux() {
    adb -s "$ADB_TARGET" shell run-as com.termux files/usr/bin/bash -c "$1" 2>/dev/null
}

# ─── Step 5-1: Termux 환경 설정 스크립트 생성 ────────────────────────

create_termux_setup_script() {
    log_step "Step 5-1: Termux 환경 설정 스크립트 생성"

    local setup_script="/tmp/iris_setup.sh"

    cat > "$setup_script" << 'TERMUX_SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
# Iris Setup Script for Termux

echo "=== Iris 환경 설정 ==="

# Set environment variables
cat >> ~/.bashrc << 'ENVEOF'

# Iris Configuration
export IRIS_CONFIG_PATH="/data/data/com.termux/files/home/config.json"
export IRIS_RUNNER="com.termux"
ENVEOF

source ~/.bashrc

echo "[OK] 환경변수 설정 완료"

# Download Iris
echo "=== Iris 다운로드 ==="
curl -L -O https://github.com/dolidolih/Iris/releases/latest/download/Iris.apk
if [ -f "Iris.apk" ]; then
    echo "[OK] Iris.apk 다운로드 완료"
else
    echo "[ERROR] Iris 다운로드 실패"
    exit 1
fi

echo ""
echo "=== Iris 실행 방법 ==="
echo "다음 명령어로 Iris를 실행하세요:"
echo "  app_process -cp Iris.apk / party.qwer.iris.Main"
echo ""
echo "대시보드: http://localhost:3000/dashboard"
TERMUX_SCRIPT

    log_success "설정 스크립트 생성: $setup_script"
    echo "$setup_script"
}

# ─── Step 5-2: ADB를 통한 자동 설정 시도 ────────────────────────────

try_auto_setup() {
    log_step "Step 5-2: 자동 설정 시도"

    if ! check_adb; then
        return 1
    fi

    # Check if Termux is installed
    if ! adb -s "$ADB_TARGET" shell pm list packages 2>/dev/null | grep -q "com.termux"; then
        log_error "Termux가 Redroid에 설치되어 있지 않습니다."
        log_info "Phase 4에서 Termux APK를 설치하세요."
        return 1
    fi

    log_success "Termux 설치 확인됨"

    # Push and run setup script
    local setup_script=$(create_termux_setup_script)

    log_info "Termux에 설정 스크립트 전송 중..."
    adb -s "$ADB_TARGET" push "$setup_script" /data/local/tmp/iris_setup.sh

    log_info "스크립트를 Termux에서 실행합니다..."
    log_warn "Termux 앱이 실행 중이어야 합니다. scrcpy로 Termux를 먼저 열어주세요."

    echo ""
    read -p "Termux가 열려있나요? (Y/n): " ready
    if [[ "$ready" == "n" || "$ready" == "N" ]]; then
        log_info "scrcpy로 Termux를 연 후 다시 시도하세요."
        return 1
    fi

    # Try to execute via am command (launch Termux with the script)
    adb -s "$ADB_TARGET" shell "cp /data/local/tmp/iris_setup.sh /data/data/com.termux/files/home/iris_setup.sh" 2>/dev/null || true
    adb -s "$ADB_TARGET" shell "chmod 755 /data/data/com.termux/files/home/iris_setup.sh" 2>/dev/null || true

    log_info "Termux에서 다음 명령을 실행하세요:"
    echo "  bash ~/iris_setup.sh"

    return 0
}

# ─── Step 5-3: 수동 설정 가이드 ──────────────────────────────────────

show_manual_guide() {
    log_step "Iris 수동 설정 가이드"

    echo -e "${CYAN}scrcpy로 Redroid 화면을 열고 Termux에서 아래 명령을 실행하세요:${NC}"
    echo ""
    echo -e "${YELLOW}1. 환경변수 설정:${NC}"
    echo '  echo '\''export IRIS_CONFIG_PATH="/data/data/com.termux/files/home/config.json"'\'' >> ~/.bashrc'
    echo '  echo '\''export IRIS_RUNNER="com.termux"'\'' >> ~/.bashrc'
    echo '  source ~/.bashrc'
    echo ""
    echo -e "${YELLOW}2. Iris 다운로드:${NC}"
    echo '  curl -L -O https://github.com/dolidolih/Iris/releases/latest/download/Iris.apk'
    echo ""
    echo -e "${YELLOW}3. Iris 실행:${NC}"
    echo '  app_process -cp Iris.apk / party.qwer.iris.Main'
    echo ""
    echo -e "${YELLOW}4. 대시보드 확인:${NC}"
    echo "  브라우저에서 http://localhost:3000/dashboard 접속"
    echo "  (VM에서: curl http://localhost:3000/dashboard)"
    echo ""
    echo -e "${GREEN}Iris가 정상 실행되면 'Iris server started' 메시지가 표시됩니다.${NC}"
    echo ""

    # Create a helper script for easy reference
    cat > /tmp/iris_commands.txt << 'CMDEOF'
# ===== Iris 설치 명령어 (Termux에서 실행) =====

# 1. 환경변수 설정
echo 'export IRIS_CONFIG_PATH="/data/data/com.termux/files/home/config.json"' >> ~/.bashrc
echo 'export IRIS_RUNNER="com.termux"' >> ~/.bashrc
source ~/.bashrc

# 2. Iris 다운로드
curl -L -O https://github.com/dolidolih/Iris/releases/latest/download/Iris.apk

# 3. Iris 실행
app_process -cp Iris.apk / party.qwer.iris.Main

# ============================================
CMDEOF

    log_info "명령어가 /tmp/iris_commands.txt 에도 저장되었습니다."
}

# ─── Iris 실행 스크립트 생성 (Termux용) ──────────────────────────────

create_iris_launcher() {
    log_step "Iris 실행 스크립트 생성"

    # Create a launcher script that can be pushed to Termux
    local launcher="/tmp/start_iris.sh"

    cat > "$launcher" << 'LAUNCHER_EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Iris Launcher Script

export IRIS_CONFIG_PATH="/data/data/com.termux/files/home/config.json"
export IRIS_RUNNER="com.termux"

IRIS_APK="$HOME/Iris.apk"

if [ ! -f "$IRIS_APK" ]; then
    echo "Iris.apk not found. Downloading..."
    curl -L -O https://github.com/dolidolih/Iris/releases/latest/download/Iris.apk
fi

echo "Starting Iris..."
echo "Dashboard: http://localhost:3000/dashboard"
app_process -cp "$IRIS_APK" / party.qwer.iris.Main
LAUNCHER_EOF

    chmod +x "$launcher"

    # Try to push to device
    if check_adb 2>/dev/null; then
        adb -s "$ADB_TARGET" push "$launcher" /data/local/tmp/start_iris.sh 2>/dev/null && \
            log_info "실행 스크립트가 디바이스에 전송되었습니다." || true
    fi

    log_success "Iris 실행 스크립트 생성: $launcher"
    echo ""
    echo "Termux에서 사용:"
    echo "  cp /data/local/tmp/start_iris.sh ~/start_iris.sh"
    echo "  chmod +x ~/start_iris.sh"
    echo "  bash ~/start_iris.sh"
}

# ─── Main ─────────────────────────────────────────────────────────────

main() {
    echo -e "${CYAN}Phase 5: Iris 설치 및 실행${NC}"
    echo ""

    if try_auto_setup; then
        log_info "자동 설정 스크립트가 준비되었습니다."
    fi

    create_iris_launcher
    echo ""
    show_manual_guide

    echo ""
    read -p "Iris가 실행되었나요? (y/N): " iris_running
    if [[ "$iris_running" == "y" || "$iris_running" == "Y" ]]; then
        log_success "Phase 5 완료!"
    else
        log_warn "Iris 실행 후 Phase 6으로 진행하세요."
    fi

    echo ""
    log_info "다음 단계: Phase 6에서 IrisPy 클라이언트를 설치하세요."
    log_info "  bash scripts/phase6.sh"
}

main "$@"
