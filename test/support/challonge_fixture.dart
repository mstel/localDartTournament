Map<String, dynamic> challongeFixture({int id = 7}) => {
  'id': id,
  'name': 'Importtest',
  'state': 'complete',
  'tournament_type': 'round robin',
  'teams': false,
  'participants_count': 3,
  'created_at': '2020-01-01T12:00:00Z',
  'completed_at': '2020-01-01T18:00:00Z',
  'participants': [
    for (var i = 1; i <= 3; i++)
      {
        'participant': {
          'id': i,
          'name': 'Teilnehmer $i',
          'final_rank': i == 1 ? 1 : 2,
        },
      },
  ],
  'matches': [
    for (var i = 1; i <= 3; i++)
      {
        'match': {
          'id': i,
          'state': 'complete',
          'round': i,
          'player1_id': i,
          'player2_id': i % 3 + 1,
          'winner_id': i,
          'scores_csv': '3-1',
        },
      },
  ],
};
