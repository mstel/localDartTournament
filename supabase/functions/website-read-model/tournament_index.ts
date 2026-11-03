export const tournamentPageSize = 10;

export type TournamentSummary = {
  id: string;
  name: string;
  finishedAt: string;
  startedAt: string | null;
  createdAt: string;
  playerCount: number;
  matchCount: number;
  mode: string;
  hasImportedArchive: boolean;
};

export type TournamentIndex = {
  schemaVersion: 1;
  generatedAt: string;
  completedTournaments: TournamentSummary[];
};

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const isDateString = (value: unknown): value is string =>
  typeof value === 'string' && Number.isFinite(Date.parse(value));

export function parseTournamentPage(
  searchParams: URLSearchParams,
): number | null {
  const rawPage = searchParams.get('page');
  if (rawPage === null) return 1;
  if (!/^[1-9]\d*$/.test(rawPage)) return null;
  const page = Number(rawPage);
  return Number.isSafeInteger(page) ? page : null;
}

export function isTournamentIndex(
  value: unknown,
): value is TournamentIndex {
  if (
    !isRecord(value) ||
    value.schemaVersion !== 1 ||
    !isDateString(value.generatedAt) ||
    !Array.isArray(value.completedTournaments)
  ) {
    return false;
  }
  return value.completedTournaments.every(isTournamentSummary);
}

function isTournamentSummary(value: unknown): value is TournamentSummary {
  return (
    isRecord(value) &&
    typeof value.id === 'string' &&
    typeof value.name === 'string' &&
    isDateString(value.finishedAt) &&
    (value.startedAt === null || isDateString(value.startedAt)) &&
    isDateString(value.createdAt) &&
    typeof value.playerCount === 'number' &&
    Number.isSafeInteger(value.playerCount) &&
    value.playerCount >= 0 &&
    typeof value.matchCount === 'number' &&
    Number.isSafeInteger(value.matchCount) &&
    value.matchCount >= 0 &&
    typeof value.mode === 'string' &&
    typeof value.hasImportedArchive === 'boolean'
  );
}

export function pageTournamentIndex(
  index: TournamentIndex,
  page: number,
) {
  const start = (page - 1) * tournamentPageSize;
  return {
    schemaVersion: 1,
    generatedAt: index.generatedAt,
    completedTournaments: index.completedTournaments.slice(
      start,
      start + tournamentPageSize,
    ).map((tournament) => ({
      id: tournament.id,
      name: tournament.name,
      finishedAt: tournament.finishedAt,
      startedAt: tournament.startedAt,
      createdAt: tournament.createdAt,
      playerCount: tournament.playerCount,
      matchCount: tournament.matchCount,
      mode: tournament.mode,
      hasImportedArchive: tournament.hasImportedArchive,
    })),
    tournamentPage: {
      page,
      pageSize: tournamentPageSize,
      total: index.completedTournaments.length,
      hasMore: start + tournamentPageSize < index.completedTournaments.length,
    },
  };
}

export function summarizeFullTournament(
  tournament: Record<string, unknown>,
): TournamentSummary | null {
  const players = tournament.players;
  const runStages = tournament.runStages;
  const createdAt = tournament.createdAt;
  const finishedAt = tournament.finishedAt;
  const startedAt = tournament.startedAt;
  let normalizedStartedAt: string | null = null;
  if (startedAt !== null && startedAt !== undefined) {
    if (!isDateString(startedAt)) return null;
    normalizedStartedAt = startedAt;
  }
  if (
    typeof tournament.id !== 'string' ||
    typeof tournament.name !== 'string' ||
    !isDateString(finishedAt) ||
    !isDateString(createdAt) ||
    !Array.isArray(players) ||
    !Array.isArray(runStages)
  ) {
    return null;
  }

  let matchCount = tournament.leagueMatch == null ? 0 : 1;
  for (const stage of runStages) {
    if (!isRecord(stage)) return null;
    if (stage.kind === 'groups') {
      if (!Array.isArray(stage.groups)) return null;
      for (const group of stage.groups) {
        if (!isRecord(group) || !Array.isArray(group.matches)) return null;
        matchCount += group.matches.length;
      }
    } else if (stage.kind === 'single_knockout') {
      if (!Array.isArray(stage.rounds) || !Array.isArray(stage.placementMatches)) {
        return null;
      }
      for (const round of stage.rounds) {
        if (!Array.isArray(round)) return null;
        matchCount += round.length;
      }
      matchCount += stage.placementMatches.length;
    }
  }

  const stages = Array.isArray(tournament.stages) ? tournament.stages : [];
  const firstStage = stages.find(isRecord);
  const firstRunStage = runStages.find(isRecord);
  const archive = isRecord(tournament.importedArchive)
    ? tournament.importedArchive
    : null;
  let mode = 'unknown';
  if (typeof archive?.mode === 'string') {
    mode = archive.mode;
  } else if (typeof firstStage?.type === 'string') {
    mode = firstStage.type;
    if (
      mode === 'groups' &&
      typeof firstRunStage?.groupPlayType === 'string'
    ) {
      mode = `groups:${firstRunStage.groupPlayType}`;
    }
  } else if (typeof firstRunStage?.kind === 'string') {
    mode = firstRunStage.kind;
    if (
      mode === 'groups' &&
      typeof firstRunStage.groupPlayType === 'string'
    ) {
      mode = `groups:${firstRunStage.groupPlayType}`;
    }
  }

  return {
    id: tournament.id,
    name: tournament.name,
    finishedAt,
    startedAt: normalizedStartedAt,
    createdAt,
    playerCount: players.length,
    matchCount,
    mode,
    hasImportedArchive: tournament.importedArchive != null,
  };
}
