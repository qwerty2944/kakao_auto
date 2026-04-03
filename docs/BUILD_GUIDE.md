# macOS Apple Silicon - Redroid + Iris + IrisPy 카카오톡 봇 완전 빌드 가이드

> 실제 구축 과정에서 만난 **모든 실수와 해결책**을 기록한 문서.
> 다른 Mac에서 이 문서만 보고 처음부터 끝까지 한번에 구축 가능.

---

## 검증된 환경

| 항목 | 버전 |
|------|------|
| macOS | Apple Silicon (M1/M2/M3/M4) |
| UTM | Homebrew 최신 |
| Ubuntu VM | 24.04.4 LTS ARM64 Server |
| Kernel | 6.8.0-106-generic aarch64 |
| Docker | 29.3.0 |
| Redroid | `redroid/redroid:14.0.0_64only-latest` |
| KakaoTalk | 26.2.2 (Aptoide에서 다운) |
| Termux | 0.118.1 (GitHub releases) |
| scrcpy | 3.3.4 |

---

## 핵심 주의사항 (읽지 않으면 몇 시간 날림)

### 1. Redroid 이미지: 반드시 `64only`만 사용
```
Apple Silicon에서 작동하는 이미지:
  ✅ redroid/redroid:14.0.0_64only-latest

Apple Silicon에서 부팅 안 되는 이미지 (전부 테스트함):
  ❌ redroid/redroid:14.0.0-latest      → TIMEOUT (부팅 안됨)
  ❌ redroid/redroid:12.0.0-latest      → TIMEOUT
  ❌ redroid/redroid:11.0.0-latest      → TIMEOUT
  ❌ ro.product.cpu.abilist 오버라이드  → 부팅 안됨
```
**32+64bit 겸용 이미지는 Apple Silicon에서 절대 안 된다.** ABI 오버라이드도 안 된다.

### 2. 카카오톡 APK: apkpure 쓰지 말고 Aptoide에서 받아라
```
❌ apkpure   → armeabi-v7a (32비트) native lib만 제공 → 64only에서 안됨
❌ APKMirror → Bundle(APKS) 형식만 제공, 직접 다운 어려움
✅ Aptoide   → arm64-v8a split APK 별도 제공
```

### 3. 카카오톡 설치는 4개 APK를 install-multiple로
```bash
adb install-multiple \
  kakao_base.apk \          # Aptoide에서 받은 base (~211MB)
  kakao_arm64_split.apk \   # Aptoide에서 받은 arm64 split (~59MB, .so 34개)
  config.en.apk \           # apkpure XAPK에서 추출한 언어 split
  config.mdpi.apk           # apkpure XAPK에서 추출한 density split
```
**base + arm64 split만으로는 `INSTALL_FAILED_MISSING_SPLIT` 발생.** density split 필수.

### 4. Iris.apk는 반드시 chmod 444 (읽기 전용)
```
Android 14에서 writable dex 파일 로드 차단됨:
  "Writable dex file '/data/data/com.termux/files/home/Iris.apk' is not allowed."

해결: chmod 444 Iris.apk
```

### 5. app_process 전체 경로 사용
```
Termux PATH에 /system/bin이 없음.
  ❌ app_process -cp Iris.apk / party.qwer.iris.Main
  ✅ /system/bin/app_process -cp Iris.apk / party.qwer.iris.Main
```

### 6. ashmem_linux는 커널 6.8+에서 불필요
```
커널 6.8+는 memfd를 사용하므로 ashmem_linux 모듈이 없어도 정상 동작.
binder_linux만 로드하면 됨.
```

### 7. 카카오톡 로그인 후 반드시 메시지 1회 송수신
```
Iris가 DB를 읽으려면 카카오톡이 DB를 초기화해야 함.
로그인만 하면 안 됨. 아무 채팅방에서 메시지 1번 보내고 1번 받아야 함.
```

### 8. irispy-client API (문서와 다름)
```python
# ❌ 잘못된 코드 (인터넷에 돌아다니는 예전 API)
from irispy import Iris, Message
app = Iris()
@app.on_message()
def handler(msg: Message):
    msg.reply("hello")
app.run(host="127.0.0.1", port=3000)

# ✅ 올바른 코드 (v0.2.4 기준)
from iris import Bot, ChatContext
bot = Bot("127.0.0.1:3000")
@bot.on_event("message")
def handler(chat: ChatContext):
    chat.reply("hello")
    # chat.message.msg    → 메시지 텍스트
    # chat.message.command → 첫 단어
    # chat.message.param   → 나머지 텍스트
    # chat.sender.name     → 보낸 사람 이름
    # chat.room.name       → 채팅방 이름
bot.run()
```

---

## Phase 1: macOS 준비 + UTM Ubuntu VM

### 1-1. macOS에 필요한 도구 설치
```bash
brew install --cask utm
brew install scrcpy android-platform-tools
```

### 1-2. Ubuntu ISO 다운로드

**주의**: 버전 번호가 자주 바뀜. 404 나면 cdimage.ubuntu.com에서 확인.
```bash
# 2026년 3월 기준 24.04.4
curl -L -O https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04.4-live-server-arm64.iso

# 404 나면 실제 존재하는 버전 확인:
curl -s https://cdimage.ubuntu.com/releases/24.04/release/ | grep -o 'ubuntu-24\.04\.[0-9]*-live-server-arm64\.iso' | head -1
```

### 1-3. UTM VM 생성
- 타입: **Virtualize** (반드시! Emulate 아님)
- OS: Linux
- 메모리: **8GB** (4GB는 부족함)
- CPU: **4코어** 이상
- 디스크: **64GB**
- 네트워크: **Shared Network**

### 1-4. 포트포워딩 (UTM VM 설정 → Network → Port Forward)
| 호스트 포트 | VM 포트 | 용도 |
|------------|---------|------|
| 2222 | 22 | SSH |
| 5555 | 5555 | ADB |
| 3000 | 3000 | Iris Dashboard |

### 1-5. Ubuntu 설치 후 기본 설정
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl wget vim build-essential openssh-server

# SSH 키 복사 (macOS에서)
ssh-copy-id -p 2222 유저명@localhost
# 또는 VM IP 직접 사용
ssh-copy-id 유저명@192.168.64.X
```

---

## Phase 2: Docker + 커널 모듈 (VM 내부)

### 2-1. Docker 설치
```bash
# 공식 GPG 키
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# 저장소 추가
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 설치
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# sudo 없이 사용
sudo usermod -aG docker $USER
newgrp docker
```

### 2-2. binder_linux 커널 모듈 로드
```bash
# linux-modules-extra 설치 (필수!)
sudo apt install -y linux-modules-extra-$(uname -r)

# 모듈 로드
sudo modprobe binder_linux devices="binder,hwbinder,vndbinder"

# 확인 (ashmem은 커널 6.8+에서 없어도 됨)
lsmod | grep binder_linux
ls -la /dev/binder*
```

**만약 `modprobe binder_linux` 실패 시:**
```bash
git clone https://github.com/remote-android/redroid-modules.git
cd redroid-modules
sudo apt install -y linux-headers-$(uname -r) kmod make gcc
sudo make && sudo make install
```

### 2-3. 부팅 시 자동 로드
```bash
sudo tee /etc/systemd/system/binder.service << 'EOF'
[Unit]
Description=Load binder kernel module
After=network-online.target

[Service]
Type=oneshot
ExecStart=/sbin/modprobe binder_linux devices="binder,hwbinder,vndbinder"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable binder.service
sudo systemctl start binder.service
```

---

## Phase 3: Redroid 컨테이너 (VM 내부)

### 3-1. Redroid 실행
```bash
# ⚠️ 반드시 14.0.0_64only-latest 사용!
docker run -itd --privileged \
    --name redroid \
    -v ~/redroid-data:/data \
    -p 5555:5555 \
    -p 3000:3000 \
    redroid/redroid:14.0.0_64only-latest \
    ro.product.model=SM-T970 \
    ro.product.brand=Samsung \
    androidboot.redroid_gpu_mode=guest
```

### 3-2. 부팅 확인 + ADB 연결
```bash
# ADB 설치
sudo apt install -y android-sdk-platform-tools

# 부팅 대기 (보통 10-20초)
sleep 20
adb connect localhost:5555
adb devices   # "localhost:5555 device" 나와야 함

# 부팅 확인
adb -s localhost:5555 shell getprop sys.boot_completed
# 1이면 부팅 완료
```

### 3-3. macOS에서 scrcpy 연결
```bash
# macOS에서 (VM IP 사용)
adb connect 192.168.64.X:5555
scrcpy -s 192.168.64.X:5555 --max-size=1024
```

---

## Phase 4: 카카오톡 + Termux 패치 및 설치

### 4-1. Hayul 준비 (VM 내부)
```bash
mkdir -p ~/hayul-workspace && cd ~/hayul-workspace
git clone https://github.com/ye-seola/Hayul.git
cd Hayul

# pip 설치 시 --break-system-packages 필수 (Ubuntu 24.04 PEP 668)
pip install lxml pyaxml pure-python-adb cryptography --break-system-packages

# JDK 설치 (apksigner용)
sudo apt install -y default-jdk

# Keystore 생성 (비밀번호 기억할 것)
keytool -genkey -v -keystore KEY.jks -keyalg RSA -keysize 2048 -validity 10000
```

### 4-2. Termux APK 다운로드
```bash
cd ~/hayul-workspace
curl -L -O https://github.com/termux/termux-app/releases/download/v0.118.1/termux-app_v0.118.1+github-debug_arm64-v8a.apk
mv termux-app_v0.118.1+github-debug_arm64-v8a.apk termux.apk
```

### 4-3. 카카오톡 APK 다운로드 (가장 중요한 단계!)

**Aptoide에서 base APK + arm64 split APK를 받아야 한다.**

방법 1: 브라우저로 직접 다운로드
```
1. https://kakaotalk-messenger.ko.aptoide.com/ 접속
2. base APK 다운로드 (~211MB)
3. arm64 split APK 다운로드 (~59MB, .so 파일 34개 포함)
```

방법 2: apkpure에서 XAPK도 받아서 config split 추출
```bash
# apkpure에서 XAPK 다운로드 후
unzip kakaotalk.xapk -d kakao_xapk/
# config.en.apk, config.mdpi.apk 추출
```

**필요한 파일 4개:**
| 파일 | 출처 | 크기 | 설명 |
|------|------|------|------|
| `kakao_base.apk` | Aptoide | ~211MB | 카카오톡 base APK |
| `kakao_arm64_split.apk` | Aptoide | ~59MB | arm64-v8a native libs |
| `config.en.apk` | apkpure XAPK | ~500KB | 언어 split |
| `config.mdpi.apk` | apkpure XAPK | ~3.8MB | 화면 밀도 split |

> **같은 버전(예: 26.2.2)을 맞춰야 한다!** 버전 불일치 시 설치 실패.

### 4-4. 먼저 패치 안 된 상태로 설치 (Hayul이 pull해서 패치하므로)
```bash
cd ~/hayul-workspace

# Termux 설치
adb -s localhost:5555 install termux.apk

# 카카오톡 설치 (4개 APK 동시에!)
adb -s localhost:5555 install-multiple \
  kakao_base.apk \
  kakao_arm64_split.apk \
  config.en.apk \
  config.mdpi.apk
```

**잘못된 조합으로 발생하는 에러들:**
| 시도 | 에러 | 원인 |
|------|------|------|
| base만 설치 | `INSTALL_FAILED_MISSING_SPLIT` | requiredSplitTypes에 abi,density 필수 |
| base + armeabi-v7a | `INSTALL_FAILED_NO_MATCHING_ABIS` | 64only는 32비트 lib 거부 |
| base + arm64만 | `INSTALL_FAILED_MISSING_SPLIT` | density split도 필수 |
| base + arm64 + en + mdpi | **Success** | 올바른 조합 |

### 4-5. Hayul로 패치 (sharedUserId 추가)
```bash
cd ~/hayul-workspace/Hayul

# 카카오톡 패치 (프롬프트에 패키지명 입력)
echo 'com.kakao.talk' | python3 main.py
# → patched-com.kakao.talk-YYYYMMDDHHMMSS 폴더 생성

# Termux 패치
echo 'com.termux' | python3 main.py
# → patched-com.termux-YYYYMMDDHHMMSS 폴더 생성
```

### 4-6. 기존 앱 삭제 후 패치 버전 설치
```bash
# 기존 앱 삭제
adb -s localhost:5555 shell pm uninstall com.kakao.talk
adb -s localhost:5555 shell pm uninstall com.termux

# 패치된 카카오톡 설치 (split APK 전부 포함!)
cd patched-com.kakao.talk-*/
adb -s localhost:5555 install-multiple \
  patched-aligned.apk \
  split_config.arm64_v8a-aligned.apk \
  split_config.en-aligned.apk \
  split_config.mdpi-aligned.apk

# 패치된 Termux 설치
cd ../patched-com.termux-*/
adb -s localhost:5555 install patched-aligned.apk
```

### 4-7. 카카오톡 로그인 (수동)
```bash
# 카카오톡 실행
adb -s localhost:5555 shell am start -n com.kakao.talk/.activity.SplashActivity

# scrcpy로 화면 보면서 로그인
# macOS에서:
scrcpy -s 192.168.64.X:5555
```

**로그인 후 반드시:**
1. 아무 채팅방에서 메시지 1번 보내기
2. 다른 사람에게 메시지 1번 받기
3. (DB 초기화, 이거 안 하면 Iris가 DB 못 읽음)

---

## Phase 5: Iris 설치 (Redroid Termux 내부)

### 5-1. Termux 실행 및 초기화
```bash
adb -s localhost:5555 shell am start -n com.termux/.HomeActivity
# 첫 실행 시 bootstrap 패키지 설치에 30초~1분 소요
# run-as로 확인:
adb -s localhost:5555 shell run-as com.termux ls /data/data/com.termux/files/usr/bin/bash
```

### 5-2. 환경변수 설정 (adb shell input text 사용)
```bash
# Termux가 포그라운드에 있는 상태에서 (scrcpy로 확인)
adb -s localhost:5555 shell "input text 'echo%sexport%sIRIS_CONFIG_PATH=/data/data/com.termux/files/home/config.json%s>%s~/.bashrc' && input keyevent 66"
sleep 2
adb -s localhost:5555 shell "input text 'echo%sexport%sIRIS_RUNNER=com.termux%s>>%s~/.bashrc' && input keyevent 66"
sleep 2
adb -s localhost:5555 shell "input text 'source%s~/.bashrc' && input keyevent 66"
```

> `input text`에서 `%s`는 스페이스를 의미. 특수문자가 많은 긴 명령은 실패할 수 있음.

### 5-3. Iris 다운로드
```bash
adb -s localhost:5555 shell "input text 'curl%s-L%s-O%shttps://github.com/dolidolih/Iris/releases/latest/download/Iris.apk' && input keyevent 66"
# 다운로드 완료까지 10-15초 대기
```

### 5-4. Iris.apk 읽기 전용으로 변경 (필수!)
```bash
# ⚠️ 이거 안 하면 Android 14에서 "Writable dex file not allowed" 에러로 크래시
adb -s localhost:5555 shell "run-as com.termux /data/data/com.termux/files/usr/bin/bash -c 'chmod 444 /data/data/com.termux/files/home/Iris.apk'"
```

### 5-5. Iris 시작 스크립트 생성 + 실행

**파일 쓰기 팁**: `run-as com.termux`에서 `/sdcard/` 접근 불가. `printf`를 통해 직접 쓰기.

```bash
# 시작 스크립트 생성
adb -s localhost:5555 shell "run-as com.termux /data/data/com.termux/files/usr/bin/bash -c \"printf '#!/data/data/com.termux/files/usr/bin/bash\nexport IRIS_CONFIG_PATH=/data/data/com.termux/files/home/config.json\nexport IRIS_RUNNER=com.termux\ncd /data/data/com.termux/files/home\n/system/bin/app_process -cp Iris.apk / party.qwer.iris.Main\n' > /data/data/com.termux/files/home/iris_start.sh && chmod +x /data/data/com.termux/files/home/iris_start.sh\""

# Iris 실행 (Termux 포그라운드에서)
adb -s localhost:5555 shell "input text 'nohup%s~/iris_start.sh%s>%s~/iris.log%s2>&1%s&' && input keyevent 66"
```

### 5-6. Iris 정상 동작 확인
```bash
# 프로세스 확인
adb -s localhost:5555 shell 'ps -A | grep app_process'

# 로그 확인 (아래 내용이 나와야 정상)
adb -s localhost:5555 shell "run-as com.termux /data/data/com.termux/files/usr/bin/cat /data/data/com.termux/files/home/iris.log"
# 정상 출력:
#   Returning defaultPath: /data/data/com.kakao.talk/
#   Bot user_id is detected: XXXXXXX
#   DB Polling thread started.
#   DBObserver started

# 대시보드 확인 (VM에서)
curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/dashboard
# 200이면 정상
```

**Iris 크래시 시 체크리스트:**
| 에러 | 해결 |
|------|------|
| `Writable dex file not allowed` | `chmod 444 Iris.apk` |
| `app_process: inaccessible or not found` | 전체 경로 `/system/bin/app_process` 사용 |
| `Aborted (core dumped)` | 위 두 가지 모두 확인 |
| DB 관련 에러 | 카카오톡에서 메시지 송수신 1회 필요 |

---

## Phase 6: IrisPy 봇 (Redroid Termux proot Ubuntu)

### 6-1. proot-distro 설치
```bash
# Termux 포그라운드에서
adb -s localhost:5555 shell "input text 'pkg%sinstall%sproot-distro%s-y' && input keyevent 66"
# 30초 대기
```

### 6-2. Ubuntu 설치
```bash
adb -s localhost:5555 shell "input text 'proot-distro%sinstall%subuntu' && input keyevent 66"
# 1-2분 대기
```

### 6-3. Python + irispy-client 설치

**방법 A: 스크립트를 직접 proot 파일시스템에 쓰고 실행** (권장)
```bash
# setup 스크립트 생성
adb -s localhost:5555 shell "run-as com.termux /data/data/com.termux/files/usr/bin/bash -c \"printf '#!/bin/bash\napt update -y\napt install -y python3 python3-pip python3-venv\nmkdir -p /root/ipy2\ncd /root/ipy2\npython3 -m venv venv\n. venv/bin/activate\npip install irispy-client\necho IRISPY_DONE\n' > /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/tmp/setup.sh && chmod +x /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/tmp/setup.sh\""

# Termux에서 실행
adb -s localhost:5555 shell "input text 'proot-distro%slogin%subuntu%s--%s/tmp/setup.sh' && input keyevent 66"
# 2-3분 대기
```

### 6-4. 봇 코드 배포

**base64 방식으로 파일 전송** (가장 안정적):
```bash
# macOS에서 봇 코드를 base64로 인코딩하여 전송
BOT_B64=$(base64 < bot/irispy.py)
ssh 유저명@VM_IP "adb -s localhost:5555 shell \"run-as com.termux /data/data/com.termux/files/usr/bin/bash -c 'echo $BOT_B64 | base64 -d > /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root/ipy2/irispy.py'\""
```

### 6-5. 봇 실행
```bash
# run-as를 통해 직접 실행 (가장 안정적인 방법)
adb -s localhost:5555 shell "run-as com.termux /data/data/com.termux/files/usr/bin/bash -c 'export PATH=/data/data/com.termux/files/usr/bin:\$PATH && export HOME=/data/data/com.termux/files/home && export TMPDIR=/data/data/com.termux/files/usr/tmp && export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib && export IRIS_CONFIG_PATH=/data/data/com.termux/files/home/config.json && export IRIS_RUNNER=com.termux && nohup proot-distro login ubuntu -- bash -c \"cd /root/ipy2 && source venv/bin/activate && python irispy.py\" > /data/data/com.termux/files/home/bot.log 2>&1 &'"
```

### 6-6. 봇 동작 확인
```bash
# 로그 확인
adb -s localhost:5555 shell "run-as com.termux /data/data/com.termux/files/usr/bin/cat /data/data/com.termux/files/home/bot.log"
# 정상 출력:
#   봇 시작: 127.0.0.1:3000
#   웹소켓에 연결되었습니다
#   [채팅방이름] 보낸사람: 메시지내용
```

---

## Phase 7: 검증

```bash
# 1. Docker 상태
docker ps | grep redroid                    # Up 확인

# 2. 커널 모듈
lsmod | grep binder_linux                  # 로드 확인

# 3. ADB
adb -s localhost:5555 shell getprop sys.boot_completed  # 1

# 4. 앱 설치
adb -s localhost:5555 shell pm list packages | grep -E "kakao|termux"
# package:com.kakao.talk
# package:com.termux

# 5. Iris 프로세스
adb -s localhost:5555 shell 'ps -A | grep app_process'  # 2개 이상

# 6. Iris 대시보드
curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/dashboard  # 200

# 7. 카카오톡에서 /ping 보내서 pong! 응답 확인
```

---

## Iris API 활용

### 메시지 보내기
```bash
curl -X POST http://localhost:3000/reply \
  -H "Content-Type: application/json" \
  -d '{"type":"text","room":"채팅방ID","data":"보낼 메시지"}'
```

### 채팅방 목록 조회
```bash
curl -X POST http://localhost:3000/query \
  -H "Content-Type: application/json" \
  -d '{"query":"SELECT id, active_members_count FROM chat_rooms ORDER BY last_log_id DESC LIMIT 10","bind":[]}'
```

### 친구 목록 조회
```bash
curl -X POST http://localhost:3000/query \
  -H "Content-Type: application/json" \
  -d '{"query":"SELECT id, name FROM db2.friends LIMIT 20","bind":[]}'
```

---

## 시도하고 실패한 것들 (하지 마라)

| 시도 | 결과 | 이유 |
|------|------|------|
| 32+64bit Redroid 이미지 | 부팅 안됨 | Apple Silicon 미지원 |
| armeabi-v7a → arm64-v8a 폴더명만 변경 | 크래시 | 32비트 바이너리는 64비트에서 실행 불가 |
| APK에서 requiredSplitTypes만 제거 | 크래시 | native lib 없이는 실행 불가 |
| base APK만 단독 설치 | MISSING_SPLIT | Android 강제 split 요구 |
| ro.product.cpu.abilist 오버라이드 | 부팅 안됨 | 64only 커널에서 32비트 실행 불가 |
| apkpure에서 arm64 APK 다운 | 없음 | armeabi-v7a만 제공 |
| APKMirror 직접 다운로드 | 403 | 다운로드 보호됨 |

---

## adb shell에서 Termux 파일 다루기 팁

```bash
# 1. run-as com.termux로 Termux 유저 컨텍스트 사용
adb shell "run-as com.termux /data/data/com.termux/files/usr/bin/bash -c 'echo hello'"

# 2. /sdcard/는 run-as에서 접근 불가 (Permission denied)
#    → printf나 base64로 직접 쓰기

# 3. 파일 전송: macOS → VM → base64 → run-as로 쓰기
BOT_B64=$(base64 < file.txt)
adb shell "run-as com.termux /data/data/com.termux/files/usr/bin/bash -c 'echo $BOT_B64 | base64 -d > /path/to/file'"

# 4. proot Ubuntu 파일시스템 경로
/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/

# 5. input text에서 스페이스는 %s로 치환
adb shell "input text 'hello%sworld' && input keyevent 66"
```

---

## 다중 계정 운영

VM 1개에서 여러 Redroid 컨테이너 실행 가능:
```bash
# 두 번째 계정
docker run -itd --privileged --name redroid2 \
    -v ~/redroid-data2:/data \
    -p 5556:5555 -p 3001:3000 \
    redroid/redroid:14.0.0_64only-latest \
    ro.product.model=SM-T970 ro.product.brand=Samsung \
    androidboot.redroid_gpu_mode=guest

adb connect localhost:5556
```
각 컨테이너에 동일한 Phase 4-6 반복.
