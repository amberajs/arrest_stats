import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cleanStr = (val?: string): string | undefined =>
  val?.trim() ? val.trim().toUpperCase() : undefined;

function parseDOB(dob?: string): string | undefined {
  const match = dob?.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  return match ? `${match[3]}-${match[1]}-${match[2]}` : undefined;
}

function parseImageSource(source?: string) {
  if (!source) return { arrestId: null, bookingTime: null };

  const match = source.match(/(\d+)_(\d{14})\.jpg$/i);
  if (!match) return { arrestId: null, bookingTime: null };

  const [, idStr, ts] = match;
  const bookingTime = `${ts.slice(4, 8)}-${ts.slice(0, 2)}-${ts.slice(2, 4)}T${
    ts.slice(8, 10)
  }:${ts.slice(10, 12)}:${ts.slice(12, 14)}`;

  return {
    arrestId: parseInt(idStr, 10) || null,
    bookingTime,
  };
}

Deno.serve(async (req) => {
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
      });
    }
    const body = await req.json();
    const record = body?.record ?? body ?? {};
    const rawData = record?.raw_json ?? record;

    const rawInmate = rawData?.inmate || {};
    const rawOffenses = Array.isArray(rawData?.offenses)
      ? rawData.offenses
      : [];
    const profileImages = Array.isArray(rawData?.profileImages)
      ? rawData.profileImages
      : [];

    const payloadId = record?.payload_id ?? null;
    const { arrestId, bookingTime } = parseImageSource(
      profileImages[0]?.source,
    );

    const chargesSet = new Set<string>();
    for (const off of rawOffenses) {
      const clean = cleanStr(off?.chargeDescription);
      if (clean) chargesSet.add(clean);
    }
    const charges = chargesSet.size > 0 ? Array.from(chargesSet) : undefined;

    const recordItem = {
      payload_id: payloadId,
      arrest_id: arrestId,
      booking_time: bookingTime,
      inmate_id: rawInmate.inmateID ? Number(rawInmate.inmateID) : undefined,
      first_name: cleanStr(rawInmate.firstName),
      middle_name: cleanStr(rawInmate.middleName),
      last_name: cleanStr(rawInmate.lastName),
      dob: parseDOB(rawInmate.dob),
      arresting_location: cleanStr(rawInmate.arrestingLocation),
      arrest_agency: cleanStr(rawInmate.arrestAgency),
      arresting_officer: cleanStr(rawInmate.arrestingOfficer),
      race: cleanStr(rawInmate.race),
      sex: cleanStr(rawInmate.sex),
      height: rawInmate.height,
      weight: rawInmate.weight,
      charges,
    };

    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const { data, error } = await supabaseClient.rpc("process_arrest_payload", {
      records_json: [recordItem],
    });

    if (error) throw error;

    return new Response(
      JSON.stringify({
        status: "SUCCESS",
        count: data?.[0]?.inserted_count,
        record: recordItem,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (err: any) {
    return new Response(
      JSON.stringify({ error: err?.message || String(err) }),
      { status: 400, headers: { "Content-Type": "application/json" } },
    );
  }
});
