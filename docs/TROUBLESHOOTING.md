# 트러블슈팅 가이드

## 커널 모듈 관련

### `/dev/binder` 디바이스가 없음
```bash
# 1. 모듈 로드
sudo modprobe binder_linux devices="binder,hwbinder,vndbinder"
sudo modprobe ashmem_linux

# 2. 확인
lsmod | grep -e ashmem_linux -e binder_linux
ls -la /dev/binder* /dev/ashmem

# 3. linux-modules-extra 확인
dpkg -l | grep linux-modules-extra
sudo apt install -y linux-modules-extra-$(uname -r)

# 4. 직접 빌드 (위 방법이 안 될 경우)
git clone https://github.com/remote-android/redroid-modules.git
cd redroid-modules
sudo apt install -y linux-headers-$(uname -r) kmod make gcc
sudo make && sudo make install
```

## Docker / Redroid 관련

### Redroid 컨테이너가 반복 종료됨
```bash
# 로그 확인
docker logs redroid

# 커널 모듈 로드 상태 확인
lsmod | grep binder

# 컨테이너 삭제 후 재생성
docker rm -f redroid
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

### Docker 권한 오류
```bash
sudo usermod -aG docker $USER
newgrp docker
# 또는 재로그인
```

## ADB 관련

### ADB 연결 불가
```bash
# Redroid 컨테이너 상태 확인
docker ps | grep redroid

# ADB 서버 재시작
adb kill-server
adb start-server
adb connect localhost:5555

# 포트 확인
ss -tlnp | grep 5555
```

### macOS에서 ADB 연결 안됨
```bash
# UTM 포트포워딩 확인
# VM 설정 → Network → Port Forward
# Host 5555 → Guest 5555

# VM IP로 직접 연결
adb connect <VM_IP>:5555
```

## 카카오톡 관련

### 카카오톡 DB 접근 불가
```bash
# Redroid 내부에서 (adb shell 또는 Termux)
chmod -R 777 /data/data/com.kakao.talk/databases
```

### 카카오톡 실행 후 Iris가 메시지를 감지하지 못함
1. 카카오톡으로 메시지를 한 번 보내세요 (DB 초기화)
2. 다른 사람에게 메시지를 한 번 받으세요
3. Iris를 재시작하세요

## Iris 관련

### Iris 실행 방법 (중요!)

**반드시 `adb shell`로 실행해야 함. `docker exec`는 Android 환경변수가 없어서 `app_process`가 즉시 종료됨.**

```bash
# 1) adb 연결 및 root 전환
adb connect localhost:5555
adb -s localhost:5555 root
# "restarting adbd as root" 출력 확인

# 2) config.json 작성 (base64로! 직접 echo하면 따옴표 깨짐)
CONFIG_B64=$(echo -n '{"botName":"Iris","botHttpPort":3000,"webServerEndpoint":"","dbPollingRate":100,"messageSendRate":50,"botId":395836651}' | base64 -w0)
docker exec redroid sh -c "echo '$CONFIG_B64' | base64 -d > /data/local/tmp/config.json"

# 3) Iris 실행 (root로, 백그라운드)
adb -s localhost:5555 shell "nohup sh -c 'CLASSPATH=/data/local/tmp/Iris.apk \
  IRIS_CONFIG_PATH=/data/data/com.termux/files/home/config.json \
  IRIS_RUNNER=com.termux \
  app_process / party.qwer.iris.Main \
  > /data/local/tmp/iris.log 2>&1' &"

# 4) 확인 (5초 대기 후)
sleep 5
docker exec redroid ps -ef | grep app_process | grep -v grep
docker exec redroid ss -tlnp | grep 3000
docker exec redroid cat /data/local/tmp/iris.log | tail -10
```

### Iris 실행이 안 되는 경우 체크리스트

| 증상 | 원인 | 해결 |
|------|------|------|
| app_process 즉시 종료 (exit 0) | `docker exec`로 실행 | `adb shell`로 실행 |
| app_process 즉시 종료 (exit 0) | config.json 깨짐 (따옴표 없음) | base64로 config 다시 작성 |
| "ANDROID_DATA unset" 크래시 | CLASSPATH 환경변수 없음 | `CLASSPATH=Iris.apk` 추가 |
| Port 3000 안 열림 | Iris 프로세스 죽음 | `iris.log` 확인, 재시작 |
| DB 접근 오류 | KakaoTalk 미실행/미초기화 | 카톡으로 메시지 1회 송수신 |

### config.json 깨짐 확인
```bash
# 정상: {"botName":"Iris",...}  (따옴표 있음)
# 비정상: {botName:Iris,...}    (따옴표 없음)
docker exec redroid run-as com.termux cat /data/data/com.termux/files/home/config.json
```

### Iris 대시보드 접근 불가
```bash
# VM에서 확인
curl http://localhost:3000/dashboard

# macOS에서 접근하려면 UTM 포트포워딩 필요
# Host 3000 → Guest 3000
```

---

## /그림 (이미지 전송) 디버깅 기록

### 문제 요약
`/그림` 명령어로 AI 이미지 생성 후 카카오톡에 전송되지 않는 문제. 총 3단계 버그가 있었음.

### 버그 1: base64 문자열을 str로 전달
- **증상**: `/그림` 명령어 후 아무 반응 없음
- **원인**: `bot.api.reply_media(files=[img_b64])` — base64 문자열(str)을 직접 전달
- **IrisPy 동작**: str 타입 → 파일경로/URL로 해석 → `open()` 시도 → 실패
- **수정**: base64 디코딩 후 bytes로 전달
```python
# Before (잘못됨)
bot.api.reply_media(room_id=chat.room.id, files=[img_b64])

# After (정상)
img_bytes = base64.b64decode(img_b64)
bot.api.reply_media(room_id=chat.room.id, files=[img_bytes])
```

### 버그 2: 짧은 프롬프트로 이미지 미생성
- **증상**: "이미지 생성에 실패했습니다" 에러
- **원인**: 한글 프롬프트 "고양이"만 보내면 Gemini API가 텍스트만 반환 (608 bytes)
- **수정**: 영어 프리픽스 추가 + 타임아웃 증가
```python
full_prompt = f"Generate an image of: {prompt}"  # 영어 접두사
# timeout 30s → 120s
```

### 버그 3: FUSE Permission Denied (핵심 문제)
- **증상**: API 성공, 이미지 생성됨, 하지만 카톡에 안 보임
- **Iris 로그**: `java.io.FileNotFoundException: /sdcard/Android/data/com.kakao.talk/files/xxx.png: EACCES (Permission denied)`
- **원인**: Android 14 FUSE Scoped Storage
  - Iris가 이미지를 `/sdcard/Android/data/com.kakao.talk/files/`에 임시저장 후 카톡으로 전송
  - `run-as com.termux`로 실행 시 per-app mount namespace 생성 → FUSE가 cross-package 쓰기 차단
  - com.termux와 com.kakao.talk이 같은 UID(10090)여도 FUSE가 프로세스별로 패키지 확인

#### 시도했으나 실패한 방법들
| 방법 | 왜 안 됐나 |
|------|-----------|
| `chmod 777` 디렉토리 | FUSE가 파일시스템 권한 무시 |
| `appops MANAGE_EXTERNAL_STORAGE` | Redroid에서 효과 없음 |
| bind mount (ext4 → FUSE 경로) | `run-as`가 새 mount namespace 생성하므로 무효 |
| `nsenter` mount namespace 진입 | mount는 보이지만 FUSE 여전히 차단 |
| Global FUSE umount + ext4 remount | `run-as`가 매번 FUSE 재생성 |
| `docker exec --user 10090` | `app_process`가 Android 환경 없이 즉시 종료 |
| Iris config `imageDirPath` | Iris가 무시 (DEX에 경로 하드코딩) |

#### 최종 해결: root로 Iris 실행
```bash
# 1) adb root (ADB 데몬을 root로 재시작)
adb -s localhost:5555 root

# 2) root shell에서 Iris 시작
adb -s localhost:5555 shell "nohup sh -c 'CLASSPATH=/data/local/tmp/Iris.apk \
  IRIS_CONFIG_PATH=/data/data/com.termux/files/home/config.json \
  IRIS_RUNNER=com.termux \
  app_process / party.qwer.iris.Main' &"

# root는 FUSE 제한을 받지 않음 → 이미지 쓰기 성공
```

#### 핵심 교훈
1. **`docker exec` ≠ `adb shell`**: Android 환경변수 차이로 `app_process` 동작이 다름
2. **`run-as`는 mount namespace 격리**: 어떤 mount 조작도 `run-as`가 새 namespace 만들면 무효
3. **root가 가장 단순한 해결**: iris_control 공식 스크립트도 `su root`로 실행
4. **config.json 쉘 이스케이핑 주의**: `echo '{...}'`로 JSON 쓰면 따옴표 깨짐 → base64 사용

## scrcpy 관련

### scrcpy 화면이 안 보임
```bash
# ADB 연결 먼저 확인
adb devices

# SSH X11 forwarding으로 시도
ssh -X -p 2222 user@localhost
scrcpy -s localhost:5555

# macOS에서 직접 (포트포워딩 필요)
scrcpy -s localhost:5555 --max-size=1024
```

## UTM / VM 관련

### VM이 느림
- Memory를 8GB 이상으로 설정
- CPU 코어를 4개 이상으로 설정
- 불필요한 macOS 앱 종료

### VM 네트워크 안됨
- UTM 네트워크 모드: Shared Network (NAT)
- VM 내부에서: `ip addr show`
- DNS 확인: `cat /etc/resolv.conf`
