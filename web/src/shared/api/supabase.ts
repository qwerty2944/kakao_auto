import { SUPABASE_URL, SUPABASE_ANON_KEY } from "@/shared/config";

export async function supabaseFetch<T>(
  path: string,
  options?: RequestInit
): Promise<T> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...options,
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      "Content-Type": "application/json",
      ...options?.headers,
    },
  });
  if (!res.ok) throw new Error(`Supabase error: ${res.status}`);
  const text = await res.text();
  return text ? (JSON.parse(text) as T) : (null as unknown as T);
}
