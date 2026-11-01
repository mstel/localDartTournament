import {
  isWebsiteResourcePayload,
  parseWebsiteResourceRequest,
  websiteResourceObjectName,
} from './versioned_resource.ts';

Deno.test('accepts a single resource and rejects invalid resource queries', () => {
  const players = parseWebsiteResourceRequest(
    new URLSearchParams('resource=players'),
  );
  if (players?.resource !== 'players') {
    throw new Error('Player resource was not selected');
  }
  for (const query of [
    'resource=players&page=1',
    'resource=players&resource=rankings',
    'resource=unknown',
    'resource=tournaments&page=0',
    'resource=tournaments&page=1&page=2',
  ]) {
    if (parseWebsiteResourceRequest(new URLSearchParams(query)) !== null) {
      throw new Error(`Invalid resource query was accepted: ${query}`);
    }
  }
});

Deno.test('maps only the requested tournament page to its stored object', () => {
  const request = parseWebsiteResourceRequest(
    new URLSearchParams('resource=tournaments&page=3'),
  );
  if (
    request?.resource !== 'tournaments' ||
    request.page !== 3 ||
    websiteResourceObjectName(request) !==
      'website-v2-tournaments-page-3.json'
  ) {
    throw new Error('Tournament request did not select its own page object');
  }
});

Deno.test('accepts a versioned resource slice and rejects bundled data', () => {
  const request = { resource: 'performance' as const };
  const payload = {
    schemaVersion: 2,
    resource: 'performance',
    generatedAt: '2026-10-28T00:00:00.000Z',
    monthlyPerformance: [{
      playerId: 'player-1',
      period: '2026-10',
      year: 2026,
      month: 10,
      weightedLegs: 18,
      scoring: 72.5,
      average: 51.2,
      checkoutQuote: 38.5,
    }],
  };
  if (!isWebsiteResourcePayload(payload, request)) {
    throw new Error('Valid performance resource was rejected');
  }
  if (
    isWebsiteResourcePayload(
      { ...payload, players: [{ id: 'unrequested-player' }] },
      request,
    )
  ) {
    throw new Error('A resource containing unrelated page data was accepted');
  }
});
