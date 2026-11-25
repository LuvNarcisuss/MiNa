// Retire legacy checkout before distributing the device-wallet client.
// Unfinished StoreKit payments stay available to the updated app.
Deno.serve(() => Response.json(
  { message: "Update MiNa to purchase or receive your star coins." },
  { status: 410 },
));
