#!/bin/bash
###############################################################################
# Phase 4: Hayul로 카카오톡 패치 (macOS 또는 VM에서 실행)
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

WORK_DIR="$(pwd)/hayul-workspace"

# ─── Step 4-1: Hayul 다운로드 및 의존성 설치 ─────────────────────────

setup_hayul() {
    log_step "Step 4-1: Hayul 다운로드 및 의존성 설치"

    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    # Clone Hayul
    if [[ -d "Hayul" ]]; then
        log_info "Hayul 업데이트 중..."
        cd Hayul && git pull && cd ..
    else
        log_info "Hayul 클론 중..."
        git clone https://github.com/ye-seola/Hayul.git
    fi

    # Install Python dependencies
    log_info "Python 의존성 설치 중..."
    if command -v pip3 &>/dev/null; then
        pip3 install lxml pyaxml pure-python-adb cryptography
    elif command -v pip &>/dev/null; then
        pip install lxml pyaxml pure-python-adb cryptography
    else
        log_error "pip가 설치되어 있지 않습니다."
        log_info "sudo apt install python3-pip  (Linux)"
        log_info "brew install python  (macOS)"
        exit 1
    fi

    log_success "Hayul 설정 완료"
}

# ─── Step 4-2: JDK 및 Keystore 설정 ─────────────────────────────────

setup_jdk_and_keystore() {
    log_step "Step 4-2: JDK 및 Keystore 설정"

    # Check JDK
    if ! command -v keytool &>/dev/null; then
        log_info "JDK가 필요합니다."
        if [[ "$(uname -s)" == "Darwin" ]]; then
            log_info "macOS: brew install openjdk"
            brew install openjdk 2>/dev/null || log_warn "JDK 설치 실패"
        else
            log_info "Linux: sudo apt install default-jdk"
            sudo apt install -y default-jdk
        fi
    else
        log_success "JDK 확인됨: $(java -version 2>&1 | head -1)"
    fi

    # Generate keystore
    cd "$WORK_DIR/Hayul"

    if [[ -f "KEY.jks" ]]; then
        log_success "Keystore(KEY.jks)가 이미 존재합니다."
        return 0
    fi

    log_info "Keystore 생성 중..."
    echo ""
    echo -e "${YELLOW}Keystore 정보를 입력하세요 (기본값으로 Enter 가능):${NC}"

    keytool -genkey -v -keystore KEY.jks \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -storepass changeit -keypass changeit \
        -dname "CN=KakaoBot, OU=Dev, O=Dev, L=Seoul, ST=Seoul, C=KR" \
        2>/dev/null || {
        log_info "자동 생성 실패. 수동으로 생성합니다..."
        keytool -genkey -v -keystore KEY.jks -keyalg RSA -keysize 2048 -validity 10000
    }

    log_success "Keystore 생성 완료"
}

# ─── Step 4-3: APK 준비 안내 ─────────────────────────────────────────

prepare_apks() {
    log_step "Step 4-3: APK 파일 준비"

    local apk_dir="$WORK_DIR/Hayul"

    echo -e "${CYAN}패치에 필요한 APK 파일을 준비하세요:${NC}"
    echo ""
    echo "  1. 카카오톡 APK (ARM64 버전)"
    echo "     - APKMirror에서 다운로드: https://www.apkmirror.com/apk/kakao/kakaotalk/"
    echo "     - 'arm64-v8a' 아키텍처 선택"
    echo "     - Split APK (APKS/XAPK) 또는 단일 APK"
    echo ""
    echo "  2. Termux APK"
    echo "     - F-Droid: https://f-droid.org/packages/com.termux/"
    echo "     - 또는 GitHub: https://github.com/termux/termux-app/releases"
    echo ""
    echo -e "${YELLOW}APK 파일을 다음 경로에 복사하세요:${NC}"
    echo "  $apk_dir/"
    echo ""

    # Check if APKs exist
    local kakao_found=false
    local termux_found=false

    if ls "$apk_dir"/*kakao* "$apk_dir"/*KakaoTalk* 2>/dev/null | head -1 &>/dev/null; then
        kakao_found=true
        log_success "카카오톡 APK 발견"
    fi

    if ls "$apk_dir"/*termux* "$apk_dir"/*Termux* 2>/dev/null | head -1 &>/dev/null; then
        termux_found=true
        log_success "Termux APK 발견"
    fi

    if ! $kakao_found || ! $termux_found; then
        log_warn "APK 파일이 아직 준비되지 않았습니다."
        read -p "APK를 준비한 후 Enter를 눌러주세요... (건너뛰려면 's'): " resp
        if [[ "$resp" == "s" || "$resp" == "S" ]]; then
            log_warn "APK 준비를 건너뜁니다. 나중에 수동으로 패치하세요."
            return 1
        fi
    fi

    return 0
}

# ─── Step 4-4: Hayul 패치 실행 ───────────────────────────────────────

run_hayul_patch() {
    log_step "Step 4-4: Hayul 패치 실행"

    cd "$WORK_DIR/Hayul"

    echo -e "${CYAN}Hayul 패치를 실행합니다.${NC}"
    echo ""
    echo "패치 과정에서 다음을 입력하세요:"
    echo "  - 첫 번째 프롬프트: com.kakao.talk"
    echo "  - 두 번째 프롬프트: com.termux"
    echo ""

    read -p "패치를 시작하시겠습니까? (Y/n): " start
    if [[ "$start" == "n" || "$start" == "N" ]]; then
        log_info "패치를 건너뜁니다."
        return 0
    fi

    python3 main.py || python main.py

    log_success "패치 완료"
}

# ─── Step 4-5: 패치된 APK 설치 ───────────────────────────────────────

install_patched_apks() {
    log_step "Step 4-5: 패치된 APK를 Redroid에 설치"

    cd "$WORK_DIR/Hayul"

    # Check ADB connection
    if ! adb devices 2>/dev/null | grep -q "localhost:5555\|device"; then
        log_info "ADB 연결 시도 중..."
        adb connect localhost:5555 2>/dev/null || {
            log_warn "Redroid ADB 연결 실패."
            log_info "VM 내부에서 실행하거나 ADB 포트포워딩을 확인하세요."
            show_manual_install_guide
            return 0
        }
    fi

    # Install patched KakaoTalk
    if [[ -d "patched-com.kakao.talk" ]]; then
        log_info "패치된 카카오톡 설치 중..."
        adb install-multiple patched-com.kakao.talk/*.apk && \
            log_success "카카오톡 설치 완료" || \
            log_warn "카카오톡 설치 실패. 수동으로 설치하세요."
    else
        log_warn "패치된 카카오톡 APK가 없습니다."
    fi

    # Install patched Termux
    if [[ -d "patched-com.termux" ]]; then
        log_info "패치된 Termux 설치 중..."
        adb install-multiple patched-com.termux/*.apk && \
            log_success "Termux 설치 완료" || \
            log_warn "Termux 설치 실패. 수동으로 설치하세요."
    else
        log_warn "패치된 Termux APK가 없습니다."
    fi
}

show_manual_install_guide() {
    echo ""
    echo -e "${YELLOW}수동 설치 방법:${NC}"
    echo "  1. ADB 연결: adb connect localhost:5555"
    echo "  2. 카카오톡: adb install-multiple patched-com.kakao.talk/*.apk"
    echo "  3. Termux:   adb install-multiple patched-com.termux/*.apk"
    echo ""
}

# ─── Step 4-6: 카카오톡 로그인 안내 ──────────────────────────────────

show_login_guide() {
    log_step "Step 4-6: 카카오톡 로그인 안내"

    echo -e "${CYAN}카카오톡 로그인을 완료해야 합니다:${NC}"
    echo ""
    echo "  1. scrcpy로 Redroid 화면 열기:"
    echo "     scrcpy -s localhost:5555"
    echo ""
    echo "  2. 카카오톡 앱 실행 후 로그인"
    echo ""
    echo -e "  ${YELLOW}3. 중요! 로그인 후 반드시:${NC}"
    echo "     - 아무 채팅방에서 메시지 한 번 보내기"
    echo "     - 다른 사람에게 메시지 한 번 받기"
    echo "     (Iris가 사용할 DB가 초기화되어야 합니다)"
    echo ""

    read -p "카카오톡 로그인이 완료되면 Enter를 눌러주세요..."
}

# ─── Main ─────────────────────────────────────────────────────────────

main() {
    echo -e "${CYAN}Phase 4: Hayul로 카카오톡 패치${NC}"
    echo ""

    setup_hayul
    setup_jdk_and_keystore

    if prepare_apks; then
        run_hayul_patch
        install_patched_apks
    fi

    show_login_guide

    log_success "Phase 4 완료!"
    echo ""
    log_info "다음 단계: Phase 5에서 Iris를 설치하세요."
    log_info "  bash scripts/phase5.sh"
}

main "$@"
