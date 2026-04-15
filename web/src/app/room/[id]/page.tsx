import Link from "next/link";
import { supabaseFetch } from "@/shared/api/supabase";
import { SearchPanel } from "@/features/search";
import type { Room } from "@/entities/room";

export const dynamic = "force-dynamic";

export default async function RoomPage(props: PageProps<"/room/[id]">) {
  const { id } = await props.params;

  const rooms = await supabaseFetch<Room[]>(
    `recorded_rooms?room_id=eq.${id}&select=*`
  );
  const room = rooms?.[0];

  const countRes = await supabaseFetch<{ count: number }[]>(
    `message_embeddings?room_id=eq.${id}&select=count`,
    { headers: { Prefer: "count=exact" } }
  );

  return (
    <main className="mx-auto max-w-2xl px-4 py-10">
      <Link
        href="/"
        className="mb-4 inline-block text-sm text-blue-600 hover:underline"
      >
        ← 방 목록
      </Link>

      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">
          {room?.room_name || id}
        </h1>
        <p className="mt-1 text-sm text-gray-500">
          기록 시작: {room ? new Date(room.started_at).toLocaleString("ko-KR") : "-"}
          {" · "}메시지 수: {countRes?.[0]?.count ?? 0}개
        </p>
      </div>

      <SearchPanel roomId={id} />
    </main>
  );
}
