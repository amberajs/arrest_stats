import { createClient } from "npm:@supabase/supabase-js@2.110.5";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_KEY = Deno.env.get("supabase_key")!;

// Initialize client once at the top level
const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

Deno.serve(async (req) => {
  try {
    const { data, hash: hash_value } = await req.json();

    const data_array = Array.isArray(data) ? data : [data];

    if (!data_array.length || !hash_value) {
      throw new Error("INVALID JSON OR MISSING HASH");
    }

    const { data: existing_hash } = await supabase
      .from("hash_log")
      .select("hash_value")
      .eq("hash_value", hash_value)
      .maybeSingle();

    if (existing_hash) {
      return new Response(JSON.stringify({ status: "UNCHANGED" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const records = [];
    for (const item of data_array) {
      const image_str = item.image?.trim() || "";
      const path_parts = image_str.split(/[\\/]/);
      const filename = path_parts[path_parts.length - 1] || "";

      const arrest_id_match = filename.match(/^([^_]+)_/);
      if (!arrest_id_match) continue;
      const arrest_id = parseInt(arrest_id_match[1].trim(), 10);

      const booking_match = filename.match(/_([^\.]+)\.jpg$/i);
      let booking_time = "";
      
      if (booking_match && booking_match[1].length === 14) {
        const ts = booking_match[1];
        booking_time = `${ts.substring(4, 8)}-${ts.substring(0, 2)}-${ts.substring(2, 4)}T${ts.substring(8, 10)}:${ts.substring(10, 12)}:${ts.substring(12, 14)}`;
      }

      const dob_parts = item.dob ? item.dob.split("/") : [];
      if (dob_parts.length !== 3) continue;
      const dob = `${dob_parts[2]}-${dob_parts[0]}-${dob_parts[1]}`;

      const name_parts = item.fullName?.split(",") || [];
      const last_name = name_parts[0]?.trim().toUpperCase() || "";
      const first_middle = name_parts[1]?.trim().split(" ") || [];
      const first_name = first_middle[0]?.toUpperCase() || "";
      const middle_name = first_middle.slice(1).join(" ").toUpperCase() || null;

      if (!booking_time || !item.inmateID || !first_name || !last_name) continue;

      records.push({
        arrest_id: arrest_id,
        booking_time: booking_time,
        inmate_id: parseInt(item.inmateID, 10),
        first_name: first_name,
        middle_name: middle_name,
        last_name: last_name,
        dob: dob,
        race: item.race ? item.race.toUpperCase() : null,
        sex: item.sex ? item.sex.toUpperCase() : null,
        height: item.height || null,
        weight: item.weight || null,
        charge_description: item.chargeDescription ? item.chargeDescription.toUpperCase() : null,
      });
    }

    if (records.length > 0) {
      const { error: rpc_error } = await supabase.rpc("process_recents_batch", {
        payload_hash: hash_value,
        records: records
      });
      if (rpc_error) throw rpc_error;
    }

    return new Response(JSON.stringify({ status: "SUCCESS", count: records.length }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });

  } catch (err: any) {
    const msg = String(err.message || err);
    return new Response(JSON.stringify({ error: msg }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }
});
