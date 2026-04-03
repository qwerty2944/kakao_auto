#!/bin/bash
###############################################################################
# Phase 7: 검증 및 테스트
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

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check_pass() { ((PASS_COUNT++)); log_success "$*"; }
check_fail() { ((FAIL_COUNT++)); log_error "$*"; }
check_warn() { ((WARN_COUNT++)); log_warn "$*"; }

ADB_TARGET="localhost:5555"

# ─── 7-1: 환경 감지 ─────────────────────────────────────────────────

detect_env() {
    log_step "환경 감지"

    local os=$(uname -s)
    local arch=$(uname -m)

    echo "OS: $os"
    echo "Architecture: $arch"

    if [[ "$os" == "Linux" ]]; then
        echo "Environment: Ubuntu VM (예상)"
        return 0
    elif [[ "$os" == "Darwin" ]]; then
        echo "Environment: macOS"
        log_info "macOS에서는 일부 검증만 수행합니다."
        return 1
    fi
}

# ─── 7-2: Docker 상태 확인 ───────────────────────────────────────────

check_docker() {
    log_step "Step 7-1: Docker 상태 확인"

    if ! command -v docker &>/dev/null; then
        check_fail "Docker가 설치되어 있지 않습니다."
        return
    fi

    check_pass "Docker 설치됨: $(docker --version 2>/dev/null)"

    if docker ps &>/dev/null; then
        check_pass "Docker 데몬 실행 중"
    else
        check_fail "Docker 데몬이 실행 중이지 않거나 권한이 없습니다."
    fi
}

# ─── 7-3: 커널 모듈 확인 ─────────────────────────────────────────────

check_kernel_modules() {
    log_step "커널 모듈 확인"

    if [[ "$(uname -s)" != "Linux" ]]; then
        log_info "macOS에서는 커널 모듈 확인을 건너뜁니다."
        return
    fi

    if lsmod | grep -q binder_linux; then
        check_pass "binder_linux 모듈 로드됨"
    else
        check_fail "binder_linux 모듈 미로드"
    fi

    if lsmod | grep -q ashmem_linux; then
        check_pass "ashmem_linux 모듈 로드됨"
    else
        check_warn "ashmem_linux 모듈 미로드 (커널 5.18+에서는 선택사항)"
    fi
}

# ─── 7-4: Redroid 컨테이너 확인 ──────────────────────────────────────

check_redroid() {
    log_step "Step 7-1: Redroid 컨테이너 상태 확인"

    if ! command -v docker &>/dev/null; then
        check_warn "Docker 없음, Redroid 확인 불가"
        return
    fi

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^redroid$"; then
        check_pass "Redroid 컨테이너 실행 중"
        echo ""
        docker ps --filter name=redroid --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
    elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^redroid$"; then
        check_fail "Redroid 컨테이너가 중지되어 있습니다."
        echo "  재시작: docker start redroid"

        echo ""
        echo "최근 로그:"
        docker logs --tail 20 redroid 2>/dev/null || true
    else
        check_fail "Redroid 컨테이너가 존재하지 않습니다."
    fi
}

# ─── 7-5: ADB 연결 확인 ─────────────────────────────────────────────

check_adb() {
    log_step "ADB 연결 확인"

    if ! command -v adb &>/dev/null; then
        check_warn "ADB 미설치"
        return
    fi

    check_pass "ADB 설치됨"

    adb connect "$ADB_TARGET" &>/dev/null

    if adb -s "$ADB_TARGET" shell echo ok &>/dev/null; then
        check_pass "ADB 연결됨: $ADB_TARGET"

        local model=$(adb -s "$ADB_TARGET" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
        local version=$(adb -s "$ADB_TARGET" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
        echo "  Model: $model"
        echo "  Android: $version"
    else
        check_fail "ADB 연결 실패: $ADB_TARGET"
    fi
}

# ─── 7-6: 앱 설치 확인 ──────────────────────────────────────────────

check_installed_apps() {
    log_step "설치된 앱 확인"

    if ! adb -s "$ADB_TARGET" shell echo ok &>/dev/null; then
        check_warn "ADB 연결 불가, 앱 확인 스킵"
        return
    fi

    # Check KakaoTalk
    if adb -s "$ADB_TARGET" shell pm list packages 2>/dev/null | grep -q "com.kakao.talk"; then
        check_pass "카카오톡 설치됨"
    else
        check_fail "카카오톡 미설치"
    fi

    # Check Termux
    if adb -s "$ADB_TARGET" shell pm list packages 2>/dev/null | grep -q "com.termux"; then
        check_pass "Termux 설치됨"
    else
        check_fail "Termux 미설치"
    fi
}

# ─── 7-7: Iris 동작 확인 ─────────────────────────────────────────────

check_iris() {
    log_step "Step 7-2: Iris 동작 확인"

    # Check via HTTP
    if curl -s --connect-timeout 5 http://localhost:3000/dashboard &>/dev/null; then
        check_pass "Iris 대시보드 접근 가능 (localhost:3000)"
    else
        check_warn "Iris 대시보드 접근 불가 (localhost:3000)"
        log_info "Iris가 Termux에서 실행 중인지 확인하세요."
        log_info "  Termux에서: app_process -cp Iris.apk / party.qwer.iris.Main"
    fi
}

# ─── 7-8: 봇 서비스 확인 ─────────────────────────────────────────────

check_bot_service() {
    log_step "Step 7-3: 봇 서비스 확인"

    # Check if irispy is running (inside proot, harder to check from outside)
    log_info "봇 서비스는 Termux proot 내부에서 확인해야 합니다."
    echo ""
    echo "  확인 방법:"
    echo "  1. Termux에서 proot-distro login ubuntu"
    echo "  2. ps aux | grep irispy"
    echo "  3. sudo service irispy status (서비스 등록한 경우)"
    echo ""
}

# ─── Summary ─────────────────────────────────────────────────────────

show_summary() {
    log_step "검증 결과 요약"

    echo -e "  ${GREEN}통과: $PASS_COUNT${NC}"
    echo -e "  ${RED}실패: $FAIL_COUNT${NC}"
    echo -e "  ${YELLOW}경고: $WARN_COUNT${NC}"
    echo ""

    if [[ $FAIL_COUNT -eq 0 ]]; then
        echo -e "${GREEN}모든 검증을 통과했습니다!${NC}"
    else
        echo -e "${YELLOW}실패한 항목을 확인하고 수정하세요.${NC}"
        echo ""
        echo "트러블슈팅 가이드:"
        echo "  ┌──────────────────────────┬──────────────────────────────────────┐"
        echo "  │ 문제                     │ 해결책                               │"
        echo "  ├──────────────────────────┼──────────────────────────────────────┤"
        echo "  │ /dev/binder 없음         │ modprobe binder_linux 재실행         │"
        echo "  │ ADB 연결 불가            │ 포트 5555 확인, Redroid 재시작       │"
        echo "  │ 컨테이너 반복 종료       │ docker logs redroid 확인             │"
        echo "  │ scrcpy 연결 안됨         │ ADB 연결 먼저 확인                   │"
        echo "  │ Iris 실행 안됨           │ 환경변수, app_process 경로 확인      │"
        echo "  │ 카카오톡 DB 접근 불가    │ chmod -R 777 ~/data/.../databases    │"
        echo "  └──────────────────────────┴──────────────────────────────────────┘"
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────

main() {
    echo -e "${CYAN}Phase 7: 검증 및 테스트${NC}"
    echo ""

    local is_vm=true
    detect_env || is_vm=false

    if $is_vm; then
        check_docker
        check_kernel_modules
    fi

    check_redroid
    check_adb
    check_installed_apps
    check_iris
    check_bot_service

    show_summary
}

main "$@"
