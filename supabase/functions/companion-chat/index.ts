const instructions = "You are MiNa, an AI bedtime companion. Respond briefly and warmly in English. Listen to everyday concerns and offer gentle wind-down ideas. Do not diagnose or prescribe. Encourage appropriate real-world support when needed.";

function failure(status: number, message: string) {
  return Response.json({ message }, { status });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return failure(405, "Use POST to send a message.");
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return failure(401, "Sign in to continue.");

  const body = await request.json().catch(() => null);
  const prompt = typeof body?.prompt === "string" ? body.prompt.trim() : "";
  if (!prompt || Array.from(prompt).length > 6400 || !Array.isArray(body?.history) || body.history.length > 6) {
    return failure(400, "Shorten your message and try again.");
  }
  const messages = [{ role: "system", content: instructions }];
  for (const turn of body.history) {
    if (!["user", "assistant"].includes(turn?.role) || typeof turn.text !== "string" || turn.text.length > 3200) {
      return failure(400, "The conversation history could not be read.");
    }
    messages.push({ role: turn.role, content: turn.text });
  }
  messages.push({ role: "user", content: prompt });
  const base = Deno.env.get("SUPABASE_URL")!;
  const headers = { Authorization: authorization, apikey: Deno.env.get("SUPABASE_ANON_KEY")! };
  try {
    const user = await fetch(base + "/auth/v1/user", { headers });
    if (!user.ok) return failure(user.status >= 500 ? 503 : 401, "Your account could not be verified.");
    const { id } = await user.json();
    if (!id) return failure(401, "Sign in to continue.");
    const query = new URLSearchParams({ select: "expires_at", owner_id: "eq." + id, expires_at: "gt." + new Date().toISOString() });
    const session = await fetch(base + "/rest/v1/companion_sessions?" + query, { headers });
    if (!session.ok) return failure(503, "Your session could not be checked. Try again.");
    if (!(await session.json()).length) return failure(403, "Start a free session to continue.");

    const key = Deno.env.get("GROQ_API_KEY");
    if (!key) return failure(503, "MiNa Companion is unavailable. Try again later.");
    const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: "Bearer " + key, "Content-Type": "application/json" },
      body: JSON.stringify({ model: Deno.env.get("GROQ_MODEL") || "openai/gpt-oss-20b", messages, reasoning_effort: "low", max_completion_tokens: 1024 }),
      signal: AbortSignal.timeout(35000),
    });
    if (response.status === 429) return failure(429, "MiNa Companion is busy. Try again in a moment.");
    if (!response.ok) return failure(502, "MiNa Companion could not reply. Try again later.");
    const content = (await response.json()).choices?.[0]?.message?.content;
    if (typeof content !== "string" || !content.trim()) return failure(502, "No reply arrived. Try again.");
    return Response.json({ text: content.trim() }, { headers: { "Cache-Control": "no-store" } });
  } catch {
    return failure(503, "MiNa Companion could not connect. Try again.");
  }
});
