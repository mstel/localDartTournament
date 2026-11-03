export const websiteResourceNames = [
  'players',
  'rankings',
  'statistics',
  'performance',
  'achievements',
  'tournaments',
] as const;

export type WebsiteResourceName = typeof websiteResourceNames[number];

export type WebsiteResourceRequest = {
  resource: WebsiteResourceName;
  page?: number;
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const hasExactKeys = (
  value: Record<string, unknown>,
  resourceKeys: string[],
): boolean => {
  const expected = new Set([
    'schemaVersion',
    'resource',
    'generatedAt',
    ...resourceKeys,
  ]);
  return Object.keys(value).length === expected.size &&
    Object.keys(value).every((key) => expected.has(key));
};

const isAchievementStanding = (value: unknown): value is Record<string, unknown> =>
  isRecord(value) &&
  typeof value.rankingId === 'string' &&
  typeof value.rankingName === 'string' &&
  typeof value.rankingType === 'string' &&
  Array.isArray(value.players) &&
  value.players.every((player) =>
    isRecord(player) &&
    typeof player.playerId === 'string' &&
    typeof player.playerName === 'string' &&
    typeof player.level === 'number' &&
    typeof player.totalExperiencePoints === 'number' &&
    typeof player.levelEligibleExperiencePoints === 'number' &&
    typeof player.levelStartExperiencePoints === 'number' &&
    typeof player.nextLevelExperiencePoints === 'number' &&
    typeof player.experiencePointsToNextLevel === 'number' &&
    typeof player.levelProgress === 'number' &&
    Array.isArray(player.achievements) &&
    player.achievements.every((achievement) =>
      isRecord(achievement) &&
      typeof achievement.id === 'string' &&
      typeof achievement.name === 'string' &&
      typeof achievement.description === 'string' &&
      typeof achievement.category === 'string' &&
      typeof achievement.currentValue === 'number' &&
      typeof achievement.target === 'number' &&
      typeof achievement.status === 'string' &&
      typeof achievement.isCompleted === 'boolean' &&
      typeof achievement.experiencePoints === 'number' &&
      typeof achievement.contributesToLevel === 'boolean' &&
      (achievement.unlockedAt === null ||
        typeof achievement.unlockedAt === 'string')
    )
  );

export function parseWebsiteResourceRequest(
  searchParams: URLSearchParams,
): WebsiteResourceRequest | null {
  const resources = searchParams.getAll('resource');
  if (resources.length !== 1) return null;
  const resource = resources[0];
  if (!websiteResourceNames.includes(resource as WebsiteResourceName)) {
    return null;
  }
  const pages = searchParams.getAll('page');
  if (resource !== 'tournaments') {
    return pages.length === 0
      ? { resource: resource as WebsiteResourceName }
      : null;
  }
  if (pages.length > 1) return null;
  const page = pages.length === 0 ? 1 : Number(pages[0]);
  if (
    !Number.isSafeInteger(page) ||
    page < 1 ||
    pages.length === 1 && !/^[1-9]\d*$/.test(pages[0])
  ) {
    return null;
  }
  return { resource: 'tournaments', page };
}

export function websiteResourceObjectName(
  request: WebsiteResourceRequest,
): string {
  if (request.resource === 'tournaments') {
    return `website-v2-tournaments-page-${request.page}.json`;
  }
  return `website-v2-${request.resource}.json`;
}

export function isWebsiteResourcePayload(
  value: unknown,
  request: WebsiteResourceRequest,
): value is Record<string, unknown> {
  if (
    !isRecord(value) ||
    value.schemaVersion !== 2 ||
    value.resource !== request.resource ||
    typeof value.generatedAt !== 'string' ||
    !Number.isFinite(Date.parse(value.generatedAt))
  ) {
    return false;
  }
  switch (request.resource) {
    case 'players':
      return hasExactKeys(value, ['players']) &&
        Array.isArray(value.players) &&
        value.players.every(isRecord);
    case 'rankings':
      return hasExactKeys(value, ['rankings', 'rankingStandings']) &&
        Array.isArray(value.rankings) &&
        value.rankings.every(isRecord) &&
        Array.isArray(value.rankingStandings) &&
        value.rankingStandings.every(isRecord);
    case 'statistics':
      return hasExactKeys(value, [
        'statistics',
        'bestPerformances',
        'currentForm',
      ]) &&
        Array.isArray(value.statistics) &&
        value.statistics.every(isRecord) &&
        Array.isArray(value.bestPerformances) &&
        value.bestPerformances.every(isRecord) &&
        Array.isArray(value.currentForm) &&
        value.currentForm.every(isRecord);
    case 'performance':
      return hasExactKeys(value, ['monthlyPerformance', 'currentForm']) &&
        Array.isArray(value.monthlyPerformance) &&
        value.monthlyPerformance.every((entry) =>
          isRecord(entry) &&
          typeof entry.playerId === 'string' &&
          typeof entry.period === 'string' &&
          typeof entry.year === 'number' &&
          typeof entry.month === 'number' &&
          typeof entry.weightedLegs === 'number'
        ) &&
        Array.isArray(value.currentForm) &&
        value.currentForm.every(isRecord);
    case 'achievements':
      return hasExactKeys(value, ['rankingAchievements']) &&
        Array.isArray(value.rankingAchievements) &&
        value.rankingAchievements.every(isAchievementStanding);
    case 'tournaments':
      return hasExactKeys(value, ['completedTournaments', 'tournamentPage']) &&
        Array.isArray(value.completedTournaments) &&
        value.completedTournaments.every(isRecord) &&
        isRecord(value.tournamentPage) &&
        value.tournamentPage.page === request.page &&
        typeof value.tournamentPage.pageSize === 'number' &&
        typeof value.tournamentPage.total === 'number' &&
        typeof value.tournamentPage.hasMore === 'boolean';
  }
}
