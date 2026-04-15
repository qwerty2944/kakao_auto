import Link from "next/link";
import { fetchRooms } from "@/entities/room";

export const dynamic = "force-dynamic";

export default async function HomePage() {
  const rooms = await fetchRooms();

  return (
    <main className="mx-auto max-w-2xl px-4 py-10">
      <h1 className="mb-6 text-2xl font-bold text-gray-900">카카오톡 대화 검색</h1>
      <div className="space-y-3">
        {rooms.map((room) => (
          <Link
            key={room.room_id}
            href={`/room/${room.room_id}`}
            className="block rounded-lg border border-gray-200 bg-white p-4 transition hover:border-blue-400 hover:shadow-sm"
          >
            <div className="flex items-center justify-between">
              <h2 className="font-medium text-gray-900">
                {room.room_name || room.room_id}
              </h2>
              <span className="text-xs text-gray-400">
                {new Date(room.started_at).toLocaleDateString("ko-KR")}
              </span>
            </div>
            <p className="mt-1 text-xs text-gray-500">
              시작: {room.started_by || "알 수 없음"} · ID: {room.room_id}
            </p>
          </Link>
        ))}
        {rooms.length === 0 && (
          <p className="text-gray-400">기록 중인 방이 없습니다.</p>
        )}
      </div>
    </main>
  );
}
