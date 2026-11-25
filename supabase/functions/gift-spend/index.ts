import { Buffer } from "node:buffer";
import { verifyAssertion, verifyAttestation } from "npm:node-app-attest@1.0.1";
import { createClient } from "npm:@supabase/supabase-js@2.49.8";

const response = (status: number, body: object) => Response.json(body, { status });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async req => {
  if (req.method !== "POST") return response(405, { message: "Use POST." });
  const token = req.headers.get("Authorization")?.match(/^Bearer (\S+)$/i)?.[1];
  if (!token) return response(401, { message: "Sign in to send gifts." });
  const teamIdentifier = Deno.env.get("MINA_APPLE_TEAM_ID");
  if (!teamIdentifier) return response(503, { message: "Device-funded gifts are unavailable." });
  const app = { teamIdentifier, bundleIdentifier: "com.mina.bedtime" };
  try {
    const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: { user }, error: authError } = await db.auth.getUser(token);
    if (!user || authError) return response(401, { message: "Sign in again to send gifts." });
    const body = await req.json();
    const key = body.key;
    if (typeof key !== "string" || !/^[A-Za-z0-9+/]{43}=$/.test(key)) throw Error();
    const keys = () => db.from("device_gift_keys");
    const owned = () => keys().select("*").eq("owner_id", user.id).eq("key_id", key);
    if (body.action === "challenge") {
      const { error } = await keys().upsert({ owner_id: user.id, key_id: key },
        { onConflict: "owner_id,key_id", ignoreDuplicates: true });
      if (error) throw error;
    }
    const { data: row, error } = await owned().single();
    if (error || !row) throw Error();
    if (body.action === "challenge") return response(200, { challenge: row.challenge, registered: !!row.public_key });
    if (body.action === "register" && !row.public_key && Date.parse(row.expires_at) > Date.now()) {
      const proof = verifyAttestation({ ...app, keyId: key, challenge: row.challenge,
        attestation: Buffer.from(body.proof, "base64"), allowDevelopmentEnvironment: false });
      const update = await keys().update({ public_key: proof.publicKey }).eq("owner_id", user.id)
        .eq("key_id", key).eq("challenge", row.challenge).is("public_key", null).select("key_id").single();
      if (update.error) throw update.error;
      return response(200, { registered: true });
    }
    if (body.action !== "authorize" || !row.public_key || typeof body.payload !== "string" ||
        body.payload.length > 4096 || typeof body.proof !== "string" || body.proof.length > 8192) throw Error();
    const { signCount } = verifyAssertion({ ...app, publicKey: row.public_key, signCount: row.sign_count,
      assertion: Buffer.from(body.proof, "base64"), payload: body.payload });
    const spend = JSON.parse(body.payload);
    if (spend.owner !== user.id || !uuid.test(spend.id) || !Number.isInteger(spend.item) || spend.item < 0 ||
        spend.item > 19 || !Number.isInteger(spend.quantity) || spend.quantity < 1 || spend.quantity > 99 ||
        !Number.isSafeInteger(spend.coins) || !Number.isSafeInteger(spend.total) || spend.coins < 0 ||
        !Number.isInteger(spend.localItems) || spend.localItems < 0 || spend.localItems > spend.quantity ||
        (spend.localItems > 0 ? !spend.room || spend.coins !== 0 : spend.coins === 0) ||
        spend.coins > spend.total || (spend.room == null ? spend.recipient != null :
          !uuid.test(spend.room) || !uuid.test(spend.recipient))) throw Error();
    const result = await db.rpc("authorize_device_gift", { p_owner: user.id, p_key: key, p_counter: signCount,
      p_operation: spend.id, p_request: [spend.room ? "send" : "acquire", spend.room ?? null,
        spend.recipient ?? null, spend.item, spend.quantity, spend.localItems > 0], p_total: spend.total, p_coins: spend.coins, p_items: spend.localItems });
    if (result.error) throw result.error;
    return response(200, { operation: spend.id });
  } catch {
    return response(409, { message: "The device gift authorization could not be confirmed." });
  }
});
