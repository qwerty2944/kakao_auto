export interface Room {
  room_id: string;
  room_name: string;
  started_at: string;
  started_by: string;
}

export interface SearchResult {
  id: number;
  room_id: string;
  sender_name: string;
  message_text: string;
  sent_at: string;
  similarity: number;
}
