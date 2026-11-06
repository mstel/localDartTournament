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
    currentForm: [],
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
  const updatedPayload = {
    ...payload,
    monthlyClubPerformance: [{
      year: 2026,
      month: 10,
      period: '2026-10',
      matches: 9,
      weightedLegs: 18,
      scoring: 72.5,
      average: 51.2,
      checkoutQuote: 38.5,
    }],
    importedMonthlyStatistics: [{
      playerId: 'player-1',
      sourcePlayerName: 'Ada Dart',
      period: '2026-10',
      year: 2026,
      month: 10,
      threeDartAverage: 51.2,
      firstNineAverage: 60,
      checkoutPercentage: 38.5,
      legs: 18,
      matches: 9,
    }],
  };
  if (!isWebsiteResourcePayload(updatedPayload, request)) {
    throw new Error('Updated performance resource fields were rejected');
  }
  if (
    isWebsiteResourcePayload(
      { ...updatedPayload, monthlyClubPerformance: 'invalid' },
      request,
    )
  ) {
    throw new Error('Invalid club performance data was accepted');
  }
});

Deno.test('accepts achievement standings with player progress', () => {
  const request = parseWebsiteResourceRequest(
    new URLSearchParams('resource=achievements'),
  );
  if (request?.resource !== 'achievements') {
    throw new Error('Achievement resource was not selected');
  }
  const payload = {
    schemaVersion: 2,
    resource: 'achievements',
    generatedAt: '2026-10-28T00:00:00.000Z',
    rankingAchievements: [{
      rankingId: 'ranking-1',
      rankingName: 'Vereinsrangliste',
      rankingType: 'series',
      players: [{
        playerId: 'player-1',
        playerName: 'Ada Dart',
        level: 4,
        totalExperiencePoints: 125,
        levelEligibleExperiencePoints: 115,
        levelStartExperiencePoints: 100,
        nextLevelExperiencePoints: 150,
        experiencePointsToNextLevel: 35,
        levelProgress: 0.6,
        achievements: [{
          id: 'legs-won-10',
          name: 'Erste zehn Legs',
          description: 'Gewinne zehn Legs.',
          category: 'consistency',
          currentValue: 10,
          target: 10,
          status: 'completed',
          isCompleted: true,
          experiencePoints: 25,
          contributesToLevel: true,
          unlockedAt: '2026-10-01T10:00:00.000Z',
        }],
      }],
    }],
  };
  if (!isWebsiteResourcePayload(payload, request)) {
    throw new Error('Valid achievements resource was rejected');
  }
  if (
    isWebsiteResourcePayload(
      { ...payload, statistics: [] },
      request,
    )
  ) {
    throw new Error('Achievement resource containing unrelated data was accepted');
  }
});
