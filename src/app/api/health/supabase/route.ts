import { NextResponse } from "next/server";

import { getSupabaseConfig } from "@/lib/supabase/env";

export const dynamic = "force-dynamic";

export async function GET() {
  let url: string;
  let publishableKey: string;

  try {
    ({ url, publishableKey } = getSupabaseConfig());
  } catch {
    return NextResponse.json(
      {
        ok: false,
        status: "configuration_missing",
      },
      { status: 503 },
    );
  }

  try {
    const response = await fetch(`${url}/auth/v1/health`, {
      cache: "no-store",
      headers: {
        apikey: publishableKey,
      },
      signal: AbortSignal.timeout(5_000),
    });

    if (!response.ok) {
      return NextResponse.json(
        {
          ok: false,
          status: "unreachable",
        },
        { status: 503 },
      );
    }

    return NextResponse.json({
      ok: true,
      status: "connected",
    });
  } catch {
    return NextResponse.json(
      {
        ok: false,
        status: "unreachable",
      },
      { status: 503 },
    );
  }
}
