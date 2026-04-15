import { supabaseFetch } from "@/shared/api/supabase";
import type { Room } from "./types";

export async function fetchRooms(): Promise<Room[]> {
  return supabaseFetch<Room[]>("recorded_rooms?select=*&order=started_at.desc");
}

export async function fetchRoomMessageCount(
  roomId: string
): Promise<number> {
  const res = await supabaseFetch<{ count: number }[]>(
    `message_embeddings?room_id=eq.${roomId}&select=count`,
    { headers: { Prefer: "count=exact" } }
  );
  return res?.[0]?.count ?? 0;
}
