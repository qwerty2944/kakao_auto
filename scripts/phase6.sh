#!/bin/bash
###############################################################################
# Phase 6: IrisPy 클라이언트 설치 (Redroid Termux 내부 proot-distro)
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOT_DIR="$(dirname "$SCRIPT_DIR")/bot"

ADB_TARGET="localhost:5555"

# ─── Step 6-1: proot-distro 설정 가이드 ──────────────────────────────

show_proot_guide() {
    log_step "Step 6-1: proot-distro로 Ubuntu 설치 (Termux 새 탭에서)"

    echo -e "${CYAN}Termux에서 새 터미널 탭을 열고 다음 명령을 실행하세요:${NC}"
    echo ""
    echo -e "${YELLOW}# proot-distro 설치 및 Ubuntu 환경 구성${NC}"
    echo '  pkg update && pkg install proot-distro'
    echo '  proot-distro install ubuntu'
    echo '  proot-distro login ubuntu'
    echo ""
    echo -e "${YELLOW}# Ubuntu proot 내부에서:${NC}"
    echo '  apt update && apt upgrade -y'
    echo '  apt install -y sudo python3.12-venv openssh-server curl'
    echo ""
    echo -e "${YELLOW}# 사용자 생성 (선택사항):${NC}"
    echo '  useradd -m ubuntu'
    echo '  passwd ubuntu'
    echo '  usermod -aG sudo ubuntu'
    echo '  echo "ubuntu  ALL=(ALL:ALL) ALL" >> /etc/sudoers'
    echo '  su ubuntu'
    echo ""
}

# ─── Step 6-2: IrisPy 설치 가이드 ───────────────────────────────────

show_irispy_guide() {
    log_step "Step 6-2: irispy-client 설치"

    echo -e "${CYAN}proot Ubuntu 내부에서:${NC}"
    echo ""
    echo '  cd ~'
    echo '  mkdir -p ipy2 && cd ipy2'
    echo '  python3 -m venv venv'
    echo '  source venv/bin/activate'
    echo '  pip install irispy-client'
    echo '  iris init'
    echo ""
    echo -e "${GREEN}'iris init' 실행 후 config.json과 irispy.py가 생성됩니다.${NC}"
    echo ""
}

# ─── Step 6-3: 봇 코드 배포 ─────────────────────────────────────────

deploy_bot_code() {
    log_step "Step 6-3: 봇 코드 배포"

    if [[ ! -f "$BOT_DIR/irispy.py" ]]; then
        log_warn "봇 코드가 없습니다. 기본 봇을 사용하세요 (iris init으로 생성됨)."
        return 0
    fi

    log_info "커스텀 봇 코드를 Redroid에 배포합니다."

    if command -v adb &>/dev/null && adb -s "$ADB_TARGET" shell echo ok &>/dev/null; then
        adb -s "$ADB_TARGET" push "$BOT_DIR/irispy.py" /data/local/tmp/irispy.py 2>/dev/null && \
            log_success "봇 코드 전송됨" || \
            log_warn "ADB 전송 실패"

        echo ""
        echo "Termux proot 내부에서:"
        echo "  cp /data/local/tmp/irispy.py ~/ipy2/irispy.py"
    else
        echo ""
        echo -e "${YELLOW}봇 코드를 수동으로 복사하세요:${NC}"
        echo "  내용: $BOT_DIR/irispy.py"
        echo ""
    fi
}

# ─── Step 6-4: 서비스 등록 가이드 ────────────────────────────────────

show_service_guide() {
    log_step "Step 6-4: irispy 서비스 등록"

    echo -e "${CYAN}proot Ubuntu에서 서비스로 등록 (선택사항):${NC}"
    echo ""
    cat << 'SERVICE_GUIDE'
# 서비스 스크립트 생성
sudo tee /etc/init.d/irispy << 'SCRIPT'
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
    cd $WORK_DIR
    sudo -u $SERVICE_USER setsid $PYTHON_BIN $APP_SCRIPT --host 127.0.0.1 --port 3000 \
        >> $LOG_FILE 2>&1 &
    echo $! > $PID_FILE
    echo "$SERVICE_NAME started."
}

stop() {
    if [ -f $PID_FILE ]; then
        PID=$(cat $PID_FILE)
        echo "Stopping $SERVICE_NAME (PID: $PID)..."
        kill -- -$(ps -o pgid= $PID | tr -d ' ') 2>/dev/null
        rm -f $PID_FILE
        echo "$SERVICE_NAME stopped."
    fi
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 2; start ;;
    *) echo "Usage: $0 {start|stop|restart}" ;;
esac
SCRIPT

sudo chmod +x /etc/init.d/irispy
sudo update-rc.d irispy defaults
sudo service irispy start
SERVICE_GUIDE

    echo ""
    echo -e "${YELLOW}또는 간단하게 직접 실행:${NC}"
    echo "  cd ~/ipy2"
    echo "  source venv/bin/activate"
    echo "  python irispy.py"
    echo ""
}

# ─── 전체 설정 스크립트 생성 (Termux proot용) ────────────────────────

create_proot_setup_script() {
    log_step "proot 내부용 자동 설정 스크립트 생성"

    local script_path="/tmp/irispy_proot_setup.sh"

    cat > "$script_path" << 'PROOT_SCRIPT'
#!/bin/bash
# IrisPy Setup Script for proot-distro Ubuntu
# Run this inside: proot-distro login ubuntu

set -e

echo "=== IrisPy 환경 설정 ==="

# Install dependencies
apt update
apt install -y python3 python3-venv python3-pip curl sudo

# Create user if not exists
if ! id ubuntu &>/dev/null; then
    useradd -m ubuntu
    echo "ubuntu:ubuntu" | chpasswd
    usermod -aG sudo ubuntu
    echo "ubuntu  ALL=(ALL:ALL) ALL" >> /etc/sudoers
fi

# Setup as ubuntu user
su - ubuntu << 'USEREOF'
cd ~
mkdir -p ipy2
cd ipy2

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install irispy-client
pip install irispy-client

# Initialize irispy
iris init

echo ""
echo "=== IrisPy 설치 완료! ==="
echo "실행 방법:"
echo "  cd ~/ipy2"
echo "  source venv/bin/activate"
echo "  python irispy.py"
USEREOF
PROOT_SCRIPT

    chmod +x "$script_path"

    # Try to push to device
    if command -v adb &>/dev/null && adb -s "$ADB_TARGET" shell echo ok &>/dev/null; then
        adb -s "$ADB_TARGET" push "$script_path" /data/local/tmp/irispy_proot_setup.sh 2>/dev/null || true
    fi

    log_success "설정 스크립트 생성: $script_path"
    echo ""
    echo "proot Ubuntu 내부에서:"
    echo "  bash /data/local/tmp/irispy_proot_setup.sh"
    echo "또는 수동으로 위 가이드를 따르세요."
}

# ─── Main ─────────────────────────────────────────────────────────────

main() {
    echo -e "${CYAN}Phase 6: IrisPy 클라이언트 설치${NC}"
    echo ""

    show_proot_guide
    read -p "proot-distro Ubuntu 설치가 완료되면 Enter..."

    show_irispy_guide
    create_proot_setup_script

    echo ""
    deploy_bot_code

    show_service_guide

    log_success "Phase 6 완료!"
    echo ""
    log_info "다음 단계: Phase 7에서 전체 시스템을 검증하세요."
    log_info "  bash scripts/phase7.sh"
}

main "$@"
