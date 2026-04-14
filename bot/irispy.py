"""
KakaoTalk Bot using IrisPy
Redroid + Iris + IrisPy 기반 카카오톡 봇

사용법:
    cd ~/ipy2
    source venv/bin/activate
    python irispy.py
"""

import base64
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime

try:
    from iris import Bot, ChatContext
except ImportError:
    print("irispy-client가 설치되어 있지 않습니다.")
    print("pip install irispy-client")
    sys.exit(1)

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

bot = Bot("127.0.0.1:3000")
bot_id = 439321293


IRIS_API = "http://127.0.0.1:3000"
CONTACTS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "contacts.json")

# 방별 대화 컨텍스트 (chat_id -> list of {"role": "user"/"model", "parts": [{"text": "..."}]})
MAX_CONTEXT_TURNS = 10  # 방당 최대 저장 턴 수 (user+model 쌍)
room_contexts: dict[str, list[dict]] = {}
room_ctx_lock = threading.Lock()

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY", "")
EMBEDDING_MODEL = "gemini-embedding-001"
recording_rooms: set[str] = set()
recording_rooms_lock = threading.Lock()


def load_contacts() -> dict:
    """저장된 연락처 로드"""
    try:
        with open(CONTACTS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_contact(user_id: str, name: str, room: str):
    """연락처 자동 저장 (메시지 수신 시마다 호출)"""
    contacts = load_contacts()
    contacts[user_id] = {"name": name, "room": room, "last_seen": datetime.now().strftime("%Y-%m-%d %H:%M")}
    try:
        with open(CONTACTS_FILE, "w", encoding="utf-8") as f:
            json.dump(contacts, f, ensure_ascii=False, indent=2)
    except Exception:
        pass


def supabase_request(method: str, path: str, data: dict | list | None = None, prefer: str = "") -> dict | list | None:
    """Supabase REST API 래퍼"""
    url = f"{SUPABASE_URL}/rest/v1/{path}"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
    }
    if prefer:
        headers["Prefer"] = prefer
    body = json.dumps(data).encode("utf-8") if data is not None else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=15) as resp:
        raw = resp.read().decode("utf-8")
        if not raw:
            return None
        return json.loads(raw)


def supabase_rpc(func_name: str, params: dict) -> list | dict | None:
    """Supabase RPC 함수 호출"""
    url = f"{SUPABASE_URL}/rest/v1/rpc/{func_name}"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
    }
    body = json.dumps(params).encode("utf-8")
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=15) as resp:
        raw = resp.read().decode("utf-8")
        if not raw:
            return None
        return json.loads(raw)


def get_embedding(text: str, task_type: str = "RETRIEVAL_DOCUMENT") -> list[float] | None:
    """Gemini embedding API로 768차원 임베딩 벡터 반환"""
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{EMBEDDING_MODEL}:embedContent?key={GEMINI_API_KEY}"
    payload = json.dumps({
        "model": f"models/{EMBEDDING_MODEL}",
        "content": {"parts": [{"text": text}]},
        "taskType": task_type,
        "outputDimensionality": 768,
    }).encode("utf-8")
    try:
        req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("embedding", {}).get("values")
    except Exception as e:
        print(f"[임베딩] 오류: {e}", flush=True)
        return None


def store_message_embedding(room_id: str, room_name: str, sender_name: str, sender_id: str, message_text: str):
    """메시지 임베딩 생성 후 Supabase에 저장 (백그라운드 스레드에서 호출)"""
    try:
        embedding = get_embedding(message_text, "RETRIEVAL_DOCUMENT")
        row = {
            "room_id": room_id or "",
            "room_name": room_name or "",
            "sender_name": sender_name or str(sender_id) or "unknown",
            "sender_id": sender_id or "",
            "message_text": message_text or "",
        }
        if embedding:
            row["embedding"] = "[" + ",".join(str(v) for v in embedding) + "]"
        supabase_request("POST", "message_embeddings", row, prefer="return=minimal")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print(f"[기록] 저장 실패: {e} | {body}", flush=True)
    except Exception as e:
        print(f"[기록] 저장 실패: {e}", flush=True)


def load_recording_rooms():
    """시작 시 기록 중인 방 목록을 DB에서 로드"""
    if not SUPABASE_URL or not SUPABASE_KEY:
        print("[기록] SUPABASE_URL 또는 SUPABASE_KEY 미설정, 기록 기능 비활성화", flush=True)
        return
    try:
        rows = supabase_request("GET", "recorded_rooms?select=room_id")
        if rows:
            with recording_rooms_lock:
                for row in rows:
                    recording_rooms.add(row["room_id"])
            print(f"[기록] {len(recording_rooms)}개 방 기록 중", flush=True)
    except Exception as e:
        print(f"[기록] 방 목록 로드 실패: {e}", flush=True)


def search_messages(room_id: str, query: str) -> str:
    """RAG: 임베딩→벡터검색→Gemini 답변생성"""
    query_emb = get_embedding(query, "RETRIEVAL_QUERY")
    if not query_emb:
        return "검색용 임베딩 생성에 실패했습니다."
    try:
        emb_str = "[" + ",".join(str(v) for v in query_emb) + "]"
        results = supabase_request(
            "POST", "rpc/match_messages",
            {
                "query_embedding": emb_str,
                "target_room_id": room_id,
                "match_threshold": 0.3,
                "match_count": 20,
            },
        )
    except Exception as e:
        return f"검색 오류: {e}"
    if not results:
        return "관련 대화를 찾지 못했습니다."
    # 컨텍스트 구성
    context_lines = []
    for r in results:
        sent_at = r.get("sent_at", "")[:19].replace("T", " ")
        context_lines.append(f"[{sent_at}] {r['sender_name']}: {r['message_text']}")
    context = "\n".join(context_lines)
    # Gemini로 답변 생성
    prompt = (
        f"다음은 카카오톡 대화 기록에서 검색된 메시지들입니다:\n\n"
        f"{context}\n\n"
        f"위 대화 내용을 바탕으로 다음 질문에 답해주세요:\n{query}\n\n"
        f"대화 내용에 없는 정보는 추측하지 말고, 찾은 내용만 근거로 답해주세요."
    )
    answer, _ = ask_gemini(prompt)
    return answer


def iris_query(sql: str) -> list[dict]:
    """Iris /query 엔드포인트로 SQL 실행"""
    payload = json.dumps({"query": sql}).encode("utf-8")
    req = urllib.request.Request(
        f"{IRIS_API}/query", data=payload, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8", errors="replace")).get("data", [])


def generate_image(prompt: str) -> tuple[str | None, str]:
    """Gemini로 이미지 생성. (base64문자열, 에러메시지) 반환."""
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent?key={GEMINI_API_KEY}"
    full_prompt = f"Generate an image of: {prompt}"
    payload = json.dumps({
        "contents": [{"parts": [{"text": full_prompt}]}],
        "generationConfig": {"responseModalities": ["IMAGE", "TEXT"]},
    }).encode("utf-8")
    try:
        print(f"[이미지] API 요청 시작: {full_prompt}", flush=True)
        req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode("utf-8")
            print(f"[이미지] API 응답 수신: {len(raw)} bytes", flush=True)
            data = json.loads(raw)
            parts = data.get("candidates", [{}])[0].get("content", {}).get("parts", [])
            print(f"[이미지] parts 개수: {len(parts)}, keys: {[list(p.keys()) for p in parts]}", flush=True)
            for part in parts:
                if "inlineData" in part:
                    b64 = part["inlineData"]["data"]
                    print(f"[이미지] base64 추출 완료: {len(b64)} chars", flush=True)
                    return b64, ""
                if "text" in part:
                    print(f"[이미지] 텍스트 응답: {part['text'][:200]}", flush=True)
            return None, "이미지 생성에 실패했습니다. 다시 시도해주세요."
    except urllib.error.HTTPError as e:
        print(f"[이미지] HTTP 에러: {e.code}", flush=True)
        if e.code == 429:
            return None, "API 요청 한도 초과입니다. 잠시 후 다시 시도해주세요."
        return None, f"API 오류 ({e.code}): {e.reason}"
    except Exception as e:
        print(f"[이미지] 예외: {e}", flush=True)
        return None, f"오류: {e}"


def _get_context(room_key: str) -> list[dict]:
    """방별 대화 기록 가져오기"""
    with room_ctx_lock:
        return list(room_contexts.get(room_key, []))


def _add_context(room_key: str, role: str, text: str):
    """방별 대화 기록에 추가 (최대 MAX_CONTEXT_TURNS 쌍 유지)"""
    with room_ctx_lock:
        if room_key not in room_contexts:
            room_contexts[room_key] = []
        room_contexts[room_key].append({"role": role, "parts": [{"text": text}]})
        # user+model = 2 메시지가 1턴, 최대 MAX_CONTEXT_TURNS턴 유지
        max_msgs = MAX_CONTEXT_TURNS * 2
        if len(room_contexts[room_key]) > max_msgs:
            room_contexts[room_key] = room_contexts[room_key][-max_msgs:]


def ask_gemini(question: str, room_key: str = "") -> tuple[str, str]:
    """Gemini에 질문하고 (답변, 토큰정보) 튜플 반환. room_key가 있으면 컨텍스트 유지."""
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-lite-latest:generateContent?key={GEMINI_API_KEY}"
    # 컨텍스트 구성
    if room_key:
        contents = _get_context(room_key) + [{"role": "user", "parts": [{"text": question}]}]
    else:
        contents = [{"role": "user", "parts": [{"text": question}]}]
    payload = json.dumps({
        "contents": contents,
        "generationConfig": {"maxOutputTokens": 1024},
    }).encode("utf-8")
    try:
        req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            answer = data["candidates"][0]["content"]["parts"][0]["text"]
            usage = data.get("usageMetadata", {})
            prompt_tokens = usage.get("promptTokenCount", 0)
            answer_tokens = usage.get("candidatesTokenCount", 0)
            total_tokens = usage.get("totalTokenCount", 0)
            token_info = f"\n\n[토큰] 입력: {prompt_tokens} | 출력: {answer_tokens} | 합계: {total_tokens}"
            # 성공 시 컨텍스트에 저장
            if room_key:
                _add_context(room_key, "user", question)
                _add_context(room_key, "model", answer)
            return answer, token_info
    except urllib.error.HTTPError as e:
        if e.code == 429:
            return "API 요청 한도 초과입니다. 잠시 후 다시 시도해주세요.", ""
        return f"API 오류 ({e.code}): {e.reason}", ""
    except Exception as e:
        return f"오류: {e}", ""


@bot.on_event("chat")
def on_message(chat: ChatContext):
    # "chat" 이벤트는 모든 origin을 수신 (MSG, MCHATLOGS, WRITE, POST 등)
    # WRITE는 봇 자신이 보낸 메시지이므로 무시 (무한루프 방지)
    origin = chat.message.v.get("origin", "") if chat.message.v else ""
    if origin == "WRITE":
        return
    try:
        _handle_message(chat)
    except Exception as e:
        print(f"[ERROR] {e}", flush=True)
        try:
            chat.reply(f"오류 발생: {e}")
        except Exception:
            pass


def _handle_message(chat: ChatContext):
    text = chat.message.msg
    command = chat.message.command
    param = chat.message.param

    room_name = chat.room.name or str(chat.room.id)
    sender_name = chat.sender.name or str(chat.sender.id)
    print(f"[{room_name}] {sender_name}: {text}", flush=True)

    # 메시지 보낸 사람 자동 수집 (본인 제외)
    sender_id = str(getattr(chat.sender, "id", "") or "")
    if sender_id and sender_id != str(bot_id):
        save_contact(sender_id, chat.sender.name, chat.room.name)

    if command == "/ping":
        chat.reply("pong!")

    elif command == "/echo":
        if chat.message.has_param:
            chat.reply(param)
        else:
            chat.reply("사용법: /echo <메시지>")

    elif command == "/time":
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        chat.reply(f"현재 시간: {now}")

    elif command == "/질문":
        if chat.message.has_param:
            chat.reply("생각 중...")
            answer, token_info = ask_gemini(param)
            chat.reply(answer + token_info)
        else:
            chat.reply("사용법: /질문 <질문 내용>")

    elif command == "/초기화":
        room_key = str(chat.room.id)
        with room_ctx_lock:
            room_contexts.pop(room_key, None)
        chat.reply("대화 기록이 초기화되었습니다.")

    elif command == "/그림":
        if chat.message.has_param:
            chat.reply("그리는 중...")
            print(f"[이미지] 생성 시작: {param}", flush=True)
            img_b64, err = generate_image(param)
            if img_b64:
                print(f"[이미지] 리사이즈 및 전송 시작...", flush=True)
                import base64 as b64mod
                from io import BytesIO
                from PIL import Image
                img_bytes = b64mod.b64decode(img_b64)
                img = Image.open(BytesIO(img_bytes))
                img.thumbnail((1024, 1024))
                buf = BytesIO()
                img.save(buf, format="JPEG", quality=85)
                resized_bytes = buf.getvalue()
                print(f"[이미지] 원본: {len(img_bytes)}B → 리사이즈: {len(resized_bytes)}B", flush=True)
                bot.api.reply_media(room_id=chat.room.id, files=[resized_bytes])
                print(f"[이미지] 전송 완료!", flush=True)
            else:
                print(f"[이미지] 생성 실패: {err}", flush=True)
                chat.reply(err)
        else:
            chat.reply("사용법: /그림 <설명>\n예: /그림 귀여운 바나나 캐릭터")

    elif command == "/기록시작":
        room_key = str(chat.room.id)
        with recording_rooms_lock:
            if room_key in recording_rooms:
                chat.reply("이미 이 방의 대화를 기록 중입니다.")
                return
        try:
            supabase_request("POST", "recorded_rooms", {
                "room_id": room_key,
                "room_name": chat.room.name or str(chat.room.id),
                "started_by": chat.sender.name or str(chat.sender.id),
            }, prefer="return=minimal")
            with recording_rooms_lock:
                recording_rooms.add(room_key)
            chat.reply(f"이 방의 대화 기록을 시작합니다.\n방 이름: {chat.room.name or room_key}")
        except Exception as e:
            chat.reply(f"기록 시작 실패: {e}")

    elif command == "/기록중지":
        room_key = str(chat.room.id)
        with recording_rooms_lock:
            if room_key not in recording_rooms:
                chat.reply("이 방은 기록 중이 아닙니다.")
                return
        try:
            supabase_request("DELETE", f"recorded_rooms?room_id=eq.{room_key}")
            with recording_rooms_lock:
                recording_rooms.discard(room_key)
            chat.reply("대화 기록을 중지했습니다.\n(기존 기록은 유지됩니다)")
        except Exception as e:
            chat.reply(f"기록 중지 실패: {e}")

    elif command == "/검색":
        if chat.message.has_param:
            room_key = str(chat.room.id)
            chat.reply("검색 중...")
            answer = search_messages(room_key, param)
            chat.reply(answer)
        else:
            chat.reply("사용법: /검색 <질문>\n예: /검색 지난주 회의에서 결정된 사항이 뭐야?")

    elif command == "/친구목록":
        contacts = load_contacts()
        if not contacts:
            chat.reply("아직 수집된 친구가 없습니다.\n메시지를 주고받으면 자동으로 수집됩니다.")
            return
        lines = [f"카톡 친구 목록 ({len(contacts)}명)\n"]
        sorted_contacts = sorted(contacts.values(), key=lambda x: x.get("last_seen", ""), reverse=True)
        for i, c in enumerate(sorted_contacts, 1):
            lines.append(f"{i}. {c['name']} ({c.get('room', '')})")
        chat.reply("\n".join(lines))

    elif command == "/help":
        help_text = (
            "사용 가능한 명령어:\n"
            "/ping - 봇 응답 확인\n"
            "/echo <메시지> - 메시지 반복\n"
            "/time - 현재 시간\n"
            "/질문 <내용> - Gemini AI에게 질문 (대화 기억됨)\n"
            "/초기화 - AI 대화 기록 초기화\n"
            "/그림 <설명> - AI 이미지 생성\n"
            "/친구목록 - 대화한 친구 목록 (자동 수집)\n"
            "/기록시작 - 이 방의 대화 기록 시작\n"
            "/기록중지 - 대화 기록 중지\n"
            "/검색 <질문> - 기록된 대화에서 RAG 검색\n"
            "/help - 이 도움말"
        )
        chat.reply(help_text)

    # 기록 중인 방의 일반 메시지 저장 (명령어가 아닌 경우)
    if not text.startswith("/"):
        room_key = str(chat.room.id)
        with recording_rooms_lock:
            is_recording = room_key in recording_rooms
        if is_recording:
            threading.Thread(
                target=store_message_embedding,
                args=(room_key, room_name, sender_name, sender_id, text),
                daemon=True,
            ).start()


def _db_poll_loop():
    """Iris WebSocket이 놓치는 메시지를 DB 직접 폴링으로 보완.
    supplement='' 인 메시지는 Iris가 JSONException으로 스킵하므로 여기서 처리."""
    last_id = 0
    # 시작 시 마지막 ID 가져오기
    try:
        rows = iris_query("SELECT MAX(id) as max_id FROM chat_logs")
        if rows and rows[0].get("max_id"):
            last_id = int(rows[0]["max_id"])
    except Exception:
        pass
    print(f"[DB폴링] 시작, last_id={last_id}", flush=True)

    while True:
        try:
            time.sleep(1)
            rows = iris_query(
                f"SELECT id, user_id, message, v, chat_id, supplement "
                f"FROM chat_logs "
                f"WHERE id > {last_id} "
                f"ORDER BY id ASC LIMIT 20"
            )
            for row in rows:
                msg_id = int(row["id"])
                if msg_id > last_id:
                    last_id = msg_id
                user_id = int(row["user_id"])
                if user_id == bot_id:
                    continue
                msg_text = row.get("message", "")
                chat_id = int(row["chat_id"])
                supplement = row.get("supplement", "")
                if msg_text.startswith("/") and supplement == "":
                    parts = msg_text.split(" ", 1)
                    cmd = parts[0]
                    param = parts[1] if len(parts) > 1 else ""
                    print(f"[DB폴링] cmd={cmd} param={param} room={chat_id} user={user_id}", flush=True)
                    # 별도 스레드로 처리 (폴링 루프 블로킹 방지)
                    threading.Thread(
                        target=_handle_polled_command, args=(cmd, param, chat_id), daemon=True
                    ).start()
                elif not msg_text.startswith("/") and msg_text.strip():
                    # 기록 중인 방의 일반 메시지 저장
                    room_key = str(chat_id)
                    with recording_rooms_lock:
                        is_recording = room_key in recording_rooms
                    if is_recording:
                        threading.Thread(
                            target=store_message_embedding,
                            args=(room_key, "", str(user_id), str(user_id), msg_text),
                            daemon=True,
                        ).start()
            if not rows:
                # supplement='' 메시지가 없을 때만 last_id를 최신으로 갱신
                # (처리 중 도착한 supplement='' 메시지 스킵 방지)
                rows2 = iris_query(f"SELECT MAX(id) as max_id FROM chat_logs WHERE id > {last_id}")
                if rows2 and rows2[0].get("max_id"):
                    new_max = int(rows2[0]["max_id"])
                    if new_max > last_id:
                        last_id = new_max
        except Exception as e:
            print(f"[DB폴링] 에러: {e}", flush=True)
            time.sleep(3)


def _iris_reply(room_id: int, text: str):
    """Iris HTTP API로 직접 텍스트 전송"""
    payload = json.dumps({"type": "text", "room": str(room_id), "data": text}).encode("utf-8")
    req = urllib.request.Request(
        f"{IRIS_API}/reply", data=payload, headers={"Content-Type": "application/json"}
    )
    urllib.request.urlopen(req, timeout=10)


def _handle_polled_command(cmd: str, param: str, room_id: int):
    """DB 폴링으로 감지한 명령어 처리 (WebSocket 누락분)"""
    if cmd == "/ping":
        _iris_reply(room_id, "pong!")
    elif cmd == "/echo" and param:
        _iris_reply(room_id, param)
    elif cmd == "/time":
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        _iris_reply(room_id, f"현재 시간: {now}")
    elif cmd == "/질문" and param:
        _iris_reply(room_id, "생각 중...")
        answer, token_info = ask_gemini(param)
        _iris_reply(room_id, answer + token_info)
    elif cmd == "/초기화":
        with room_ctx_lock:
            room_contexts.pop(str(room_id), None)
        _iris_reply(room_id, "대화 기록이 초기화되었습니다.")
    elif cmd == "/그림" and param:
        _iris_reply(room_id, "그리는 중...")
        img_b64, err = generate_image(param)
        if img_b64:
            import base64 as b64mod
            from io import BytesIO
            from PIL import Image
            img_bytes = b64mod.b64decode(img_b64)
            img = Image.open(BytesIO(img_bytes))
            img.thumbnail((1024, 1024))
            buf = BytesIO()
            img.save(buf, format="JPEG", quality=85)
            resized_bytes = buf.getvalue()
            bot.api.reply_media(room_id=room_id, files=[resized_bytes])
        else:
            _iris_reply(room_id, err)
    elif cmd == "/기록시작":
        room_key = str(room_id)
        with recording_rooms_lock:
            if room_key in recording_rooms:
                _iris_reply(room_id, "이미 이 방의 대화를 기록 중입니다.")
                return
        try:
            supabase_request("POST", "recorded_rooms", {
                "room_id": room_key,
                "room_name": "",
                "started_by": "",
            }, prefer="return=minimal")
            with recording_rooms_lock:
                recording_rooms.add(room_key)
            _iris_reply(room_id, "이 방의 대화 기록을 시작합니다.")
        except Exception as e:
            _iris_reply(room_id, f"기록 시작 실패: {e}")
    elif cmd == "/기록중지":
        room_key = str(room_id)
        with recording_rooms_lock:
            if room_key not in recording_rooms:
                _iris_reply(room_id, "이 방은 기록 중이 아닙니다.")
                return
        try:
            supabase_request("DELETE", f"recorded_rooms?room_id=eq.{room_key}")
            with recording_rooms_lock:
                recording_rooms.discard(room_key)
            _iris_reply(room_id, "대화 기록을 중지했습니다.\n(기존 기록은 유지됩니다)")
        except Exception as e:
            _iris_reply(room_id, f"기록 중지 실패: {e}")
    elif cmd == "/검색" and param:
        _iris_reply(room_id, "검색 중...")
        answer = search_messages(str(room_id), param)
        _iris_reply(room_id, answer)
    elif cmd == "/help":
        _iris_reply(room_id, "사용 가능한 명령어:\n/ping - 봇 응답 확인\n/echo <메시지> - 메시지 반복\n/time - 현재 시간\n/질문 <내용> - Gemini AI에게 질문 (대화 기억됨)\n/초기화 - AI 대화 기록 초기화\n/그림 <설명> - AI 이미지 생성\n/기록시작 - 대화 기록 시작\n/기록중지 - 대화 기록 중지\n/검색 <질문> - 기록된 대화에서 RAG 검색\n/help - 이 도움말")


if __name__ == "__main__":
    print("봇 시작: 127.0.0.1:3000")
    load_recording_rooms()
    # DB 폴링 스레드 시작 (Iris WebSocket 누락 메시지 보완)
    poll_thread = threading.Thread(target=_db_poll_loop, daemon=True)
    poll_thread.start()
    bot.run()
