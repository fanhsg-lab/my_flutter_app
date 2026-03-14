import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const PACKAGE_NAME = "com.EspanolDictionary";

Deno.serve(async (req: Request) => {
  // CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    // 1. Parse body
    const { product_id, purchase_token, platform } = await req.json();
    if (!product_id || !purchase_token) {
      return json({ error: "Missing product_id or purchase_token" }, 400);
    }

    // 2. Get user from JWT
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization")!;

    // Use service role key to validate the JWT
    const authClient = createClient(supabaseUrl, serviceKey);
    const token = authHeader.replace("Bearer ", "");
    console.log("Auth header present:", !!authHeader);
    console.log("Token length:", token.length);
    console.log("Token prefix:", token.substring(0, 20));
    const { data: { user }, error: authError } = await authClient.auth.getUser(token);
    console.log("Auth error:", authError?.message);
    console.log("User found:", !!user);
    if (authError || !user) return json({ error: "Unauthorized", detail: authError?.message }, 401);

    // 3. Get Google access token
    const serviceAccount = JSON.parse(Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON")!);
    const googleToken = await getGoogleAccessToken(serviceAccount);

    // 4. Verify with Google Play API
    const googleUrl = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE_NAME}/purchases/subscriptionsv2/tokens/${purchase_token}`;
    const googleRes = await fetch(googleUrl, {
      headers: { Authorization: `Bearer ${googleToken}` },
    });

    if (!googleRes.ok) {
      const err = await googleRes.text();
      console.error("Google verification failed:", err);
      return json({ error: "Google verification failed", detail: err }, 400);
    }

    const googleData = await googleRes.json();
    console.log("Google response:", JSON.stringify(googleData));

    // 5. Extract expiry and status
    const lineItem = googleData.lineItems?.[0];
    const expiresAt = lineItem?.expiryTime ? new Date(lineItem.expiryTime).toISOString() : null;
    const state = googleData.subscriptionState ?? "";
    const isActive = state === "SUBSCRIPTION_STATE_ACTIVE" ||
                     state === "SUBSCRIPTION_STATE_IN_GRACE_PERIOD";

    // 6. Save to subscriptions table
    const adminClient = createClient(supabaseUrl, serviceKey);
    const { error: upsertError } = await adminClient.from("subscriptions").upsert({
      user_id: user.id,
      product_id,
      purchase_token,
      status: isActive ? "active" : "expired",
      platform: platform ?? "android",
      starts_at: new Date().toISOString(),
      expires_at: expiresAt,
    }, { onConflict: "user_id" });

    if (upsertError) {
      console.error("Upsert error:", upsertError);
      return json({ error: "Failed to save subscription" }, 500);
    }

    return json({ success: true, status: isActive ? "active" : "expired", expires_at: expiresAt });

  } catch (e) {
    console.error("Edge function error:", e);
    return json({ error: String(e) }, 500);
  }
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function getGoogleAccessToken(sa: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = btoa(JSON.stringify({ alg: "RS256", typ: "JWT" })).replace(/=/g, "");
  const payload = btoa(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })).replace(/=/g, "");

  const signingInput = `${header}.${payload}`;
  const privateKey = await importPrivateKey(sa.private_key);
  const signature = await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" },
    privateKey,
    new TextEncoder().encode(signingInput),
  );

  const sig = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
  const jwt = `${signingInput}.${sig}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  const tokenData = await tokenRes.json();
  if (!tokenData.access_token) {
    throw new Error(`Failed to get Google token: ${JSON.stringify(tokenData)}`);
  }
  return tokenData.access_token;
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const pemContents = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\n/g, "");
  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}
