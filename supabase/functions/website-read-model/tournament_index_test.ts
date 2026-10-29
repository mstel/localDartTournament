import {
  pageTournamentIndex,
  parseTournamentPage,
  tournamentPageSize,
  type TournamentIndex,
} from './tournament_index.ts';

const makeIndex = (total: number): TournamentIndex => ({
  schemaVersion: 1,
  generatedAt: '2026-10-28T00:00:00.000Z',
  completedTournaments: Array.from({ length: total }, (_, index) => ({
    id: `tournament-${index + 1}`,
    name: `Tournament ${index + 1}`,
    finishedAt: '2026-10-20T00:00:00.000Z',
    startedAt: null,
    createdAt: '2026-10-19T00:00:00.000Z',
    playerCount: 8,
    matchCount: 7,
    mode: 'single_knockout',
    hasImportedArchive: false,
  })),
});

Deno.test('first page returns ten tournaments and indicates more data', () => {
  const response = pageTournamentIndex(makeIndex(12), 1);
  if (
    response.completedTournaments.length !== tournamentPageSize ||
    response.completedTournaments[0].id !== 'tournament-1' ||
    response.tournamentPage.hasMore !== true
  ) {
    throw new Error('First tournament page was not paged correctly');
  }
});

Deno.test('last page returns remaining tournaments and no more flag', () => {
  const response = pageTournamentIndex(makeIndex(12), 2);
  if (
    response.completedTournaments.length !== 2 ||
    response.completedTournaments[0].id !== 'tournament-11' ||
    response.tournamentPage.hasMore !== false
  ) {
    throw new Error('Last tournament page was not paged correctly');
  }
});

Deno.test('rejects invalid page numbers', () => {
  for (const page of ['0', '-1', 'abc', '1.5', '9007199254740992']) {
    if (parseTournamentPage(new URLSearchParams(`page=${page}`)) !== null) {
      throw new Error(`Invalid page ${page} was accepted`);
    }
  }
});

Deno.test('empty index returns a successful empty first page', () => {
  const response = pageTournamentIndex(makeIndex(0), 1);
  if (
    response.completedTournaments.length !== 0 ||
    response.tournamentPage.total !== 0 ||
    response.tournamentPage.hasMore !== false
  ) {
    throw new Error('Empty tournament index was not represented correctly');
  }
});
