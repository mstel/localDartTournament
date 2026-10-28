# Website read-only API

The app publishes one versioned read model alongside its existing private
workspace backup. The read model contains the active player catalog (names,
nickname, city and country), configured ranking names and computed standings,
per-player statistics, best performances, and completed tournaments. Player
profile birthdays, external service IDs and darts setup details are omitted.
Completed tournament records retain their stored result and imported-archive
data; unfinished tournaments and the full workspace backup are not included.

The website reads the model through the `website-read-model` Supabase Edge
Function. It accepts `GET` only and requires a valid Supabase user access token.
The function uses the caller's JWT and the existing owner-folder Storage RLS
policy to read only
`dart-app-backups/<authenticated-user-id>/website-read-model.json`. It does not
use a service-role key or perform database/storage writes. Anonymous requests
are rejected. The response is a single JSON document, so the website does not
need separate Supabase queries for each page section.

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
   request returns `404`; after sync it returns a document with
   `schemaVersion: 1`.

## Astro server-side use

Keep the login and data fetch on the Astro server. Use the authenticated
Supabase session from the server request, and only fetch the API after checking
that session. Do not prerender protected pages, expose the access token to
client-side JavaScript, place credentials in page HTML, or use a service-role
key. The browser should receive rendered page data only after the server has
confirmed the user's session.

Example server-side request after the Astro Supabase integration has resolved
the current user session:

```ts
const session = await getAuthenticatedSession(Astro);
if (!session) return Astro.redirect('/login');

const response = await fetch(
  `${import.meta.env.SUPABASE_URL}/functions/v1/website-read-model`,
  {
    headers: {
      apikey: import.meta.env.SUPABASE_PUBLISHABLE_KEY,
      Authorization: `Bearer ${session.access_token}`,
    },
  },
);
if (!response.ok) throw new Error(`Website data API returned ${response.status}`);
const websiteData = await response.json();
```

`getAuthenticatedSession` above stands for the session helper provided by the
Astro project's Supabase SSR integration; this repository does not include or
modify that separate website project. Render `websiteData` in server-rendered
pages only, and leave tournament administration and write actions in the app.
The API response is privately cacheable for 60 seconds and is varied by the
authorization header.

## Response contract, schema version 1

- `generatedAt`: UTC timestamp of the last generated snapshot.
- `players`: `{ id, firstName, lastName, fullName, nickname, country, city, createdAt }`.
- `rankings`: `{ id, name, type }`, where type is `elo` or `series`.
- `rankingStandings`: `{ rankingId, entries }`; entry fields vary by ranking type
  and include the position and player ID/name.
- `statistics`: `{ playerId, tournaments, matches, wins, losses, draws,
  tournamentWins, legsWon, legsLost, legsDrawn, setsWon, setsLost }`.
- `bestPerformances`: best-performance records with the corresponding `playerId`.
- `completedTournaments`: app tournament JSON objects with a non-null finish
  timestamp. Reopened tournaments are excluded until finalized again.

When changing this contract, increment `schemaVersion`, update this document
and keep the endpoint backward-compatible or update the Astro consumer in the
separate website project at the same time.
