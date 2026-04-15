"use client";

import { useSearch } from "./use-search";

export function SearchPanel({ roomId }: { roomId: string }) {
  const { query, setQuery, results, loading, error, search } = useSearch(roomId);

  return (
    <div className="space-y-4">
      <form
        onSubmit={(e) => {
          e.preventDefault();
          search();
        }}
        className="flex gap-2"
      >
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="대화 내용 검색..."
          className="flex-1 rounded-lg border border-gray-300 px-4 py-2 text-sm focus:border-blue-500 focus:outline-none"
        />
        <button
          type="submit"
          disabled={loading || !query.trim()}
          className="rounded-lg bg-blue-600 px-6 py-2 text-sm font-medium text-white hover:bg-blue-700 disabled:opacity-50"
        >
          {loading ? "검색 중..." : "검색"}
        </button>
      </form>

      {error && (
        <div className="rounded-lg bg-red-50 p-3 text-sm text-red-600">
          {error}
        </div>
      )}

      {results.length > 0 && (
        <div className="space-y-2">
          <p className="text-sm text-gray-500">{results.length}개 결과</p>
          {results.map((r) => (
            <div
              key={r.id}
              className="rounded-lg border border-gray-200 bg-white p-3"
            >
              <div className="flex items-center justify-between text-xs text-gray-400">
                <span className="font-medium text-gray-700">
                  {r.sender_name}
                </span>
                <span>
                  {new Date(r.sent_at).toLocaleString("ko-KR")} · 유사도{" "}
                  {(r.similarity * 100).toFixed(0)}%
                </span>
              </div>
              <p className="mt-1 text-sm text-gray-800 whitespace-pre-wrap">{r.message_text}</p>
            </div>
          ))}
        </div>
      )}

      {!loading && !error && results.length === 0 && query && (
        <p className="text-sm text-gray-400">검색 결과가 없습니다.</p>
      )}
    </div>
  );
}
