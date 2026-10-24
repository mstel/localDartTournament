import { createClient } from 'npm:@supabase/supabase-js@2.117.2';

const bucket = 'dart-app-backups';
const objectName = 'website-read-model.json';
const maximumBytes = 32 * 1024 * 1024;

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'private, max-age=60',
      'Vary': 'Authorization',
      'X-Content-Type-Options': 'nosniff',
    },
  });

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

Deno.serve(async (request: Request) => {
  if (request.method !== 'GET') {
    return jsonResponse({ error: 'method_not_allowed' }, 405);
  }

  const authorization = request.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) {
    return jsonResponse({ error: 'authentication_required' }, 401);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const publishableKey = Deno.env.get('SUPABASE_ANON_KEY')
    ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY');
  if (!url || !publishableKey) {
    return jsonResponse({ error: 'server_configuration_error' }, 503);
  }

  const supabase = createClient(url, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError) {
    if (userError.status === 401) {
      return jsonResponse({ error: 'authentication_required' }, 401);
    }
    console.error('website-read-model authentication failed');
    return jsonResponse({ error: 'authentication_service_unavailable' }, 502);
  }
  if (!user) {
    return jsonResponse({ error: 'authentication_required' }, 401);
  }

  const objectPath = `${user.id}/${objectName}`;
  const { data: file, error: downloadError } = await supabase.storage
    .from(bucket)
    .download(objectPath);
  if (downloadError) {
    if (Number(downloadError.statusCode) === 404) {
      return jsonResponse({ error: 'website_data_not_published' }, 404);
    }
    console.error('website-read-model storage download failed', {
      statusCode: downloadError.statusCode,
    });
    return jsonResponse({ error: 'website_data_unavailable' }, 502);
  }
  if (!file) {
    console.error('website-read-model storage returned no object or error');
    return jsonResponse({ error: 'website_data_unavailable' }, 502);
  }
  if (file.size > maximumBytes) {
    return jsonResponse({ error: 'website_data_too_large' }, 413);
  }

  let readModel: unknown;
  try {
    readModel = JSON.parse(await file.text());
  } catch {
    return jsonResponse({ error: 'website_data_invalid' }, 502);
  }
  if (!isRecord(readModel) || readModel.schemaVersion !== 1) {
    return jsonResponse({ error: 'website_data_invalid' }, 502);
  }
  const {
    generatedAt,
    players,
    rankings,
    rankingStandings,
    statistics,
    bestPerformances,
    completedTournaments,
  } = readModel;
  if (
    typeof generatedAt !== 'string' ||
    !Number.isFinite(Date.parse(generatedAt)) ||
    !Array.isArray(players) ||
    !players.every(isRecord) ||
    !Array.isArray(rankings) ||
    !rankings.every(isRecord) ||
    !Array.isArray(rankingStandings) ||
    !rankingStandings.every(isRecord) ||
    !Array.isArray(statistics) ||
    !statistics.every(isRecord) ||
    !Array.isArray(bestPerformances) ||
    !bestPerformances.every(isRecord) ||
    !Array.isArray(completedTournaments) ||
    !completedTournaments.every(isRecord)
  ) {
    return jsonResponse({ error: 'website_data_invalid' }, 502);
  }

  return jsonResponse({
    schemaVersion: 1,
    generatedAt,
    players,
    rankings,
    rankingStandings,
    statistics,
    bestPerformances,
    completedTournaments: completedTournaments.filter(
      (tournament) =>
        typeof tournament.finishedAt === 'string' &&
        Number.isFinite(Date.parse(tournament.finishedAt)) &&
        tournament.reopenedForCorrections !== true,
    ),
  });
});
