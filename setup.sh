#!/bin/bash
###############################################################################
# KakaoTalk Bot Environment Setup - Main Orchestrator
# macOS (Apple Silicon) + UTM + Ubuntu ARM64 VM + Redroid + Iris + IrisPy
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

# Colors
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
log_phase()   { echo -e "\n${CYAN}========================================${NC}"; echo -e "${CYAN} $*${NC}"; echo -e "${CYAN}========================================${NC}\n"; }

show_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  KakaoTalk Bot Environment Setup                    ║"
    echo "║  Redroid + Iris + IrisPy on macOS (Apple Silicon)   ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo "Architecture:"
    echo "  macOS → UTM → Ubuntu ARM64 VM → Docker → Redroid (Android 14)"
    echo "                                           ├── KakaoTalk (patched)"
    echo "                                           ├── Iris (DB Observer)"
    echo "                                           └── Termux → IrisPy (Bot)"
    echo ""
}

show_menu() {
    echo "Select a phase to run (or 'all' for guided setup):"
    echo ""
    echo "  [1] Phase 1: Install UTM & prepare Ubuntu ARM64 VM (macOS)"
    echo "  [2] Phase 2: Install Docker & kernel modules      (VM)"
    echo "  [3] Phase 3: Run Redroid container + ADB/scrcpy   (VM)"
    echo "  [4] Phase 4: Patch KakaoTalk with Hayul           (VM/macOS)"
    echo "  [5] Phase 5: Install Iris in Redroid Termux       (Redroid)"
    echo "  [6] Phase 6: Install IrisPy client                (Redroid)"
    echo "  [7] Phase 7: Verify & test everything             (all)"
    echo ""
    echo "  [all] Run all phases sequentially"
    echo "  [status] Show current setup status"
    echo "  [q] Quit"
    echo ""
}

detect_environment() {
    local arch=$(uname -m)
    local os=$(uname -s)

    if [[ "$os" == "Darwin" ]]; then
        if [[ "$arch" == "arm64" ]]; then
            echo "macos_arm64"
        else
            echo "macos_x86"
        fi
    elif [[ "$os" == "Linux" ]]; then
        echo "linux"
    else
        echo "unknown"
    fi
}

check_phase_applicable() {
    local phase=$1
    local env=$(detect_environment)

    case $phase in
        1)
            if [[ "$env" != macos_* ]]; then
                log_warn "Phase 1 (UTM setup) should be run on macOS."
                return 1
            fi
            ;;
        2|3)
            if [[ "$env" != "linux" ]]; then
                log_warn "Phase $phase should be run inside the Ubuntu VM."
                log_info "SSH into your VM first: ssh user@<VM_IP>"
                return 1
            fi
            ;;
        4)
            # Can run on either macOS or VM
            return 0
            ;;
        5|6)
            log_info "Phase $phase requires manual steps inside Redroid's Termux."
            log_info "The script will print instructions to follow."
            return 0
            ;;
        7)
            return 0
            ;;
    esac
    return 0
}

run_phase() {
    local phase=$1
    local script="$SCRIPTS_DIR/phase${phase}.sh"

    if [[ ! -f "$script" ]]; then
        log_error "Script not found: $script"
        return 1
    fi

    if ! check_phase_applicable "$phase"; then
        echo ""
        read -p "Run anyway? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            return 0
        fi
    fi

    log_phase "Phase $phase"
    bash "$script"
}

show_status() {
    log_phase "Environment Status"

    local env=$(detect_environment)
    echo "Current environment: $env"
    echo ""

    if [[ "$env" == macos_* ]]; then
        echo "=== macOS Checks ==="
        if command -v utm &>/dev/null || [[ -d "/Applications/UTM.app" ]]; then
            log_success "UTM: Installed"
        else
            log_warn "UTM: Not installed"
        fi

        if command -v adb &>/dev/null; then
            log_success "ADB: Installed ($(adb version 2>/dev/null | head -1))"
        else
            log_warn "ADB: Not installed"
        fi

        if command -v scrcpy &>/dev/null; then
            log_success "scrcpy: Installed"
        else
            log_warn "scrcpy: Not installed"
        fi

    elif [[ "$env" == "linux" ]]; then
        echo "=== VM Checks ==="
        if command -v docker &>/dev/null; then
            log_success "Docker: Installed ($(docker --version 2>/dev/null))"
        else
            log_warn "Docker: Not installed"
        fi

        if lsmod 2>/dev/null | grep -q binder_linux; then
            log_success "binder_linux: Loaded"
        else
            log_warn "binder_linux: Not loaded"
        fi

        if lsmod 2>/dev/null | grep -q ashmem_linux; then
            log_success "ashmem_linux: Loaded"
        else
            log_warn "ashmem_linux: Not loaded"
        fi

        if docker ps 2>/dev/null | grep -q redroid; then
            log_success "Redroid: Running"
        else
            log_warn "Redroid: Not running"
        fi

        if command -v adb &>/dev/null; then
            if adb devices 2>/dev/null | grep -q "localhost:5555"; then
                log_success "ADB: Connected to Redroid"
            else
                log_warn "ADB: Not connected to Redroid"
            fi
        fi
    fi
}

main() {
    show_banner

    if [[ $# -gt 0 ]]; then
        case $1 in
            [1-7]) run_phase "$1" ;;
            all)
                for i in 1 2 3 4 5 6 7; do
                    run_phase "$i"
                    echo ""
                    if [[ $i -lt 7 ]]; then
                        read -p "Continue to Phase $((i+1))? (Y/n): " cont
                        if [[ "$cont" == "n" || "$cont" == "N" ]]; then
                            log_info "Stopped after Phase $i. Run './setup.sh $((i+1))' to continue."
                            exit 0
                        fi
                    fi
                done
                ;;
            status) show_status ;;
            *) echo "Usage: $0 [1-7|all|status]" ;;
        esac
        return
    fi

    while true; do
        show_menu
        read -p "Choice: " choice
        case $choice in
            [1-7]) run_phase "$choice" ;;
            all)
                for i in 1 2 3 4 5 6 7; do
                    run_phase "$i"
                    echo ""
                    if [[ $i -lt 7 ]]; then
                        read -p "Continue to Phase $((i+1))? (Y/n): " cont
                        if [[ "$cont" == "n" || "$cont" == "N" ]]; then
                            log_info "Stopped after Phase $i."
                            break
                        fi
                    fi
                done
                ;;
            status) show_status ;;
            q|Q) echo "Bye!"; exit 0 ;;
            *) log_error "Invalid choice." ;;
        esac
        echo ""
    done
}

main "$@"
