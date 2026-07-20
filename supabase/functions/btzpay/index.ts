import BetabotzPaygate from "npm:betabotz-paygate@1.0.1";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const apiKey = Deno.env.get("BTZPAY_API_KEY")!;
const publicSiteUrl = (Deno.env.get("PUBLIC_SITE_URL") || "").replace(
  /\/$/,
  "",
);
const paygate = new BetabotzPaygate({ apiKey });
const admin = createClient(supabaseUrl, serviceKey, {
  auth: { persistSession: false },
});

function gatewayStatus(value: unknown) {
  const status = String(value || "pending").toLowerCase();
  return status === "sukses"
    ? "paid"
    : status === "cancel"
      ? "cancelled"
      : status === "gagal"
        ? "failed"
        : status;
}

async function authenticatedClient(req: Request) {
  const authorization = req.headers.get("Authorization") || "";
  const client = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const {
    data: { user },
  } = await client.auth.getUser();
  if (!user) throw new Error("Silakan login terlebih dahulu");
  return { client, user };
}

async function staffRole(userId: string) {
  const { data } = await admin
    .from("profiles")
    .select("role")
    .eq("id", userId)
    .single();
  return String(data?.role || "user").toLowerCase();
}

async function createPayment(
  orderId: string,
  userId: string,
  allowAdmin = false,
) {
  if (!apiKey) throw new Error("Secret BTZPAY_API_KEY belum dipasang");
  if (!publicSiteUrl) throw new Error("Secret PUBLIC_SITE_URL belum dipasang");
  const { data: order, error } = await admin
    .from("orders")
    .select("*")
    .eq("id", orderId)
    .single();
  if (error || !order) throw new Error("Pesanan tidak ditemukan");
  if (order.user_id !== userId && !allowAdmin) throw new Error("Akses ditolak");
  if (["paid", "completed"].includes(order.status))
    throw new Error("Pesanan sudah dibayar");

  const { data: row } = await admin
    .from("site_settings")
    .select("settings")
    .eq("id", "main")
    .single();
  const settings = row?.settings || {};
  if (!settings.payment_enabled)
    throw new Error("Pembayaran otomatis sedang dinonaktifkan");

  const { data: existing } = await admin
    .from("payment_transactions")
    .select("id,status,payment_url")
    .eq("order_id", orderId)
    .eq("status", "pending")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (existing) return existing;

  const timeoutMinutes = Math.max(
    5,
    Math.min(60, Number(settings.payment_timeout_minutes) || 15),
  );
  const paymentMethod = "qrisdana";
  const amount = Number(order.total);
  if (!Number.isFinite(amount) || amount < 1)
    throw new Error(`Nominal pesanan tidak valid: ${String(order.total)}`);
  const callbackUrl = `${supabaseUrl}/functions/v1/btzpay?action=webhook`;
  const returnUrl = `${publicSiteUrl}/payment.html?order=${encodeURIComponent(orderId)}`;
  const result = await paygate.createTransaction({
    action: "create",
    amount,
    fee: 0,
    timeout: timeoutMinutes * 60 * 1000,
    callback_url: callbackUrl,
    return_url: returnUrl,
    notes: `Pesanan ${order.order_number}`,
  });
  const tx = result.data;
  const { accessKey, ...safeTransaction } = tx;
  const { data: payment, error: insertError } = await admin
    .from("payment_transactions")
    .insert({
      order_id: order.id,
      gateway_transaction_id: tx.transactionId,
      payment_method: paymentMethod,
      amount: Number(tx.amount ?? order.total),
      total_amount: Number(tx.totalAmount ?? order.total),
      status: gatewayStatus(tx.status),
      payment_url: tx.paymentUrl,
      expires_at:
        tx.expiredAt ||
        new Date(Date.now() + timeoutMinutes * 60000).toISOString(),
      raw_response: { success: result.success, data: safeTransaction },
    })
    .select()
    .single();
  if (insertError) throw insertError;
  await admin
    .from("payment_gateway_secrets")
    .insert({ payment_id: payment.id, access_key: accessKey });
  await admin
    .from("orders")
    .update({ payment_status: "pending" })
    .eq("id", order.id);
  return payment;
}

async function getPaymentWithSecret(paymentId: string) {
  const { data: payment, error } = await admin
    .from("payment_transactions")
    .select("*")
    .eq("id", paymentId)
    .single();
  if (error || !payment) throw new Error("Pembayaran tidak ditemukan");
  const { data: secret } = await admin
    .from("payment_gateway_secrets")
    .select("access_key")
    .eq("payment_id", payment.id)
    .single();
  if (!secret) throw new Error("Access key pembayaran tidak ditemukan");
  return { payment, accessKey: secret.access_key };
}

async function syncPayment(paymentId: string) {
  const { payment, accessKey } = await getPaymentWithSecret(paymentId);
  const result = await paygate.getTransaction(
    payment.gateway_transaction_id,
    accessKey,
  );
  const safeRaw = {
    transactionId: result.data?.transactionId,
    status: result.data?.status,
    amount: result.data?.amount,
    paidAt: result.data?.paidAt,
    expiredAt: result.data?.expiredAt,
    reason: result.data?.reason,
  };
  await admin.rpc("apply_btzpay_status", {
    p_transaction_id: payment.gateway_transaction_id,
    p_status: result.data?.status || "pending",
    p_raw: safeRaw,
    p_reason: result.data?.reason || null,
  });
  return {
    ...payment,
    ...result.data,
    status: gatewayStatus(result.data?.status),
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const url = new URL(req.url);
  const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
  const action = url.searchParams.get("action") || body.action || "status";

  try {
    if (action === "webhook") {
      const transactionId = String(
        body.pay_id || body.raw?.data?.transactionId || "",
      );
      const log = await admin
        .from("payment_webhook_logs")
        .insert({
          gateway_transaction_id: transactionId,
          event_status: body.status,
          payload: body,
        })
        .select("id")
        .single();
      const { data: payment } = await admin
        .from("payment_transactions")
        .select("id,amount")
        .eq("gateway_transaction_id", transactionId)
        .single();
      if (!payment) throw new Error("Transaksi callback tidak dikenal");
      const secured = await getPaymentWithSecret(payment.id);
      const verified = await paygate.getTransaction(
        secured.payment.gateway_transaction_id,
        secured.accessKey,
      );
      if (Number(verified.data?.amount) !== Number(payment.amount))
        throw new Error("Nominal callback tidak cocok");
      await admin.rpc("apply_btzpay_status", {
        p_transaction_id: secured.payment.gateway_transaction_id,
        p_status: verified.data?.status || "pending",
        p_raw: {
          transactionId: verified.data?.transactionId,
          status: verified.data?.status,
          amount: verified.data?.amount,
          paidAt: verified.data?.paidAt,
          expiredAt: verified.data?.expiredAt,
          reason: verified.data?.reason,
        },
        p_reason: verified.data?.reason || null,
      });
      await admin
        .from("payment_webhook_logs")
        .update({ verified: true })
        .eq("id", log.data?.id);
      return json({ success: true });
    }

    if (action === "expire") {
      if (
        req.headers.get("x-cron-secret") !== Deno.env.get("BTZPAY_CRON_SECRET")
      )
        return json({ error: "Akses ditolak" }, 401);
      const { data: expired } = await admin
        .from("payment_transactions")
        .select("id")
        .eq("status", "pending")
        .lt("expires_at", new Date().toISOString())
        .limit(100);
      for (const item of expired || []) {
        try {
          await syncPayment(item.id);
        } catch {
          /* dicoba lagi oleh cron berikutnya */
        }
        const { data: current } = await admin
          .from("payment_transactions")
          .select("gateway_transaction_id,status")
          .eq("id", item.id)
          .single();
        if (current?.status === "pending") {
          try {
            await paygate.cancelTransaction(
              current.gateway_transaction_id,
              "Batas pembayaran berakhir",
            );
          } catch {
            /* status lokal tetap ditutup */
          }
          await admin.rpc("apply_btzpay_status", {
            p_transaction_id: current.gateway_transaction_id,
            p_status: "expired",
            p_raw: {},
            p_reason: "Batas pembayaran berakhir",
          });
        }
      }
      return json({ success: true, processed: expired?.length || 0 });
    }

    const { user } = await authenticatedClient(req);
    const role = await staffRole(user.id);
    const userIsAdmin = [
      "admin",
      "super_admin",
      "order_admin",
      "finance_admin",
    ].includes(role);
    const canRefund = ["admin", "super_admin", "finance_admin"].includes(role);

    if (action === "create" || action === "recreate") {
      const orderId = String(body.order_id || "");
      if (action === "recreate") {
        const { data: targetOrder } = await admin
          .from("orders")
          .select("status,user_id")
          .eq("id", orderId)
          .single();
        if (!targetOrder) throw new Error("Pesanan tidak ditemukan");
        if (targetOrder.user_id !== user.id && !userIsAdmin)
          throw new Error("Akses ditolak");
        if (["paid", "completed"].includes(targetOrder.status))
          throw new Error("Pesanan sudah dibayar");
        const { data: old } = await admin
          .from("payment_transactions")
          .select("id,gateway_transaction_id,status")
          .eq("order_id", orderId)
          .eq("status", "pending")
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();
        if (old) {
          try {
            await paygate.cancelTransaction(
              old.gateway_transaction_id,
              "Pembayaran dibuat ulang",
            );
          } catch {
            /* lanjut */
          }
          await admin.rpc("apply_btzpay_status", {
            p_transaction_id: old.gateway_transaction_id,
            p_status: "cancel",
            p_raw: {},
            p_reason: "Dibuat ulang",
          });
        }
        await admin
          .from("orders")
          .update({ status: "pending", payment_status: "unpaid" })
          .eq("id", orderId);
      }
      return json({
        success: true,
        payment: await createPayment(orderId, user.id, userIsAdmin),
      });
    }

    const paymentId = String(body.payment_id || "");
    const { payment } = await getPaymentWithSecret(paymentId);
    const { data: order } = await admin
      .from("orders")
      .select("user_id")
      .eq("id", payment.order_id)
      .single();
    if (order?.user_id !== user.id && !userIsAdmin)
      return json({ error: "Akses ditolak" }, 403);

    if (action === "check")
      return json({ success: true, payment: await syncPayment(paymentId) });
    if (action === "cancel") {
      await paygate.cancelTransaction(
        payment.gateway_transaction_id,
        body.reason || "Dibatalkan pengguna",
      );
      await admin.rpc("apply_btzpay_status", {
        p_transaction_id: payment.gateway_transaction_id,
        p_status: "cancel",
        p_raw: {},
        p_reason: body.reason || null,
      });
      return json({ success: true });
    }
    if (action === "refund_mark" && canRefund) {
      await admin.rpc("apply_btzpay_status", {
        p_transaction_id: payment.gateway_transaction_id,
        p_status: "refunded",
        p_raw: {},
        p_reason: body.reason || "Refund dicatat admin",
      });
      return json({ success: true });
    }
    return json({ error: "Aksi tidak dikenal" }, 400);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error("BTZPAY_ERROR:", errorMessage);
    const errorData = (error as { data?: unknown })?.data;
    if (errorData)
      console.error("BTZPAY_ERROR_DATA:", JSON.stringify(errorData));
    if (action === "webhook") {
      const transactionId = String(
        body.pay_id || body.raw?.data?.transactionId || "",
      );
      await admin
        .from("payment_webhook_logs")
        .update({ error_message: errorMessage })
        .eq("gateway_transaction_id", transactionId)
        .eq("verified", false);
    }
    return json(
      {
        success: false,
        error: errorMessage,
      },
      400,
    );
  }
});
