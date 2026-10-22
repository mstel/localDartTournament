import 'dart:convert';

import '../domain/tournament_models.dart';

/// Portable, versioned representations for publishing tournament data elsewhere.
class TournamentExport {
  static const schemaVersion = 1;

  static Map<String, dynamic> document(CreatedTournament tournament) => {
    'format': 'dart-tournament-export',
    'schemaVersion': schemaVersion,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'tournament': tournament.toJson(),
  };

  static String encode(CreatedTournament tournament) =>
      const JsonEncoder.withIndent('  ').convert(document(tournament));

  static String html(
    CreatedTournament tournament, {
    Map<String, Object?>? resultSummary,
    List<Map<String, Object?>> rankingChanges = const [],
  }) => _htmlTemplate
      .replaceFirst(
        '@@DATA@@',
        jsonEncode(document(tournament)).replaceAll('<', r'\u003c'),
      )
      .replaceFirst(
        '@@SUMMARY@@',
        jsonEncode({
          ...?resultSummary,
          'rankingChanges': rankingChanges,
        }).replaceAll('<', r'\u003c'),
      );

  static const _htmlTemplate = r'''<!doctype html>
<html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Turnierübersicht</title>
<style>:root{font:16px/1.5 system-ui,sans-serif;color-scheme:light dark}body{margin:0;background:#101820;color:#f5f7f8}main{max-width:1100px;margin:auto;padding:clamp(16px,4vw,40px)}h1{line-height:1.15}section{background:#1b2933;border-radius:14px;padding:16px;margin:18px 0;overflow:auto}.summary{background:linear-gradient(120deg,#142b3a,#175c59)}.meta,.players,.metrics,.podium{display:flex;flex-wrap:wrap;gap:10px}.metrics{justify-content:center}.metric,.pill{border:1px solid #456;padding:6px 10px;border-radius:10px}.podium article{flex:1 1 190px;background:#ffffff12;border-radius:10px;padding:12px;text-align:center}.muted{color:#b6c2c9}.toolbar{text-align:right}table{width:100%;border-collapse:collapse;min-width:480px}th,td{text-align:left;padding:10px;border-bottom:1px solid #456}th{color:#9ed9d2}.score{text-align:center;font-weight:700}button{min-height:48px;padding:8px 14px;font:inherit}@media print{body{background:#fff;color:#111}main{max-width:none;padding:0}section{background:#fff!important;color:#111;border:1px solid #999;break-inside:avoid}.summary{background:#e7f3ee!important}.toolbar{display:none}.muted{color:#444}table{min-width:0}th,td{border-color:#aaa}}</style>
<main><header><div class="toolbar"><button onclick="window.print()">Drucken / Als PDF speichern</button></div><p class="muted">Turnierübersicht</p><h1 id="name"></h1><div class="meta" id="meta"></div></header><section class="summary"><h2>Turnierübersicht</h2><div class="metrics" id="metrics"></div><p id="duration"></p></section><section><h2>Podium</h2><div class="podium" id="podium"></div></section><section id="ranking-section" hidden><h2>Ranglistenänderungen</h2><div id="ranking-changes"></div></section><section><h2>Bestleistungen</h2><div id="performances"></div></section><section><h2>Teilnehmer</h2><div class="players" id="players"></div></section><section><h2>Begegnungen und Ergebnisse</h2><div id="matches"></div></section><p class="muted">Exportiert aus der Turnierverwaltung.</p></main>
<script type="application/json" id="export">@@DATA@@</script><script type="application/json" id="summary-data">@@SUMMARY@@</script><script>
const root=JSON.parse(document.querySelector('#export').textContent),t=root.tournament,s=JSON.parse(document.querySelector('#summary-data').textContent);const el=id=>document.getElementById(id),text=(tag,value,cls)=>{const n=document.createElement(tag);n.textContent=value??'';if(cls)n.className=cls;return n},fmtMinutes=m=>`${Math.floor(m/60)}:${String(m%60).padStart(2,'0')}`,fmtSeconds=n=>fmtMinutes(Math.floor(n/60));
el('name').textContent=t.name||'Turnier';for(const v of [t.createdAt?new Date(t.createdAt).toLocaleDateString('de-DE'):null,t.finishedAt?'Abgeschlossen':null])if(v)el('meta').append(text('span',v,'pill'));
for(const [label,value] of [['Teilnehmer',s.participantCount],['Begegnungen',s.matchCount],['Gespielte Legs',s.legCount],['Legs / Match',s.averageLegsPerMatch?.toFixed(1)]])if(value!=null)el('metrics').append(text('span',`${label}: ${value}`,'metric'));
const duration=[];if(s.actualDurationSeconds!=null)duration.push(`Tatsächlich: ${fmtSeconds(s.actualDurationSeconds)}`);if(s.expectedMinimumMinutes!=null&&s.expectedMaximumMinutes!=null)duration.push(`Erwartet: ${fmtMinutes(s.expectedMinimumMinutes)}–${fmtMinutes(s.expectedMaximumMinutes)}`);else if(s.expectedMaximumMinutes!=null)duration.push(`Erwartet: ${fmtMinutes(s.expectedMaximumMinutes)}`);el('duration').textContent=duration.join(' · ')||'Dauer: nicht erfasst';
for(const [i,p] of (s.podium||[]).entries()){const card=document.createElement('article');card.append(text('strong',`${i+1}. Platz · ${p.name}`),text('p',`${p.wins} Siege · ${p.losses} Niederlagen`),text('p',`${p.legsFor}:${p.legsAgainst} Legs`));el('podium').append(card)}
if((s.rankingChanges||[]).length){el('ranking-section').hidden=false;for(const c of s.rankingChanges){const suffix=c.delta>0?`+${c.delta}`:`${c.delta}`;el('ranking-changes').append(text('p',`${c.rankingName} · ${c.playerName}: ${suffix} (${c.ratingBefore} → ${c.ratingAfter})${c.tierChange?` · ${c.tierBefore} → ${c.tierAfter}`:''}`))}}
const participants=t.importedArchive?.participants||[];if(participants.length){for(const p of [...participants].sort((a,b)=>(a.finalRank||9999)-(b.finalRank||9999)))el('players').append(text('span',`${p.finalRank?`${p.finalRank}. `:''}${p.name}`,'pill'))}else for(const p of t.players||[])el('players').append(text('span',p.name,'pill'));
const rows=[],performances=[];for(const m of t.importedArchive?.matches||[])rows.push([m.round?`Runde ${Math.abs(m.round)}`:'Challonge',participants.find(p=>String(p.id)===String(m.player1_id))?.name||'Freilos',m.scores_csv||m.state||'—',participants.find(p=>String(p.id)===String(m.player2_id))?.name||'']);
function walk(v,path=[]){if(!v||typeof v!=='object')return;if(Array.isArray(v)){v.forEach((x,i)=>walk(x,[...path,i]));return}if(v.homePlayer||v.awayPlayer){const score=v.homeLegs!=null?`${v.homeLegs}:${v.awayLegs}${v.homeSets!=null?` (${v.homeSets}:${v.awaySets} Sets)`:''}`:v.homeScore!=null?`${v.homeScore}:${v.awayScore}`:'—';rows.push([v.label||path.filter(x=>typeof x==='string').join(' · ')||'Begegnung',v.homePlayer?.name||'—',score,v.awayPlayer?.name||'—']);for(const performance of v.bestPerformances||[])performances.push(performance)}for(const[k,x]of Object.entries(v))if(k!=='homePlayer'&&k!=='awayPlayer')walk(x,[...path,k])}walk(t.runStages||[]);
for(const p of performances)el('performances').append(text('p',`${p.playerName} · ${{score170:'170+',score180:'180+',highFinish:'High Finish',shortLeg:'Shortleg'}[p.type]||p.type}${p.value!=null?` · ${p.value}`:''}`));if(!performances.length)el('performances').append(text('p','Keine Bestleistungen erfasst.'));
if(rows.length){const table=document.createElement('table'),head=document.createElement('tr');for(const v of ['Runde / Gruppe','Spieler 1','Ergebnis','Spieler 2'])head.append(text('th',v));table.append(head);for(const row of rows){const tr=document.createElement('tr');row.forEach((v,i)=>tr.append(text('td',v,i===2?'score':'')));table.append(tr)}el('matches').append(table)}else el('matches').append(text('p','Noch keine Begegnungen mit Ergebnissen.'));
</script></html>''';
}
