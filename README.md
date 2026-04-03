# KakaoTalk Bot Environment (Redroid + Iris + IrisPy)

macOS(Apple Silicon)에서 Redroid(Android 14)를 Docker로 실행하고, Iris/IrisPy 기반 카카오톡 봇을 구축하는 자동화 스크립트.

## 아키텍처

```
macOS (Apple Silicon)
  └── UTM (가상화)
       └── Ubuntu ARM64 VM
            ├── Docker Engine
            │    └── Redroid Container (Android 14 ARM64)
            │         ├── 패치된 KakaoTalk APK
            │         ├── Iris (DB Observer + Message Broker)
            │         └── Termux (Linux 환경)
            │              └── proot-distro Ubuntu
            │                   └── irispy-client (Python 봇 로직)
            └── scrcpy / adb (화면 제어 및 디버깅)
```

## VM 접속 정보

| 항목 | 값 |
|------|-----|
| **VM IP** | `192.168.64.2` |
| **SSH 포트** | `22` |
| **사용자** | `cjy` |
| **비밀번호** | `Roqudtls3#` |
| **호스트명** | `kakao1` |
| **OS** | Ubuntu ARM64 (커널 6.8.0) |

```bash
# SSH 접속
ssh cjy@192.168.64.2

# sshpass 사용 (비대화식)
sshpass -p 'Roqudtls3#' ssh cjy@192.168.64.2
```

> VM IP는 UTM Shared Network(bridge100, 192.168.64.0/24) 대역에서 할당됩니다. VM 재시작 시 IP가 변경될 수 있습니다.

## 빠른 시작

```bash
# 전체 가이드 실행
./setup.sh

# 또는 특정 Phase만 실행
./setup.sh 1    # UTM + Ubuntu VM 설치 (macOS)
./setup.sh 2    # Docker + 커널 모듈 (VM)
./setup.sh 3    # Redroid 컨테이너 (VM)
./setup.sh 4    # KakaoTalk 패치
./setup.sh 5    # Iris 설치 (Redroid)
./setup.sh 6    # IrisPy 클라이언트 (Redroid)
./setup.sh 7    # 검증 및 테스트

# 현재 상태 확인
./setup.sh status
```

## 프로젝트 구조

```
kakaotalk_auto/
├── setup.sh                      # 메인 오케스트레이터
├── scripts/
│   ├── phase1.sh                 # UTM + Ubuntu VM 설치
│   ├── phase2.sh                 # Docker + 커널 모듈
│   ├── phase3.sh                 # Redroid 컨테이너
│   ├── phase4.sh                 # Hayul 카카오톡 패치
│   ├── phase5.sh                 # Iris 설치
│   ├── phase6.sh                 # IrisPy 클라이언트
│   └── phase7.sh                 # 검증 테스트
├── configs/
│   ├── docker-compose.yml        # Redroid Docker Compose
│   ├── redroid-modules.service   # 커널 모듈 자동 로드
│   ├── irispy-service.sh         # IrisPy init.d 서비스
│   └── start_iris.sh             # Iris 실행 스크립트 (Termux용)
├── bot/
│   └── irispy.py                 # 샘플 봇 코드
└── docs/
    └── TROUBLESHOOTING.md        # 트러블슈팅 가이드
```

## Phase별 상세 설명

### Phase 1: UTM에 Ubuntu ARM64 VM 설치 (macOS)
- UTM 설치 (Homebrew)
- Ubuntu 24.04 ARM64 Server ISO 다운로드
- VM 생성 가이드 (메모리 8GB, CPU 4코어, 디스크 64GB)
- 포트포워딩 설정 (SSH, ADB, Iris, Bot API)

### Phase 2: Docker 및 커널 모듈 (VM 내부)
- Docker Engine 설치
- `binder_linux` / `ashmem_linux` 커널 모듈 로드
- systemd 서비스로 부팅 시 자동 로드

### Phase 3: Redroid 컨테이너 실행 (VM 내부)
- Android 14 ARM64 컨테이너 생성
- ADB 연결 및 부팅 확인
- scrcpy 화면 제어 가이드

### Phase 4: Hayul로 카카오톡 패치
- Hayul 다운로드 및 설정
- KakaoTalk/Termux APK 패치
- 패치된 APK Redroid에 설치
- 카카오톡 로그인

### Phase 5: Iris 설치 (Redroid Termux 내부)
- Termux 환경변수 설정
- Iris 다운로드 및 실행
- 대시보드 확인

### Phase 6: IrisPy 클라이언트 (Redroid Termux proot)
- proot-distro Ubuntu 설치
- irispy-client 설치
- 봇 코드 배포 및 서비스 등록

### Phase 7: 검증 및 테스트
- Docker, 커널 모듈, Redroid, ADB, 앱 설치, Iris, 봇 서비스 확인

## 봇 명령어

기본 샘플 봇(`bot/irispy.py`)에 포함된 명령어:

| 명령어 | 설명 |
|--------|------|
| `/ping` | 봇 응답 확인 |
| `/echo <메시지>` | 메시지 반복 |
| `/time` | 현재 시간 표시 |
| `/help` | 도움말 표시 |

## 트러블슈팅

| 문제 | 해결책 |
|------|--------|
| `/dev/binder` 없음 | `sudo modprobe binder_linux devices="binder,hwbinder,vndbinder"` |
| ADB 연결 불가 | 포트 5555 확인, `docker restart redroid` |
| 컨테이너 반복 종료 | `docker logs redroid` 확인, 커널 모듈 로드 상태 확인 |
| scrcpy 연결 안됨 | ADB 연결 먼저 확인, X11 forwarding 설정 |
| Iris 실행 안됨 | Termux 환경변수 확인, `app_process` 경로 확인 |
| 카카오톡 DB 접근 불가 | `chmod -R 777 ~/data/data/com.kakao.talk/databases` |

## 참고 자료

- [redroid-doc](https://github.com/remote-android/redroid-doc)
- [redroid-modules](https://github.com/remote-android/redroid-modules)
- [Iris](https://github.com/dolidolih/Iris)
- [Hayul](https://github.com/ye-seola/Hayul)
- [UTM](https://mac.getutm.app/)
