import { createClient } from "npm:@supabase/supabase-js@2.49.8";

const reply = (status: number, body: object) => Response.json(body, { status });
const bundle = "com.mina.bedtime";

async function verify(receipt: string, sandbox: boolean) {
  const url = sandbox ? "https://sandbox.itunes.apple.com/verifyReceipt" : "https://buy.itunes.apple.com/verifyReceipt";
  const res = await fetch(url, {
    method: "POST", redirect: "error", signal: AbortSignal.timeout(12000),
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ "receipt-data": receipt }),
  });
  if (!res.ok) throw new Error("Apple verification is unavailable.");
  return await res.json();
}

Deno.serve(async req => {
  if (req.method !== "POST") return reply(405, { message: "Use POST." });
  const token = req.headers.get("Authorization")?.match(/^Bearer (\S+)$/i)?.[1];
  if (!token) return reply(401, { message: "Sign in to open your wallet." });
  try {
    const service = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: { user }, error } = await service.auth.getUser(token);
    if (error || !user) return reply(401, { message: "Sign in again to open your wallet." });
    const body = await req.json().catch(() => null);
    if (body?.proof !== "receipt-v1") return reply(409, { message: "Update MiNa to complete this purchase." });
    if (typeof body.product !== "string" || !["prepare", "deliver"].includes(body.action))
      return reply(400, { message: "Invalid purchase request." });
    const { data: pack, error: catalogError } = await service.from("coin_packages")
      .select("coins").eq("product_id", body.product).single();
    if (catalogError || !pack) return reply(503, { message: "This package is unavailable." });
    if (body.action === "prepare") {
      const { error } = await service.from("wallets").select("owner_id").eq("owner_id", user.id).single();
      if (error) return reply(503, { message: "Your wallet could not be opened." });
      return reply(200, { proof: "receipt-v1", owner: user.id, product: body.product, coins: pack.coins });
    }

    if (typeof body.transaction !== "string" || !/^[0-9]{1,32}$/.test(body.transaction) ||
        typeof body.receipt !== "string" || !body.receipt.length || body.receipt.length > 4_000_000 ||
        !/^[A-Za-z0-9+/]+=*$/.test(body.receipt))
      return reply(400, { message: "Invalid App Store purchase proof." });

    let result = await verify(body.receipt, false);
    const sandbox = result.status === 21007;
    if (sandbox) result = await verify(body.receipt, true);
    const environment = sandbox ? "Sandbox" : "Production";
    const receipt = result.receipt;
    if (result.status !== 0 || result.environment !== environment || receipt?.bundle_id !== bundle ||
        receipt.receipt_type !== (sandbox ? "ProductionSandbox" : "Production") || !Array.isArray(receipt.in_app))
      return reply(409, { message: "Apple has not verified this receipt for MiNa." });

    type AppleRow = Record<string, unknown>;
    const matches = (row: AppleRow) => row?.transaction_id === body.transaction;
    const entries: AppleRow[] = receipt.in_app.filter(matches);
    if (entries.length === 0) return reply(200, { refreshReceipt: true });
    const latest: AppleRow[] = Array.isArray(result.latest_receipt_info) ? result.latest_receipt_info.filter(matches) : [];
    for (const tx of [...entries, ...latest]) {
      if (tx.product_id !== body.product || tx.quantity !== "1" || tx.original_transaction_id !== body.transaction ||
          !Number.isFinite(Number(tx.purchase_date_ms)) || Number(tx.purchase_date_ms) <= 0 ||
          tx.expires_date_ms != null || tx.cancellation_date_ms != null || tx.cancellation_date != null ||
          tx.cancellation_reason != null || tx.is_upgraded === "true" ||
          (tx.in_app_ownership_type != null && tx.in_app_ownership_type !== "PURCHASED") ||
          (tx.app_account_token != null && String(tx.app_account_token).toLowerCase() !== user.id.toLowerCase()))
        return reply(409, { message: "This purchase could not be verified for this wallet." });
    }

    const { data, error: saveError } = await service.rpc("credit_coin_purchase", {
      account: user.id, store_environment: environment, apple_transaction: body.transaction, sku: body.product,
    });
    if (saveError) return reply(503, { message: "Wallet delivery could not be confirmed. Refresh to retry." });
    return reply(200, data);
  } catch {
    return reply(503, { message: "Purchase verification is unavailable. Try again later." });
  }
});
