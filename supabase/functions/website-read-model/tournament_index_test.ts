import {
  isTournamentSummary,
  pageTournamentIndex,
  parseTournamentPage,
  summarizeFullTournament,
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

const makeEnrichedIndex = (total: number): TournamentIndex => ({
  ...makeIndex(total),
  completedTournaments: makeIndex(total).completedTournaments.map(
    (summary, index) => ({
      ...summary,
      winnerId: index === 1 ? null : `player-${index + 1}`,
      winnerName: index === 1 ? null : `Player ${index + 1}`,
      phaseKinds: index % 2 === 0 ? ['table', 'knockout'] : ['table'],
    }),
  ),
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

Deno.test('pagination keeps winner and phase-kind fields', () => {
  const response = pageTournamentIndex(makeEnrichedIndex(12), 1);
  const first = response.completedTournaments[0];
  const second = response.completedTournaments[1];
  if (
    first.winnerId !== 'player-1' ||
    first.winnerName !== 'Player 1' ||
    first.phaseKinds?.join(',') !== 'table,knockout' ||
    second.winnerId !== null ||
    second.winnerName !== null ||
    second.phaseKinds?.join(',') !== 'table'
  ) {
    throw new Error('Winner and phase-kind fields were lost during pagination');
  }
});

Deno.test('summary validation accepts legacy and enriched payloads', () => {
  const legacy = makeIndex(1).completedTournaments[0];
  const enriched = makeEnrichedIndex(2).completedTournaments[0];
  if (!isTournamentSummary(legacy) || !isTournamentSummary(enriched)) {
    throw new Error('Legacy or enriched tournament summary was rejected');
  }
  if (!isTournamentSummary({ ...enriched, winnerId: null, winnerName: null, phaseKinds: [] })) {
    throw new Error('Null winners and empty phase kinds were rejected');
  }
  if (
    isTournamentSummary({ ...enriched, winnerId: 42 }) ||
    isTournamentSummary({ ...enriched, phaseKinds: ['table', 7] })
  ) {
    throw new Error('Malformed winner or phase-kind fields were accepted');
  }
  const legacyPage = pageTournamentIndex(makeIndex(1), 1);
  if (
    legacyPage.completedTournaments.some(
      (summary) =>
        'winnerId' in summary ||
        'winnerName' in summary ||
        'phaseKinds' in summary,
    )
  ) {
    throw new Error('Legacy summaries gained additive fields during paging');
  }
});

Deno.test('summarizeFullTournament carries winner and phase kinds', () => {
  const summary = summarizeFullTournament({
    id: 'finished',
    name: 'Vereinsturnier',
    finishedAt: '2026-10-20T00:00:00.000Z',
    startedAt: null,
    createdAt: '2026-10-19T00:00:00.000Z',
    players: [],
    runStages: [],
    winnerId: 'player-1',
    winnerName: 'Ada Dart',
    phaseKinds: ['table', 'knockout'],
  });
  if (
    summary === null ||
    summary.winnerId !== 'player-1' ||
    summary.winnerName !== 'Ada Dart' ||
    summary.phaseKinds?.join(',') !== 'table,knockout' ||
    !isTournamentSummary(summary)
  ) {
    throw new Error('Full tournament winner and phase kinds were not summarized');
  }
  const legacy = summarizeFullTournament({
    id: 'legacy',
    name: 'Legacy',
    finishedAt: '2026-10-20T00:00:00.000Z',
    startedAt: null,
    createdAt: '2026-10-19T00:00:00.000Z',
    players: [],
    runStages: [],
  });
  if (
    legacy === null ||
    'winnerId' in legacy ||
    'winnerName' in legacy ||
    'phaseKinds' in legacy
  ) {
    throw new Error('Legacy full tournament gained additive fields');
  }
});
