#!/bin/bash
###############################################################################
# Phase 2: Docker 및 커널 모듈 설치 (Ubuntu VM 내부에서 실행)
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

check_linux() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        log_error "이 스크립트는 Ubuntu VM 내부에서 실행해야 합니다."
        exit 1
    fi
}

# ─── Step 2-1: Docker 설치 ────────────────────────────────────────────

install_docker() {
    log_step "Step 2-1: Docker 설치"

    if command -v docker &>/dev/null; then
        log_success "Docker 이미 설치됨: $(docker --version)"
        return 0
    fi

    log_info "Docker 의존성 설치 중..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl

    log_info "Docker GPG 키 추가 중..."
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    log_info "Docker 저장소 추가 중..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    log_info "Docker 패키지 설치 중..."
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    log_info "현재 사용자를 docker 그룹에 추가 중..."
    sudo usermod -aG docker "$USER"

    log_success "Docker 설치 완료"
    log_warn "docker 그룹이 적용되려면 로그아웃 후 재로그인하거나 'newgrp docker'를 실행하세요."
}

# ─── Step 2-2: Binder/Ashmem 커널 모듈 로드 ──────────────────────────

load_kernel_modules() {
    log_step "Step 2-2: Binder/Ashmem 커널 모듈 로드"

    # Check if modules are already loaded
    if lsmod | grep -q binder_linux && lsmod | grep -q ashmem_linux; then
        log_success "커널 모듈이 이미 로드되어 있습니다."
        lsmod | grep -E "binder_linux|ashmem_linux"
        return 0
    fi

    # Try installing linux-modules-extra
    local kernel_ver=$(uname -r)
    log_info "현재 커널 버전: $kernel_ver"

    log_info "linux-modules-extra-$kernel_ver 설치 시도 중..."
    if sudo apt install -y "linux-modules-extra-$kernel_ver" 2>/dev/null; then
        log_success "linux-modules-extra 설치 완료"
    else
        log_warn "linux-modules-extra 패키지를 찾을 수 없습니다."
        log_info "redroid-modules에서 직접 빌드를 시도합니다..."
        build_kernel_modules
    fi

    # Load modules
    log_info "binder_linux 모듈 로드 중..."
    if sudo modprobe binder_linux devices="binder,hwbinder,vndbinder" 2>/dev/null; then
        log_success "binder_linux 로드 성공"
    else
        log_warn "binder_linux 로드 실패. 직접 빌드가 필요할 수 있습니다."
        build_kernel_modules
        sudo modprobe binder_linux devices="binder,hwbinder,vndbinder"
    fi

    log_info "ashmem_linux 모듈 로드 중..."
    if sudo modprobe ashmem_linux 2>/dev/null; then
        log_success "ashmem_linux 로드 성공"
    else
        log_warn "ashmem_linux 로드 실패 (커널 5.18+ 에서는 memfd를 사용하므로 불필요할 수 있음)"
    fi

    # Verify
    echo ""
    log_info "로드된 모듈 확인:"
    lsmod | grep -E "binder_linux|ashmem_linux" || log_warn "모듈이 로드되지 않았습니다."

    # Check /dev/binder*
    if [[ -e /dev/binderfs ]] || [[ -e /dev/binder ]]; then
        log_success "/dev/binder 디바이스 확인됨"
    else
        log_info "/dev/binderfs 마운트 시도..."
        sudo mkdir -p /dev/binderfs
        sudo mount -t binder binder /dev/binderfs 2>/dev/null || true
    fi
}

build_kernel_modules() {
    log_info "redroid-modules 빌드 중..."

    local build_dir="/tmp/redroid-modules"
    if [[ -d "$build_dir" ]]; then
        rm -rf "$build_dir"
    fi

    sudo apt install -y "linux-headers-$(uname -r)" kmod make gcc

    git clone https://github.com/remote-android/redroid-modules.git "$build_dir"
    cd "$build_dir"
    sudo make
    sudo make install
    cd -

    log_success "커널 모듈 빌드 완료"
}

# ─── Step 2-3: 부팅 시 자동 로드 설정 ────────────────────────────────

setup_autoload() {
    log_step "Step 2-3: 부팅 시 자동 로드 설정"

    local service_file="/etc/systemd/system/redroid-modules.service"

    if [[ -f "$service_file" ]]; then
        log_success "자동 로드 서비스가 이미 설정되어 있습니다."
        return 0
    fi

    log_info "systemd 서비스 생성 중..."
    sudo tee "$service_file" > /dev/null << 'EOF'
[Unit]
Description=Load binder and ashmem kernel modules for Redroid
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/modprobe binder_linux devices="binder,hwbinder,vndbinder"
ExecStart=/sbin/modprobe ashmem_linux

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable redroid-modules.service
    sudo systemctl start redroid-modules.service

    log_success "자동 로드 서비스 등록 완료"
}

# ─── Step 2-4: 기본 도구 설치 ────────────────────────────────────────

install_basic_tools() {
    log_step "Step 2-4: 기본 도구 설치"

    log_info "필수 패키지 설치 중..."
    sudo apt install -y \
        android-sdk-platform-tools \
        git \
        curl \
        wget \
        vim \
        build-essential \
        python3 \
        python3-pip \
        python3-venv \
        default-jdk

    # Try installing scrcpy
    if ! command -v scrcpy &>/dev/null; then
        log_info "scrcpy 설치 시도 중..."
        sudo apt install -y scrcpy 2>/dev/null || {
            log_warn "scrcpy를 apt로 설치할 수 없습니다."
            log_info "snap으로 시도합니다..."
            sudo snap install scrcpy 2>/dev/null || {
                log_warn "scrcpy 설치 실패. macOS에서 직접 연결하세요."
            }
        }
    fi

    log_success "기본 도구 설치 완료"
}

# ─── Main ─────────────────────────────────────────────────────────────

main() {
    echo -e "${CYAN}Phase 2: Docker 및 커널 모듈 설치 (Ubuntu VM)${NC}"
    echo ""

    check_linux

    install_docker
    load_kernel_modules
    setup_autoload
    install_basic_tools

    log_success "Phase 2 완료!"
    echo ""
    log_info "다음 단계: Phase 3을 실행하여 Redroid 컨테이너를 시작하세요."
    log_info "  bash scripts/phase3.sh"

    if ! groups "$USER" | grep -q docker; then
        log_warn "docker 그룹 적용을 위해 먼저 재로그인하세요."
    fi
}

main "$@"
