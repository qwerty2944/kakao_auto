import { NextRequest, NextResponse } from "next/server";

const GEMINI_API_KEY = process.env.GEMINI_API_KEY!;
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

async function getEmbedding(text: string): Promise<number[]> {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent?key=${GEMINI_API_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: "models/gemini-embedding-001",
        content: { parts: [{ text }] },
        taskType: "RETRIEVAL_QUERY",
        outputDimensionality: 768,
      }),
    }
  );
  if (!res.ok) throw new Error(`Embedding error: ${res.status}`);
  const data = await res.json();
  return data.embedding.values;
}

export async function POST(req: NextRequest) {
  const { query, room_id } = await req.json();

  if (!query || !room_id) {
    return NextResponse.json({ error: "query and room_id required" }, { status: 400 });
  }

  const embedding = await getEmbedding(query);
  const embStr = "[" + embedding.join(",") + "]";

  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/match_messages`, {
    method: "POST",
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query_embedding: embStr,
      target_room_id: room_id,
      match_threshold: 0.3,
      match_count: 20,
    }),
  });

  if (!res.ok) {
    return NextResponse.json({ error: `Search error: ${res.status}` }, { status: 500 });
  }

  const results = await res.json();
  return NextResponse.json({ results });
}
