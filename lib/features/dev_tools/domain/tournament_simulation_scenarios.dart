import '../../tournaments/domain/tournament_models.dart';
import '../../tournaments/domain/player_withdrawal.dart';
import 'tournament_simulation_engine.dart';
import '../../league/domain/league_match.dart';

/// League fixtures have team points instead of advancing players.
/// Shared production preset for the league branch of the development matrix.
LeagueMatch rhlDevelopmentScenario() => LeagueMatch.rhl(
  homeTeam: 'Heim',
  awayTeam: 'Gast',
  homePlayers: ['H1', 'H2', 'H3', 'H4'],
  awayPlayers: ['G1', 'G2', 'G3', 'G4'],
);

const tournamentDevelopmentScenarios = [
  TournamentSimulationScenario(
    name: 'Begrenzte Gruppe: 13 Teilnehmer mit maximal 5 Spielen und Finale',
    playerCount: 13,
    stages: [
      SimulationGroupStageSpec(
        name: 'Gruppe',
        qualifiers: 2,
        groupSizes: [13],
        maxGamesPerPlayer: [5],
        fixedPerGroup: 2,
      ),
      SimulationEliminationStageSpec(
        name: 'Finale',
        qualifiers: 1,
        lossLimit: 1,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Begrenzte Gruppe: 12 Teilnehmer mit maximal 5 Spielen',
    playerCount: 12,
    stages: [
      SimulationGroupStageSpec(
        name: 'Gruppe',
        qualifiers: 1,
        groupSizes: [12],
        maxGamesPerPlayer: [5],
        fixedPerGroup: 1,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Challonge 37: Siebenergruppe und KO mit Platz 3',
    playerCount: 7,
    stages: [
      SimulationGroupStageSpec(
        name: 'Gruppe A',
        qualifiers: 4,
        groupSizes: [7],
        fixedPerGroup: 4,
      ),
      SimulationEliminationStageSpec(
        name: 'KO',
        qualifiers: 1,
        lossLimit: 1,
        placementPlaces: [3],
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Ausstieg: zwei Teilnehmer im KO',
    playerCount: 8,
    withdrawnPlayers: [0, 7],
    stages: [
      SimulationEliminationStageSpec(name: 'KO', qualifiers: 1, lossLimit: 1),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Ausstieg: Gruppe und KO',
    playerCount: 8,
    withdrawnPlayers: [0],
    stages: [
      SimulationGroupStageSpec(
        name: 'Gruppe',
        qualifiers: 4,
        groupSizes: [4, 4],
        fixedPerGroup: 2,
      ),
      SimulationEliminationStageSpec(name: 'KO', qualifiers: 1, lossLimit: 1),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Ausstieg: ignorierte Doppel-KO-Begegnungen',
    playerCount: 8,
    withdrawnPlayers: [0],
    withdrawalMode: WithdrawalResultMode.ignoreOpen,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Doppel KO',
        qualifiers: 1,
        lossLimit: 2,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Ausstieg: Triple-KO',
    playerCount: 7,
    withdrawnPlayers: [0],
    stages: [
      SimulationEliminationStageSpec(
        name: 'Triple KO',
        qualifiers: 1,
        lossLimit: 3,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Swiss mit Freilosen und KO',
    playerCount: 13,
    stages: [
      SimulationGroupStageSpec(
        name: 'Swiss',
        qualifiers: 4,
        groupSizes: [13],
        playTypes: ['swiss'],
        roundRobinRepeats: [4],
        fixedPerGroup: 4,
      ),
      SimulationEliminationStageSpec(
        name: 'Finale',
        qualifiers: 1,
        lossLimit: 1,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Swiss mit Unentschieden',
    playerCount: 8,
    stages: [
      SimulationGroupStageSpec(
        name: 'Swiss',
        qualifiers: 1,
        groupSizes: [8],
        playTypes: ['swiss'],
        roundRobinRepeats: [3],
        fixedPerGroup: 1,
        gameFormat: TournamentGameFormat(bestOfLegs: 4),
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Finder: KO-Vorrunde, Mini-KO-Gruppen und Triple-KO',
    playerCount: 12,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Vorrunde',
        qualifiers: 6,
        lossLimit: 1,
      ),
      SimulationGroupStageSpec(
        name: 'Mini-KO-Gruppen',
        qualifiers: 4,
        groupSizes: [3, 3],
        playTypes: ['mini_knockout', 'mini_knockout'],
        fixedPerGroup: 2,
      ),
      SimulationEliminationStageSpec(
        name: 'Triple-KO-Finale',
        qualifiers: 1,
        lossLimit: 3,
        finalEndsTournament: true,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Doppel: Gruppen und KO',
    playerCount: 6,
    teamSize: 2,
    stages: [
      SimulationGroupStageSpec(
        name: 'Gruppen',
        qualifiers: 4,
        groupSizes: [3, 3],
        fixedPerGroup: 2,
      ),
      SimulationEliminationStageSpec(
        name: 'Finale',
        qualifiers: 1,
        lossLimit: 1,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Viererteams mit Freilosen',
    playerCount: 5,
    teamSize: 4,
    stages: [
      SimulationEliminationStageSpec(name: 'KO', qualifiers: 1, lossLimit: 1),
    ],
  ),
  TournamentSimulationScenario(
    name: 'KO mit Platz 3, 5, 7, 9 und 15',
    playerCount: 16,
    stages: [
      SimulationEliminationStageSpec(
        name: 'KO',
        qualifiers: 1,
        lossLimit: 1,
        placementPlaces: [3, 5, 7, 9, 15],
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Mini-KO mit optionalen Platzierungsspielen',
    playerCount: 16,
    stages: [
      SimulationGroupStageSpec(
        name: 'Mini-KO',
        qualifiers: 6,
        groupSizes: [8, 8],
        playTypes: ['mini_knockout', 'mini_knockout'],
        fixedPerGroup: 3,
        placementPlaces: [5, 7],
      ),
      SimulationEliminationStageSpec(
        name: 'Finale',
        qualifiers: 1,
        lossLimit: 1,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Doppel-KO mit entscheidendem Finale',
    playerCount: 7,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Doppel-KO',
        qualifiers: 1,
        lossLimit: 2,
        finalEndsTournament: true,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Doppel-KO mit Platzierungsspielen fuer Rang 5 und 7',
    playerCount: 8,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Doppel-KO',
        qualifiers: 1,
        lossLimit: 2,
        placementPlaces: [5, 7],
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Triple-KO mit entscheidendem Finale',
    playerCount: 7,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Triple-KO',
        qualifiers: 1,
        lossLimit: 3,
        finalEndsTournament: true,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Triple-KO mit Platzierungsspiel fuer Rang 5',
    playerCount: 8,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Triple-KO',
        qualifiers: 1,
        lossLimit: 3,
        placementPlaces: [5],
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Kratzer mit zwei Sechsergruppen',
    playerCount: 12,
    boards: 2,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Kratzer',
        qualifiers: 1,
        lossLimit: 2,
        isKratzer: true,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Kratzer mit 5 Leben und einem unbesetzten Sitz',
    playerCount: 7,
    boards: 1,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Kratzer',
        qualifiers: 1,
        lossLimit: 5,
        isKratzer: true,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Kratzer mit 10 Leben und mehreren Boards',
    playerCount: 13,
    boards: 3,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Kratzer',
        qualifiers: 1,
        lossLimit: 10,
        isKratzer: true,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Bo4 Gruppen mit Unentschieden und Bo5 KO',
    playerCount: 8,
    stages: [
      SimulationGroupStageSpec(
        name: 'Gruppen',
        qualifiers: 4,
        groupSizes: [4, 4],
        fixedPerGroup: 2,
        gameFormat: TournamentGameFormat(bestOfLegs: 4),
      ),
      SimulationEliminationStageSpec(
        name: 'KO',
        qualifiers: 1,
        lossLimit: 1,
        gameFormat: TournamentGameFormat(bestOfLegs: 5),
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Doppel-KO mit zwei Teilnehmern',
    playerCount: 2,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Finalrunde',
        qualifiers: 1,
        lossLimit: 2,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: '301-Gruppen und 501-Finale mit Sets',
    playerCount: 8,
    stages: [
      SimulationGroupStageSpec(
        name: 'Gruppen',
        qualifiers: 4,
        groupSizes: [4, 4],
        fixedPerGroup: 2,
        gameFormat: TournamentGameFormat(x01Score: 301, bestOfLegs: 3),
      ),
      SimulationEliminationStageSpec(
        name: 'Finale',
        qualifiers: 1,
        lossLimit: 1,
        gameFormat: TournamentGameFormat(
          x01Score: 501,
          bestOfSets: 3,
          bestOfLegs: 5,
        ),
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Triple-KO Grenzfall mit 2 Teilnehmern',
    playerCount: 2,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Triple-KO',
        qualifiers: 1,
        lossLimit: 3,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Triple-KO Grenzfall mit 3 Teilnehmern',
    playerCount: 3,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Triple-KO',
        qualifiers: 1,
        lossLimit: 3,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Triple-KO Grenzfall mit 5 Teilnehmern',
    playerCount: 5,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Triple-KO',
        qualifiers: 1,
        lossLimit: 3,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Triple-KO Grenzfall mit 16 Teilnehmern',
    playerCount: 16,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Triple-KO',
        qualifiers: 1,
        lossLimit: 3,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: '13 Teilnehmer in drei Gruppen mit sechs KO-Teilnehmer',
    playerCount: 13,
    stages: [
      SimulationGroupStageSpec(
        name: 'Gruppenphase',
        groupSizes: [5, 4, 4],
        qualifiers: 6,
        fixedPerGroup: 2,
      ),
      SimulationEliminationStageSpec(
        name: 'Finalrunde',
        qualifiers: 1,
        lossLimit: 1,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Planer mit einem Teilnehmer je Gruppe',
    playerCount: 8,
    stages: [
      SimulationGroupStageSpec(
        name: 'Gruppenphase',
        groupSizes: [4, 4],
        qualifiers: 2,
        fixedPerGroup: 1,
      ),
      SimulationEliminationStageSpec(
        name: 'Finale',
        qualifiers: 1,
        lossLimit: 1,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'nur KO mit 7 Teilnehmern',
    playerCount: 7,
    stages: [
      SimulationEliminationStageSpec(
        name: 'K.-o.-Runde',
        qualifiers: 1,
        lossLimit: 1,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'nur KO mit 3 von 5 Teilnehmern',
    playerCount: 5,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Mini-K.-o.-Weiterkommen',
        qualifiers: 3,
        lossLimit: 1,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'KO in KO mit 13 Teilnehmern',
    playerCount: 13,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Play-in-K.-o.',
        qualifiers: 8,
        lossLimit: 1,
      ),
      SimulationEliminationStageSpec(
        name: 'Final-K.-o.',
        qualifiers: 1,
        lossLimit: 1,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'nur Doppel-KO mit 10 Teilnehmern',
    playerCount: 10,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Doppel-K.-o.',
        qualifiers: 1,
        lossLimit: 2,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Doppel-KO mit 5 von 9 Teilnehmern',
    playerCount: 9,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Doppel-K.-o.-Weiterkommen',
        qualifiers: 5,
        lossLimit: 2,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Doppel-KO in KO mit 18 Teilnehmern',
    playerCount: 18,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Doppel-K.-o.-Vorrunde',
        qualifiers: 6,
        lossLimit: 2,
      ),
      SimulationEliminationStageSpec(
        name: 'K.-o.-Endrunde',
        qualifiers: 1,
        lossLimit: 1,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'nur Triple-KO mit 12 Teilnehmern',
    playerCount: 12,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Triple-K.-o.',
        qualifiers: 1,
        lossLimit: 3,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Triple-KO mit 4 von 11 Teilnehmern',
    playerCount: 11,
    stages: [
      SimulationEliminationStageSpec(
        name: 'Triple-K.-o.-Weiterkommen',
        qualifiers: 4,
        lossLimit: 3,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Liga-Gruppen in KO',
    playerCount: 24,
    stages: [
      SimulationGroupStageSpec(
        name: 'Gruppenphase',
        groupSizes: [4, 4, 4, 4, 4, 4],
        qualifiers: 16,
        fixedPerGroup: 2,
        extraRank: 3,
        extraCount: 4,
        extraGroups: [1, 2, 3, 4, 5, 6],
        roundRobinRepeats: [1, 1, 2, 1, 1, 2],
      ),
      SimulationEliminationStageSpec(
        name: 'Finalrunde',
        qualifiers: 1,
        lossLimit: 1,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'ungleiche Liga-Gruppen mit manueller Verteilung',
    playerCount: 17,
    stages: [
      SimulationGroupStageSpec(
        name: 'Gruppenphase',
        groupSizes: [5, 4, 4, 4],
        qualifiers: 9,
        fixedPerGroup: 0,
        fixedByGroup: [3, 2, 2, 1],
        extraRank: 2,
        extraCount: 1,
        extraGroups: [4],
        roundRobinRepeats: [2, 1, 1, 2],
      ),
      SimulationEliminationStageSpec(
        name: 'Doppel-K.-o.-Zwischenrunde',
        qualifiers: 4,
        lossLimit: 2,
      ),
      SimulationEliminationStageSpec(
        name: 'Final-K.-o.',
        qualifiers: 1,
        lossLimit: 1,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'gemischte Gruppen in Doppel-KO',
    playerCount: 27,
    stages: [
      SimulationGroupStageSpec(
        name: 'Gemischte Gruppenphase',
        groupSizes: [4, 4, 4, 4, 4, 4, 3],
        playTypes: [
          'round_robin',
          'mini_knockout',
          'double_knockout',
          'triple_knockout',
          'round_robin',
          'mini_knockout',
          'round_robin',
        ],
        qualifiers: 14,
        fixedPerGroup: 1,
        extraRank: 2,
        extraCount: 7,
        extraGroups: [1, 2, 3, 4, 5, 6, 7],
      ),
      SimulationEliminationStageSpec(
        name: 'Doppel-K.-o.-Finalrunde',
        qualifiers: 1,
        lossLimit: 2,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'kleine gemischte Gruppen mit knapper Weiterkommen',
    playerCount: 14,
    stages: [
      SimulationGroupStageSpec(
        name: 'Gemischte Kurzphase',
        groupSizes: [3, 3, 4, 4],
        playTypes: [
          'mini_knockout',
          'round_robin',
          'double_knockout',
          'triple_knockout',
        ],
        qualifiers: 7,
        fixedByGroup: [1, 1, 2, 2],
        extraRank: 2,
        extraCount: 1,
        extraGroups: [1, 2],
      ),
      SimulationEliminationStageSpec(
        name: 'K.-o.-Finalrunde',
        qualifiers: 1,
        lossLimit: 1,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'Gruppenphase in Gruppenphase in Triple-KO',
    playerCount: 32,
    stages: [
      SimulationGroupStageSpec(
        name: 'Vorrunde',
        groupSizes: [4, 4, 4, 4, 4, 4, 4, 4],
        qualifiers: 24,
        fixedPerGroup: 3,
      ),
      SimulationGroupStageSpec(
        name: 'Zwischenrunde',
        groupSizes: [6, 6, 6, 6],
        playTypes: [
          'round_robin',
          'mini_knockout',
          'double_knockout',
          'triple_knockout',
        ],
        qualifiers: 12,
        fixedPerGroup: 2,
        extraRank: 3,
        extraCount: 4,
        extraGroups: [1, 2, 3, 4],
      ),
      SimulationEliminationStageSpec(
        name: 'Triple-K.-o.-Finalrunde',
        qualifiers: 1,
        lossLimit: 3,
      ),
    ],
  ),
  TournamentSimulationScenario(
    name: 'drei Phasen mit wechselnden Modi und ungeraden Feldern',
    playerCount: 21,
    stages: [
      SimulationGroupStageSpec(
        name: 'Vorrunde',
        groupSizes: [4, 4, 4, 3, 3, 3],
        playTypes: [
          'round_robin',
          'mini_knockout',
          'round_robin',
          'double_knockout',
          'mini_knockout',
          'triple_knockout',
        ],
        qualifiers: 13,
        fixedPerGroup: 2,
        extraRank: 3,
        extraCount: 1,
        extraGroups: [1, 2, 3],
      ),
      SimulationEliminationStageSpec(
        name: 'Triple-K.-o.-Zwischenrunde',
        qualifiers: 5,
        lossLimit: 3,
      ),
      SimulationGroupStageSpec(
        name: 'Finalgruppe',
        groupSizes: [5],
        qualifiers: 2,
        fixedPerGroup: 2,
        roundRobinRepeats: [2],
      ),
      SimulationEliminationStageSpec(
        name: 'Finale',
        qualifiers: 1,
        lossLimit: 1,
      ),
    ],
  ),
];
