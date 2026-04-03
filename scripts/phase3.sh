#!/bin/bash
###############################################################################
# Phase 3: Redroid (Android 14) 컨테이너 실행 (Ubuntu VM 내부에서 실행)
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

REDROID_DATA_DIR="$HOME/redroid-data"

# ─── Pre-checks ──────────────────────────────────────────────────────

preflight_checks() {
    log_step "사전 점검"

    if [[ "$(uname -s)" != "Linux" ]]; then
        log_error "이 스크립트는 Ubuntu VM 내부에서 실행해야 합니다."
        exit 1
    fi

    if ! command -v docker &>/dev/null; then
        log_error "Docker가 설치되어 있지 않습니다. Phase 2를 먼저 실행하세요."
        exit 1
    fi

    # Check docker access
    if ! docker ps &>/dev/null; then
        log_warn "Docker 접근 권한이 없습니다. sudo로 실행합니다."
        log_info "'newgrp docker' 또는 재로그인 후 다시 시도해보세요."
    fi

    # Check kernel modules
    if ! lsmod | grep -q binder_linux; then
        log_warn "binder_linux 모듈이 로드되지 않았습니다."
        log_info "모듈 로드 시도 중..."
        sudo modprobe binder_linux devices="binder,hwbinder,vndbinder" || {
            log_error "binder_linux 로드 실패. Phase 2를 확인하세요."
            exit 1
        }
    fi

    log_success "사전 점검 완료"
}

# ─── Step 3-1: Redroid 컨테이너 실행 ─────────────────────────────────

start_redroid() {
    log_step "Step 3-1: Redroid 컨테이너 실행"

    # Check if already running
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^redroid$"; then
        log_success "Redroid 컨테이너가 이미 실행 중입니다."
        docker ps --filter name=redroid --format "table {{.ID}}\t{{.Status}}\t{{.Ports}}"
        return 0
    fi

    # Check if container exists but stopped
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^redroid$"; then
        log_info "기존 Redroid 컨테이너를 시작합니다..."
        docker start redroid
        log_success "Redroid 컨테이너 시작됨"
        return 0
    fi

    # Create data directory
    mkdir -p "$REDROID_DATA_DIR"

    log_info "Redroid Android 14 ARM64 컨테이너를 생성합니다..."
    log_info "이미지 다운로드에 시간이 걸릴 수 있습니다..."

    docker run -itd --privileged \
        --name redroid \
        --pull always \
        -v "$REDROID_DATA_DIR:/data" \
        -p 5555:5555 \
        -p 3000:3000 \
        redroid/redroid:14.0.0_64only-latest \
        ro.product.model=SM-T970 \
        ro.product.brand=Samsung \
        androidboot.redroid_gpu_mode=guest

    log_success "Redroid 컨테이너 생성 및 시작 완료"

    # Wait for boot
    log_info "Android 부팅 대기 중... (30-60초 소요)"
    local timeout=120
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if adb connect localhost:5555 &>/dev/null; then
            local boot_complete=$(adb -s localhost:5555 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
            if [[ "$boot_complete" == "1" ]]; then
                log_success "Android 부팅 완료!"
                return 0
            fi
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo -ne "\r  부팅 중... ${elapsed}/${timeout}초"
    done
    echo ""
    log_warn "부팅 타임아웃. 컨테이너 로그를 확인하세요: docker logs redroid"
}

# ─── Step 3-2: ADB 연결 ──────────────────────────────────────────────

connect_adb() {
    log_step "Step 3-2: ADB 연결"

    if ! command -v adb &>/dev/null; then
        log_info "ADB 설치 중..."
        sudo apt install -y android-sdk-platform-tools
    fi

    log_info "ADB 연결 시도 중..."
    adb connect localhost:5555

    sleep 2

    log_info "연결된 장치 목록:"
    adb devices

    # Test shell access
    log_info "Android 시스템 정보:"
    adb -s localhost:5555 shell getprop ro.product.model 2>/dev/null || true
    adb -s localhost:5555 shell getprop ro.build.version.release 2>/dev/null || true
}

# ─── Step 3-3: scrcpy 안내 ───────────────────────────────────────────

show_scrcpy_guide() {
    log_step "Step 3-3: 화면 제어 (scrcpy) 안내"

    echo -e "${CYAN}Redroid 화면을 보려면 scrcpy를 사용하세요:${NC}"
    echo ""
    echo "  방법 1: VM 내부에서 (X11 필요)"
    echo "    scrcpy -s localhost:5555"
    echo ""
    echo "  방법 2: macOS에서 직접 연결 (UTM 포트포워딩 필요)"
    echo "    adb connect localhost:5555  # macOS에서"
    echo "    scrcpy -s localhost:5555"
    echo ""
    echo "  방법 3: SSH X11 Forwarding"
    echo "    ssh -X -p 2222 user@localhost  # macOS에서"
    echo "    scrcpy -s localhost:5555       # VM 내부에서"
    echo ""
    echo -e "${YELLOW}유용한 scrcpy 옵션:${NC}"
    echo "    --max-size=1024        해상도 제한"
    echo "    --bit-rate=2M          비트레이트 설정"
    echo "    --window-title=Redroid 윈도우 제목"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────

main() {
    echo -e "${CYAN}Phase 3: Redroid (Android 14) 컨테이너 실행${NC}"
    echo ""

    preflight_checks
    start_redroid
    connect_adb
    show_scrcpy_guide

    log_success "Phase 3 완료!"
    echo ""
    log_info "Redroid가 실행 중입니다."
    log_info "scrcpy로 화면을 확인하고, Phase 4로 진행하세요."
    log_info "  bash scripts/phase4.sh"
}

main "$@"
