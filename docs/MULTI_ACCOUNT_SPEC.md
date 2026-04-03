# 다중 카카오톡 계정 관리 플랫폼 스펙

## 개요

맥미니를 서버로 사용하여 여러 카카오톡 계정을 동시에 관리하는 플랫폼.
REST API + 웹 대시보드를 통해 메시지 발송, 수신 모니터링, 전체 동시 발송 가능.

---

## 전체 아키텍처

```
인터넷 / 로컬 네트워크
  │
  ▼
맥미니 (Apple Silicon, 상시 가동)
  │
  ├── 포트포워딩 (공유기)
  │     8000 → API 서버
  │     8080 → 웹 대시보드
  │
  └── UTM Ubuntu ARM64 VM (메모리 16GB+, CPU 6코어+, 디스크 200GB+)
        │
        ├── API 서버 (FastAPI, :8000)
        │     - 모든 Iris 인스턴스를 프록시
        │     - 인증 (API Key)
        │     - 계정/채팅방/메시지 관리
        │
        ├── 웹 대시보드 (Nginx + 정적 파일, :8080)
        │     - 계정 목록, 채팅방 목록, 메시지 뷰어
        │     - 메시지 발송 UI
        │     - 전체 동시 발송
        │
        ├── Docker Engine
        │     │
        │     ├── redroid-1 (카톡 계정 #1)
        │     │     ├── 포트: 5555 (ADB), 3000 (Iris)
        │     │     ├── 볼륨: ~/redroid-data-1:/data
        │     │     ├── 패치된 KakaoTalk + Termux
        │     │     ├── Iris (DB Observer + REST API + WebSocket)
        │     │     └── IrisPy 봇 (선택)
        │     │
        │     ├── redroid-2 (카톡 계정 #2)
        │     │     ├── 포트: 5556 (ADB), 3001 (Iris)
        │     │     ├── 볼륨: ~/redroid-data-2:/data
        │     │     └── ... (동일 구조)
        │     │
        │     ├── redroid-3 (카톡 계정 #3)
        │     │     ├── 포트: 5557 (ADB), 3002 (Iris)
        │     │     └── ...
        │     │
        │     └── redroid-N
        │           ├── 포트: 5554+N (ADB), 2999+N (Iris)
        │           └── ...
        │
        └── binder_linux 커널 모듈 (systemd 자동 로드)
```

---

## 하드웨어 요구사항

### 맥미니 권장 사양

| 항목 | 최소 | 권장 |
|------|------|------|
| 칩 | M1 | M2 Pro / M4 Pro |
| 메모리 | 16GB (계정 3개) | 32GB (계정 10개+) |
| 저장소 | 256GB | 512GB+ |
| 네트워크 | 유선 LAN | 유선 LAN (고정 IP 권장) |

### 계정당 리소스 사용량 (추정)

| 항목 | 사용량 |
|------|--------|
| RAM | ~1.5GB (Redroid + Iris + 봇) |
| 디스크 | ~5GB (Redroid 이미지 공유, 데이터만 분리) |
| CPU | 유휴 시 거의 0, 메시지 처리 시 0.5코어 |

### 동시 운영 가능 계정 수 추정

| 맥미니 메모리 | VM 할당 | 계정 수 |
|--------------|---------|---------|
| 16GB | 12GB | 3~5개 |
| 32GB | 24GB | 10~15개 |
| 64GB | 48GB | 25~30개 |

---

## UTM VM 설정

```
타입: Virtualize (Apple Hypervisor)
OS: Ubuntu 24.04 LTS ARM64 Server
메모리: 호스트의 75% (예: 32GB 맥 → 24GB VM)
CPU: 호스트 코어 - 2 (예: 10코어 맥 → 8코어 VM)
디스크: 200GB+
네트워크: Bridged (VM이 공유기에서 직접 IP 받음) 또는 Shared + 포트포워딩
```

### 네트워크 모드 선택

| 모드 | 장점 | 단점 | 권장 |
|------|------|------|------|
| Bridged | VM이 독립 IP, 포트포워딩 불필요 | 공유기 설정 필요 | 서버용 권장 |
| Shared (NAT) | 설정 간단 | UTM 포트포워딩 필요 | 테스트용 |

### Bridged 모드 포트포워딩 (공유기)

| 외부 포트 | VM 포트 | 용도 |
|-----------|---------|------|
| 8000 | 8000 | API 서버 |
| 8080 | 8080 | 웹 대시보드 |
| 2222 | 22 | SSH (관리용, 선택) |

---

## Docker 컨테이너 구성

### docker-compose.yml

```yaml
version: "3.8"

services:
  redroid-1:
    image: redroid/redroid:14.0.0_64only-latest
    container_name: redroid-1
    privileged: true
    ports:
      - "5555:5555"
      - "3000:3000"
    volumes:
      - ./data/redroid-1:/data
    command:
      - ro.product.model=SM-T970
      - ro.product.brand=Samsung
      - androidboot.redroid_gpu_mode=guest

  redroid-2:
    image: redroid/redroid:14.0.0_64only-latest
    container_name: redroid-2
    privileged: true
    ports:
      - "5556:5555"
      - "3001:3000"
    volumes:
      - ./data/redroid-2:/data
    command:
      - ro.product.model=SM-T970
      - ro.product.brand=Samsung
      - androidboot.redroid_gpu_mode=guest

  redroid-3:
    image: redroid/redroid:14.0.0_64only-latest
    container_name: redroid-3
    privileged: true
    ports:
      - "5557:5555"
      - "3002:3000"
    volumes:
      - ./data/redroid-3:/data
    command:
      - ro.product.model=SM-T970
      - ro.product.brand=Samsung
      - androidboot.redroid_gpu_mode=guest

  # 계정 추가 시 redroid-N 복사, 포트만 변경
  # ADB: 5554+N, Iris: 2999+N
```

### 컨테이너 추가 자동화 스크립트

```bash
#!/bin/bash
# add_account.sh <번호>
# 예: ./add_account.sh 4

N=$1
ADB_PORT=$((5554 + N))
IRIS_PORT=$((2999 + N))

docker run -itd --privileged \
    --name redroid-$N \
    -v ./data/redroid-$N:/data \
    -p $ADB_PORT:5555 \
    -p $IRIS_PORT:3000 \
    redroid/redroid:14.0.0_64only-latest \
    ro.product.model=SM-T970 \
    ro.product.brand=Samsung \
    androidboot.redroid_gpu_mode=guest

echo "계정 #$N 생성 완료"
echo "  ADB: localhost:$ADB_PORT"
echo "  Iris: http://localhost:$IRIS_PORT/dashboard"
```

---

## API 서버 스펙

### 기술 스택

- **프레임워크**: FastAPI (Python 3.12+)
- **비동기 HTTP**: httpx (각 Iris에 비동기 프록시)
- **인증**: API Key (헤더: `X-API-Key`)
- **데이터**: accounts.json (계정 설정 파일)
- **프로세스 관리**: systemd 서비스

### 설정 파일: accounts.json

```json
{
  "accounts": [
    {
      "id": "account-1",
      "name": "마케팅봇",
      "phone": "010-1234-5678",
      "iris_url": "http://localhost:3000",
      "adb_port": 5555,
      "status": "active"
    },
    {
      "id": "account-2",
      "name": "고객응대봇",
      "phone": "010-9876-5432",
      "iris_url": "http://localhost:3001",
      "adb_port": 5556,
      "status": "active"
    }
  ],
  "api_key": "your-secret-api-key-here"
}
```

### API 엔드포인트

#### 계정 관리

| 메서드 | 경로 | 설명 |
|--------|------|------|
| `GET` | `/api/accounts` | 전체 계정 목록 + 상태 |
| `GET` | `/api/accounts/{id}` | 특정 계정 상세 정보 |
| `GET` | `/api/accounts/{id}/status` | Iris 연결 상태, 카카오톡 상태 |

#### 채팅방

| 메서드 | 경로 | 설명 |
|--------|------|------|
| `GET` | `/api/accounts/{id}/rooms` | 채팅방 목록 (최근 활성순) |
| `GET` | `/api/accounts/{id}/rooms/{room_id}` | 채팅방 상세 (멤버, 타입) |

#### 친구/유저

| 메서드 | 경로 | 설명 |
|--------|------|------|
| `GET` | `/api/accounts/{id}/friends` | 친구 목록 |

#### 메시지

| 메서드 | 경로 | 설명 |
|--------|------|------|
| `POST` | `/api/send` | 단일 메시지 발송 |
| `POST` | `/api/broadcast` | 여러 계정에서 동시 발송 |
| `GET` | `/api/accounts/{id}/messages` | 최근 수신 메시지 |

#### 시스템

| 메서드 | 경로 | 설명 |
|--------|------|------|
| `GET` | `/api/health` | 전체 시스템 상태 |
| `POST` | `/api/accounts/{id}/restart` | Iris/봇 재시작 |

### 요청/응답 예시

#### 메시지 발송
```
POST /api/send
X-API-Key: your-secret-api-key

{
  "account_id": "account-1",
  "room_id": "18398338829933617",
  "message": "안녕하세요!"
}
```
```json
{
  "success": true,
  "account_id": "account-1",
  "room_id": "18398338829933617"
}
```

#### 동시 발송 (모든 계정의 특정 방에)
```
POST /api/broadcast
X-API-Key: your-secret-api-key

{
  "account_ids": ["account-1", "account-2", "account-3"],
  "room_id": "18398338829933617",
  "message": "전체 공지입니다."
}
```
```json
{
  "success": true,
  "results": [
    {"account_id": "account-1", "success": true},
    {"account_id": "account-2", "success": true},
    {"account_id": "account-3", "success": false, "error": "Iris 연결 실패"}
  ]
}
```

#### 계정 목록 조회
```
GET /api/accounts
X-API-Key: your-secret-api-key
```
```json
{
  "accounts": [
    {
      "id": "account-1",
      "name": "마케팅봇",
      "phone": "010-1234-5678",
      "status": "active",
      "iris_status": "connected",
      "last_message_at": "2026-03-21T15:30:00Z"
    }
  ]
}
```

#### 채팅방 목록
```
GET /api/accounts/account-1/rooms?limit=20
X-API-Key: your-secret-api-key
```
```json
{
  "rooms": [
    {
      "id": "18398338829933617",
      "member_count": 496,
      "type": "group",
      "last_message_at": "2026-03-21T15:30:00Z"
    }
  ]
}
```

### API 서버 내부 동작

```python
# API 서버가 Iris에 프록시하는 방식 (핵심 로직)

import httpx

async def send_message(iris_url: str, room_id: str, message: str):
    """Iris의 /reply 엔드포인트에 프록시"""
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            f"{iris_url}/reply",
            json={"type": "text", "room": room_id, "data": message}
        )
        return resp.json()

async def query_db(iris_url: str, sql: str, bind: list = []):
    """Iris의 /query 엔드포인트에 프록시"""
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            f"{iris_url}/query",
            json={"query": sql, "bind": bind}
        )
        return resp.json()

async def get_rooms(iris_url: str):
    """채팅방 목록 조회"""
    return await query_db(
        iris_url,
        "SELECT id, active_members_count, last_log_id FROM chat_rooms ORDER BY last_log_id DESC LIMIT 50"
    )

async def get_friends(iris_url: str):
    """친구 목록 조회"""
    return await query_db(
        iris_url,
        "SELECT id, name, enc FROM db2.friends"
    )

async def broadcast(accounts: list, room_id: str, message: str):
    """여러 계정에서 동시 발송"""
    import asyncio
    tasks = [
        send_message(acc["iris_url"], room_id, message)
        for acc in accounts
    ]
    return await asyncio.gather(*tasks, return_exceptions=True)
```

---

## 웹 대시보드 스펙

### 기술 스택

- **프론트엔드**: 순수 HTML + CSS + JavaScript (빌드 도구 없음)
- **또는**: React / Vue (선택)
- **HTTP**: fetch API → API 서버
- **실시간**: WebSocket (각 Iris의 /ws에 연결하여 실시간 메시지 수신)
- **서빙**: Nginx 또는 Python http.server

### 페이지 구성

#### 1. 메인 대시보드 (`/`)
```
┌─────────────────────────────────────────────────┐
│  카카오톡 관리 대시보드                    [설정] │
├─────────────────────────────────────────────────┤
│                                                 │
│  계정 목록                                       │
│  ┌──────────┬──────────┬──────────┐             │
│  │ 마케팅봇  │ 고객응대봇│ CS봇     │             │
│  │ 🟢 활성   │ 🟢 활성   │ 🔴 오프라인│            │
│  │ 방 23개   │ 방 15개   │ 방 8개   │             │
│  │ 친구 142  │ 친구 89   │ 친구 56  │             │
│  └──────────┴──────────┴──────────┘             │
│                                                 │
│  빠른 전송                                       │
│  ┌─────────────────────────────────────────┐    │
│  │ 계정: [전체 ▼]  방: [방 선택 ▼]          │    │
│  │ 메시지: [____________________________]  │    │
│  │                              [전송]      │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  실시간 메시지 피드                               │
│  ┌─────────────────────────────────────────┐    │
│  │ 15:30 [마케팅봇] 오픈채팅방1 > 김철수: 안녕  │    │
│  │ 15:30 [고객응대봇] 1:1 > 이영희: 문의합니다  │    │
│  │ 15:29 [마케팅봇] 오픈채팅방2 > 박지민: ㅋㅋ  │    │
│  └─────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
```

#### 2. 계정 상세 (`/account/{id}`)
```
┌─────────────────────────────────────────────────┐
│  ← 마케팅봇 (010-1234-5678)          [Iris 대시보드]│
├─────────────────────────────────────────────────┤
│                                                 │
│  채팅방 목록                         [검색: ___] │
│  ┌──────────────────────────────┬──────┬──────┐ │
│  │ 채팅방 이름                   │ 인원 │ 최근 │ │
│  ├──────────────────────────────┼──────┼──────┤ │
│  │ 카톡봇 개발 커뮤니티           │ 496  │ 1분  │ │
│  │ 프로젝트A 그룹                │ 9    │ 5분  │ │
│  │ 장순필                       │ 2    │ 1시간│ │
│  └──────────────────────────────┴──────┴──────┘ │
│                                                 │
│  선택한 방: 카톡봇 개발 커뮤니티                    │
│  ┌─────────────────────────────────────────┐    │
│  │ 실시간 메시지                             │    │
│  │ 재현: 내 세금 터짐?                       │    │
│  │ 뱀비: 아님여친이랑있음?                    │    │
│  │                                         │    │
│  │ [메시지 입력 _______________] [전송]      │    │
│  └─────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
```

#### 3. 전체 발송 (`/broadcast`)
```
┌─────────────────────────────────────────────────┐
│  전체 동시 발송                                   │
├─────────────────────────────────────────────────┤
│                                                 │
│  발송 계정 선택:                                  │
│  ☑ 마케팅봇  ☑ 고객응대봇  ☐ CS봇 (오프라인)      │
│                                                 │
│  대상 방:                                        │
│  ○ 특정 방 ID: [________________]               │
│  ○ 모든 1:1 채팅방                               │
│  ○ 모든 그룹 채팅방                               │
│                                                 │
│  메시지:                                         │
│  ┌─────────────────────────────────────────┐    │
│  │                                         │    │
│  │                                         │    │
│  └─────────────────────────────────────────┘    │
│                                                 │
│  [미리보기]  [전송]                               │
│                                                 │
│  발송 결과:                                       │
│  ✅ 마케팅봇 → 성공                               │
│  ✅ 고객응대봇 → 성공                              │
└─────────────────────────────────────────────────┘
```

### 실시간 메시지 수신 (WebSocket)

```javascript
// 각 Iris 인스턴스의 WebSocket에 동시 연결
const accounts = [
  { id: "account-1", name: "마케팅봇", wsUrl: "ws://localhost:3000/ws" },
  { id: "account-2", name: "고객응대봇", wsUrl: "ws://localhost:3001/ws" },
];

accounts.forEach(account => {
  const ws = new WebSocket(account.wsUrl);
  ws.onmessage = (event) => {
    const data = JSON.parse(event.data);
    addToFeed(account.name, data);
  };
  ws.onclose = () => {
    // 3초 후 재연결
    setTimeout(() => reconnect(account), 3000);
  };
});
```

---

## 새 계정 추가 절차 (Phase 4~6 반복)

계정 하나 추가할 때마다 아래 절차를 반복. 자동화 스크립트로 만들 예정.

```
1. Redroid 컨테이너 생성
   docker run ... --name redroid-N -p ADB_PORT:5555 -p IRIS_PORT:3000

2. ADB 연결
   adb connect localhost:ADB_PORT

3. 카카오톡 + Termux 설치 (패치된 APK 재사용)
   adb -s localhost:ADB_PORT install-multiple patched-kakao/*.apk
   adb -s localhost:ADB_PORT install patched-termux/patched-aligned.apk

4. 카카오톡 로그인 (수동 - scrcpy 사용)
   scrcpy -s localhost:ADB_PORT

5. 메시지 1회 송수신 (DB 초기화)

6. Iris 설치 + 실행 (자동화 가능)
   - 환경변수 설정
   - Iris.apk 다운로드 + chmod 444
   - app_process로 실행

7. accounts.json에 계정 추가

8. API 서버 재시작 (또는 hot reload)
```

### 자동화 가능 범위

| 단계 | 자동화 | 비고 |
|------|--------|------|
| 컨테이너 생성 | ✅ 완전 자동 | 스크립트 1줄 |
| APK 설치 | ✅ 완전 자동 | 패치된 APK 재사용 |
| 카카오톡 로그인 | ❌ 수동 필수 | 전화번호 인증 |
| 메시지 송수신 | ⚠️ 반수동 | 다른 계정에서 보내기 가능 |
| Iris 설치/실행 | ✅ 완전 자동 | 스크립트화 완료 |
| 봇 배포 | ✅ 완전 자동 | base64 전송 |

---

## 서비스 자동 시작 (systemd)

### API 서버 서비스
```ini
# /etc/systemd/system/kakao-api.service
[Unit]
Description=KakaoTalk Multi-Account API Server
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/kakao-platform
ExecStart=/home/ubuntu/kakao-platform/venv/bin/uvicorn api:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Iris 자동 시작 (각 컨테이너)
```ini
# /etc/systemd/system/iris@.service
# 사용법: systemctl enable iris@1, iris@2, ...
[Unit]
Description=Iris for Redroid %i
After=docker.service

[Service]
Type=simple
ExecStart=/home/ubuntu/kakao-platform/scripts/start_iris.sh %i
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

---

## 보안

### API 인증
- 모든 API 요청에 `X-API-Key` 헤더 필수
- API Key는 `accounts.json`에 설정

### 네트워크
- 외부 노출 시 HTTPS 필수 (Let's Encrypt + Nginx reverse proxy)
- 또는 Tailscale/WireGuard VPN으로 접근 제한

### Nginx 리버스 프록시 설정
```nginx
server {
    listen 443 ssl;
    server_name kakao.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/kakao.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/kakao.yourdomain.com/privkey.pem;

    # API
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
    }

    # 대시보드
    location / {
        proxy_pass http://127.0.0.1:8080;
    }

    # WebSocket (각 Iris)
    location /ws/account-1 {
        proxy_pass http://127.0.0.1:3000/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /ws/account-2 {
        proxy_pass http://127.0.0.1:3001/ws;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

---

## 디렉토리 구조 (최종)

```
/home/ubuntu/kakao-platform/
├── api.py                    # FastAPI 서버
├── accounts.json             # 계정 설정
├── requirements.txt          # Python 의존성
├── venv/                     # Python 가상환경
│
├── dashboard/                # 웹 대시보드
│   ├── index.html           # 메인 대시보드
│   ├── account.html         # 계정 상세
│   ├── broadcast.html       # 전체 발송
│   ├── style.css
│   └── app.js
│
├── scripts/
│   ├── add_account.sh       # 계정 추가 (컨테이너 생성)
│   ├── setup_account.sh     # 계정 초기화 (APK 설치 + Iris)
│   ├── start_iris.sh        # Iris 시작
│   └── deploy_bot.sh        # 봇 코드 배포
│
├── patched-apks/             # 패치된 APK (재사용)
│   ├── kakao/
│   │   ├── patched-aligned.apk
│   │   ├── split_config.arm64_v8a-aligned.apk
│   │   ├── split_config.en-aligned.apk
│   │   └── split_config.mdpi-aligned.apk
│   └── termux/
│       └── patched-aligned.apk
│
├── data/                     # Redroid 데이터 볼륨
│   ├── redroid-1/
│   ├── redroid-2/
│   └── redroid-3/
│
└── docker-compose.yml        # 전체 Redroid 구성
```

---

## 구현 순서

맥미니 도착 후 아래 순서로 진행:

### Step 1: 인프라 (1시간)
- [ ] UTM + Ubuntu VM 설치 (`BUILD_GUIDE.md` Phase 1~3)
- [ ] Docker + binder_linux
- [ ] Redroid 컨테이너 N개 생성

### Step 2: 계정 셋업 (계정당 30분, 로그인은 수동)
- [ ] 패치된 APK 설치 (자동)
- [ ] 카카오톡 로그인 (수동, scrcpy)
- [ ] Iris 설치 + 실행 (자동)
- [ ] accounts.json에 등록

### Step 3: API 서버 (2시간)
- [ ] FastAPI 서버 구현
- [ ] 프록시 로직 (Iris ↔ API)
- [ ] 인증 미들웨어
- [ ] systemd 서비스 등록

### Step 4: 웹 대시보드 (3시간)
- [ ] 메인 대시보드 (계정 목록 + 상태)
- [ ] 계정 상세 (채팅방 + 메시지)
- [ ] 메시지 발송 UI
- [ ] 전체 동시 발송
- [ ] 실시간 메시지 피드 (WebSocket)

### Step 5: 자동화 + 보안 (1시간)
- [ ] Nginx + HTTPS
- [ ] systemd 자동 시작
- [ ] 모니터링 (헬스체크)

---

## Iris API 레퍼런스 (각 인스턴스)

API 서버가 프록시하는 Iris 내부 엔드포인트:

| 메서드 | 경로 | 설명 |
|--------|------|------|
| `POST` | `/reply` | 메시지 발송 `{"type":"text","room":"ID","data":"메시지"}` |
| `POST` | `/query` | DB 쿼리 `{"query":"SQL","bind":[]}` |
| `GET` | `/config` | 봇 설정 (bot_id 등) |
| `GET` | `/dashboard` | 대시보드 HTML |
| `WS` | `/ws` | 실시간 메시지 WebSocket |

### 주요 DB 쿼리

```sql
-- 채팅방 목록
SELECT id, active_members_count, last_log_id
FROM chat_rooms ORDER BY last_log_id DESC LIMIT 50

-- 친구 목록
SELECT id, name, enc FROM db2.friends

-- 최근 메시지 (암호화됨)
SELECT id, chat_id, user_id, message, type
FROM chat_logs ORDER BY id DESC LIMIT 20

-- 오픈채팅 멤버
SELECT user_id, nickname FROM db2.open_chat_member
WHERE chat_id = ?
```
