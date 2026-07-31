import { createClient } from "npm:@supabase/supabase-js@2.110.5";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_KEY = Deno.env.get("supabase_key")!;

function normalize(raw_json: any): any {
  if (!raw_json) return {};
  const formatted: any = {};
  for (const key in raw_json) {
    if (Object.prototype.hasOwnProperty.call(raw_json, key)) {
      const snake_key = key.replace(/[A-Z]/g, (l) => `_${l.toLowerCase()}`);
      let val = raw_json[key];
      if (typeof val === "string") {
        val = val.toUpperCase().trim();
        if (snake_key === "expected_release") {
          const parsed = Date.parse(val);
          if (!isNaN(parsed)) val = new Date(parsed).toISOString();
        }
      }
      formatted[snake_key] = val;
    }
  }
  return formatted;
}

Deno.serve(async (req) => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);
  let payload_text = "";

  try {
    payload_text = await req.text();
    if (!payload_text || payload_text.trim() === "") throw new Error("EMPTY PAYLOAD");

    const payload = JSON.parse(payload_text);
    const inmate_id = payload.inmate_id || payload.inmateID;
    const hash_value = payload.hash;
    const raw_inmate = payload.inmate || payload.data || {};
    const raw_offenses = payload.offenses || payload.charges || [];

    if (!inmate_id || !hash_value) throw new Error("MISSING INMATE_ID OR HASH");

    const numeric_inmate_id = parseInt(String(inmate_id), 10);
    if (isNaN(numeric_inmate_id)) throw new Error("INVALID NUMERIC INMATE_ID");

    const sanitized_inmate = normalize(raw_inmate);
    const charges: string[] = [];

    if (Array.isArray(raw_offenses)) {
      raw_offenses.forEach((off: any) => {
        const desc = off?.chargeDescription || off?.charge_description;
        if (desc && typeof desc === "string") {
          const clean = desc.toUpperCase().trim();
          if (!charges.includes(clean)) charges.push(clean);
        }
      });
    }

    const { data: target_id, error: rpc_error } = await supabase.rpc("process_inmate_details", {
      p_inmate_id: numeric_inmate_id,
      p_hash_value: hash_value,
      p_inmate_data: sanitized_inmate,
      p_charges: charges,
    });

    if (rpc_error) throw rpc_error;

    return new Response(JSON.stringify({ status: "SUCCESS", arrest_id: target_id }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err: any) {
    const msg = String(err.message || err).toUpperCase();
    await supabase.from("api_error_log").insert({
      error: msg,
      jail_response: payload_text || null,
    });
    return new Response(JSON.stringify({ error: msg }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }
});
