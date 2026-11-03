# Website read-only API

For compatibility, the app continues to publish the version-1 full read model
alongside its existing private workspace backup. That model contains the
active player catalog (names,
nickname, city and country), configured ranking names and computed standings,
per-player statistics, best performances, and completed tournaments. Player
profile birthdays, external service IDs and darts setup details are omitted.
Completed tournament records retain their stored result and imported-archive
data; unfinished tournaments and the full workspace backup are not included.

The website reads the model through the `website-read-model` Supabase Edge
Function. It accepts `GET` only and requires a valid Supabase user access token.
The function uses the caller's JWT and the existing owner-folder Storage RLS
policy to read only
objects under `dart-app-backups/<authenticated-user-id>/`. It does not use a
service-role key or perform database/storage writes. Anonymous requests are
rejected. The app publishes the full `website-read-model.json` and compact
`website-tournament-index.json` for version-1 compatibility, plus independent
version-2 resources. New consumers should use the version-2 route, which reads
only the requested resource or tournament page from Storage.

Use
`GET /functions/v1/website-read-model?version=2&resource=tournaments&page=1`
to load up to ten completed tournament summaries. Increase the 1-based page
number to load the next page. Version-2 reads require a resource name. Invalid
resource/page combinations return `400`; a resource not yet published returns
`404`. Empty tournament data is published as an empty page 1 with
`hasMore: false`.

The version-1 route remains available:
`GET /functions/v1/website-read-model?view=tournaments&page=1` still reads its
compact index and falls back to the full v1 object for accounts that have not
published the index. Requests without a view or version parameter retain the
legacy full v1 response.

## Deploy

1. Confirm that the private `dart-app-backups` bucket and its owner-folder
   Storage policies from `supabase/fresh_sync_schema.sql` are installed in the
   same Supabase project as the app. Do not make this bucket public.
2. Deploy the read-only function from the repository root:

   ```powershell
   supabase functions deploy website-read-model
   ```

   The repository config enables JWT verification. The function uses Supabase's
   `SUPABASE_URL` and `SUPABASE_ANON_KEY`; no secret key needs to be configured
   in Astro or the Flutter app.
3. Install this app update. After the operator logs in, use **Jetzt abgleichen**
   in **Einstellungen → Daten** to publish the read model alongside the private
   backup. An existing account with an existing backup publishes it on its next
   manual app synchronization; local data and the existing backup are not
   migrated, replaced or deleted by this feature.
4. Verify the endpoint with the operator's short-lived access token. A logged
   out request must return `401`; before the first publication an authenticated
   request returns `404`; after sync the legacy request returns a document with
   `schemaVersion: 1` and a v2 resource request returns `schemaVersion: 2` and
   the matching `resource`. Tournament requests return at most ten summaries
   and a `tournamentPage` object containing `page`, `pageSize`, `total`, and
   `hasMore`.

## Astro server-side use

Keep the login and data fetch on the Astro server. Use the authenticated
Supabase session from the server request, and only fetch the API after checking
that session. Do not prerender protected pages, expose the access token to
client-side JavaScript, place credentials in page HTML, or use a service-role
key. The browser should receive rendered page data only after the server has
confirmed the user's session.

Example server-side request for one resource (choose the resource needed by
the current server-rendered page) after the Astro Supabase integration has
resolved the current user session:

```ts
const session = await getAuthenticatedSession(Astro);
if (!session) return Astro.redirect('/login');

const resource = 'players';
const response = await fetch(
  `${import.meta.env.SUPABASE_URL}/functions/v1/website-read-model?version=2&resource=${resource}`,
  {
    headers: {
      apikey: import.meta.env.SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${session.access_token}`,
    },
  },
);
if (!response.ok) throw new Error(`Website data API returned ${response.status}`);
const pageData = await response.json();
```

`getAuthenticatedSession` above stands for the session helper provided by the
Astro project's Supabase SSR integration; this repository does not include or
modify that separate website project. Render `pageData` in server-rendered
pages only, and leave tournament administration and write actions in the app.
The API response is privately cacheable for 60 seconds and is varied by the
authorization header.

## Response contract, schema version 2

- `generatedAt`: UTC timestamp of the last generated snapshot.
- `players`: `{ id, firstName, lastName, fullName, nickname, country, city, createdAt }`.
- `rankings`: `{ id, name, type }`, where type is `elo` or `series`.
- `rankingStandings`: `{ rankingId, entries }`; entry fields vary by ranking type
  and include the position and player ID/name.
- `statistics`: `{ playerId, tournaments, matches, wins, losses, draws,
  tournamentWins, legsWon, legsLost, legsDrawn, setsWon, setsLost, currentForm }`.
  `currentForm` contains `weightedLegs`, `scoring`, `average`, and `checkoutQuote`
  for the most recent 100 weighted legs, limited to completed calendar months.
- `currentForm`: one `{ playerId, weightedLegs, scoring, average, checkoutQuote }`
  record per player, also available independently in the version-2 performance
  resource.
- `bestPerformances`: best-performance records with the corresponding `playerId`.
  The `type` is `bigFish170`, `score171Plus`, `score180`, `highFinish`,
  `bullseyeFinish`, or `shortLeg`; Bullseye finish records may include a
  user-entered `details` string. Legacy `score170` records are exposed as
  `score171Plus`.
- `completedTournaments`: app tournament JSON objects with a non-null finish
  timestamp. Reopened tournaments are excluded until finalized again.

The endpoint accepts legacy schema-version-1 read models and continues to
serve them as version 1. Version 2 read models include current-form statistics
and are returned as version 2.

## Tournament page response

The `view=tournaments` response keeps `schemaVersion` and `generatedAt`, and
contains only compact entries in `completedTournaments`: `id`, `name`,
`finishedAt`, `startedAt`, `createdAt`, `playerCount`, `matchCount`, `mode`,
and `hasImportedArchive`. `tournamentPage` contains the requested `page`, the
fixed `pageSize` of 10, the total number of completed tournaments, and
`hasMore`.

## Version-2 resource contract

Request one resource per call. `version=2` and `resource` are required;
`page` is accepted only for `tournaments`.

| Request | Response data |
| --- | --- |
| `?version=2&resource=players` | `players` |
| `?version=2&resource=rankings` | `rankings`, `rankingStandings` |
| `?version=2&resource=statistics` | `statistics`, `bestPerformances`, `currentForm` |
| `?version=2&resource=performance` | `monthlyPerformance`, `currentForm` |
| `?version=2&resource=tournaments&page=N` | One page of `completedTournaments` and `tournamentPage` |

Every response has `schemaVersion: 2`, `resource`, and `generatedAt`. A
resource response contains only its listed data keys; the endpoint reads and
validates exactly the corresponding Storage object. Tournament pages are
pre-sliced and persisted separately, so a page request does not download the
index or any other tournament page. Pages contain at most ten summaries. An
empty tournament collection is represented by page 1 with an empty list.

`monthlyPerformance` contains one row per manually maintained player/month
record: `playerId`, `period` (`YYYY-MM`), `year`, `month`, `weightedLegs`,
`scoring`, `average`, and `checkoutQuote` (the app's stored checkout-rate
percentage). Nullable scoring values stay null; no values are inferred from
tournament results. Profile-private details appear only in the independently
requested `players` resource.

`currentForm` contains one record per player with the metrics calculated over
up to the latest 100 weighted legs. Monthly statistics are weighted by their
leg counts, and the current, incomplete calendar month is excluded. Metrics
remain null when no values have been recorded for them.

### Compatibility and migration

The endpoint remains compatible with existing v1 full read-model snapshots;
new synchronizations publish schema version 2. The version-2 resource and
`view=tournaments` contracts remain independently versioned. No local records
or existing backups are migrated or removed. Existing
accounts publish the additional objects on their next synchronization. The
homepage can migrate resource by resource in its separate project, then stop
requesting the v1 full document when ready. Do not remove v1 objects or change
the default route until that consumer migration has been coordinated. Future
incompatible resource changes must increment the resource schema version and
keep the legacy v1 route available for the compatibility period.
