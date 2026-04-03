#!/bin/bash
###############################################################################
# Phase 1: UTM에 Ubuntu ARM64 VM 설치 (macOS에서 실행)
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

# ─── Step 1-1: UTM 설치 ───────────────────────────────────────────────

install_utm() {
    log_step "Step 1-1: UTM 설치"

    if [[ -d "/Applications/UTM.app" ]]; then
        log_success "UTM이 이미 설치되어 있습니다."
        return 0
    fi

    if ! command -v brew &>/dev/null; then
        log_error "Homebrew가 설치되어 있지 않습니다."
        log_info "설치: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi

    log_info "UTM 설치 중..."
    brew install --cask utm
    log_success "UTM 설치 완료"
}

# ─── Step 1-2: Ubuntu ARM64 ISO 다운로드 ──────────────────────────────

download_ubuntu_iso() {
    log_step "Step 1-2: Ubuntu ARM64 ISO 다운로드"

    local iso_dir="$HOME/Downloads"
    local iso_name="ubuntu-24.04-live-server-arm64.iso"
    local iso_path="$iso_dir/$iso_name"

    if [[ -f "$iso_path" ]]; then
        log_success "Ubuntu ISO가 이미 존재합니다: $iso_path"
        return 0
    fi

    # Check for any Ubuntu ARM64 ISO
    local existing=$(find "$iso_dir" -maxdepth 1 -name "ubuntu-*-arm64.iso" 2>/dev/null | head -1)
    if [[ -n "$existing" ]]; then
        log_success "Ubuntu ARM64 ISO 발견: $existing"
        return 0
    fi

    log_info "Ubuntu 24.04 ARM64 Server ISO를 다운로드합니다."
    log_info "다운로드 URL: https://cdimage.ubuntu.com/releases/24.04/release/$iso_name"
    echo ""

    read -p "자동으로 다운로드하시겠습니까? (Y/n): " auto_dl
    if [[ "$auto_dl" == "n" || "$auto_dl" == "N" ]]; then
        log_info "수동 다운로드:"
        log_info "  https://ubuntu.com/download/server/arm"
        log_info "다운로드 후 $iso_dir 에 저장하세요."
        read -p "다운로드 완료 후 Enter를 눌러주세요..."
        return 0
    fi

    log_info "다운로드 중... (약 2GB, 시간이 걸릴 수 있습니다)"
    curl -L -o "$iso_path" \
        "https://cdimage.ubuntu.com/releases/24.04/release/$iso_name" \
        --progress-bar

    if [[ -f "$iso_path" ]]; then
        log_success "ISO 다운로드 완료: $iso_path"
    else
        log_error "다운로드 실패. 수동으로 다운로드해주세요."
        exit 1
    fi
}

# ─── Step 1-3: macOS 도구 설치 (ADB, scrcpy) ─────────────────────────

install_macos_tools() {
    log_step "Step 1-3: macOS 도구 설치 (ADB, scrcpy)"

    if ! command -v brew &>/dev/null; then
        log_warn "Homebrew가 없어 도구 설치를 건너뜁니다."
        return 0
    fi

    if ! command -v adb &>/dev/null; then
        log_info "android-platform-tools 설치 중..."
        brew install android-platform-tools
        log_success "ADB 설치 완료"
    else
        log_success "ADB 이미 설치됨: $(adb version 2>/dev/null | head -1)"
    fi

    if ! command -v scrcpy &>/dev/null; then
        log_info "scrcpy 설치 중..."
        brew install scrcpy
        log_success "scrcpy 설치 완료"
    else
        log_success "scrcpy 이미 설치됨"
    fi
}

# ─── Step 1-4: VM 생성 가이드 ─────────────────────────────────────────

show_vm_creation_guide() {
    log_step "Step 1-4: UTM VM 생성 가이드"

    echo -e "${CYAN}UTM에서 아래 설정으로 VM을 생성하세요:${NC}"
    echo ""
    echo "  1. UTM 실행 → '+' 버튼 → 'Virtualize' 선택"
    echo "  2. OS: 'Linux' 선택"
    echo "  3. Boot ISO Image: 다운로드한 Ubuntu ARM64 ISO 선택"
    echo "  4. Hardware 설정:"
    echo "     - Memory: 8192 MB (최소 4096 MB)"
    echo "     - CPU Cores: 4 (최소 2)"
    echo "  5. Storage: 64 GB (최소 32 GB)"
    echo "  6. Shared Directory: 필요시 설정"
    echo "  7. 'Save' 클릭"
    echo ""
    echo -e "${YELLOW}VM 생성 후 포트포워딩 설정:${NC}"
    echo "  VM 선택 → 설정(⚙️) → Network → Port Forward 에서:"
    echo "  ┌──────────┬───────────┬───────────┬──────────┐"
    echo "  │ Protocol │ Host Port │ Guest Port│ 용도     │"
    echo "  ├──────────┼───────────┼───────────┼──────────┤"
    echo "  │ TCP      │ 2222      │ 22        │ SSH      │"
    echo "  │ TCP      │ 5555      │ 5555      │ ADB      │"
    echo "  │ TCP      │ 3000      │ 3000      │ Iris     │"
    echo "  │ TCP      │ 5000      │ 5000      │ Bot API  │"
    echo "  └──────────┴───────────┴───────────┴──────────┘"
    echo ""
    echo -e "${YELLOW}Ubuntu 설치 후 기본 설정:${NC}"
    echo "  sudo apt update && sudo apt upgrade -y"
    echo "  sudo apt install -y git curl wget vim build-essential openssh-server"
    echo "  sudo systemctl enable ssh && sudo systemctl start ssh"
    echo ""
    echo -e "${GREEN}설치 완료 후 macOS에서 SSH 접속:${NC}"
    echo "  ssh -p 2222 <username>@localhost"
    echo ""

    read -p "VM 설정이 완료되면 Enter를 눌러주세요..."
}

# ─── Main ─────────────────────────────────────────────────────────────

main() {
    echo -e "${CYAN}Phase 1: UTM에 Ubuntu ARM64 VM 설치${NC}"
    echo ""

    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_warn "이 스크립트는 macOS에서 실행해야 합니다."
        read -p "계속하시겠습니까? (y/N): " cont
        if [[ "$cont" != "y" && "$cont" != "Y" ]]; then
            exit 0
        fi
    fi

    install_utm
    download_ubuntu_iso
    install_macos_tools
    show_vm_creation_guide

    log_success "Phase 1 완료!"
    echo ""
    log_info "다음 단계: VM 내부에서 Phase 2를 실행하세요."
    log_info "  VM에 SSH 접속 후: bash scripts/phase2.sh"
}

main "$@"
