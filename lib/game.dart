import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.currentUserId});
  final String currentUserId;

  @override
  State<GamePage> createState() => _GamePageState();
}

enum GameDifficulty { easy, medium, hard }

class _GamePageState extends State<GamePage> with SingleTickerProviderStateMixin {
  final _rand = Random();

  // 🔊 DŹWIĘK
  late final AudioPlayer _sfxPlayer;

  // ── Ustawienia ────────────────────────────────────────────────────────────────
  GameDifficulty _difficulty = GameDifficulty.easy;

  // Stała różnica koloru – cały czas taka sama (wyraźna).
  static const double _colorDelta = 0.20; // możesz podbić/obniżyć 0.14–0.24

  // ── Stan gry ─────────────────────────────────────────────────────────────────
  bool _running = false;
  int _score = 0;
  int _tilesTotal = 4; // 4/6/8/10/12
  int _oddIndex = 0;

  DateTime? _gameStart; // start całej gry (stoper)

  // Płynny pasek czasu rundy
  late final AnimationController _progress; // 1.0 -> 0.0 (reverse)

  // Kolory (z wartościami startowymi, żeby nie było LateInit błędów)
  Color _baseColor = const Color(0xFF7DEFD7);
  Color _oddColor  = const Color(0xFF5AE6C6);

  // ── Helpers ──────────────────────────────────────────────────────────────────
  int get _roundSeconds {
    switch (_difficulty) {
      case GameDifficulty.easy:   return 10;
      case GameDifficulty.medium: return 5;
      case GameDifficulty.hard:   return 2;
    }
  }

  // zawsze 2 rzędy, kolumny wynikają z liczby kafelków
  int get _rows => 2;
  int get _cols => (_tilesTotal / 2).ceil();

  @override
  void initState() {
    super.initState();

    _sfxPlayer = AudioPlayer()
      ..setReleaseMode(ReleaseMode.stop)
      ..setPlayerMode(PlayerMode.lowLatency); // ważne dla SFX


    _progress = AnimationController(
      vsync: this,
      duration: Duration(seconds: _roundSeconds),
      value: 1.0, // pełny pasek
    )..addStatusListener((status) {
      // Kiedy dojdzie do 0.0 (AnimationStatus.dismissed) – koniec rundy
      if (status == AnimationStatus.dismissed && _running) {
        _endGame(showDialogBox: true);
      }
    });

    _prepareRoundColors(); // gotowe kolory od pierwszego builda
  }

  @override
  void dispose() {
    _progress.dispose();
    _sfxPlayer.dispose();
    super.dispose();
  }

  // ── Runda/kolory ─────────────────────────────────────────────────────────────
  void _prepareRoundColors() {
    _oddIndex = _rand.nextInt(_tilesTotal);

    // Jedno HUE, umiarkowana saturacja i stała różnica jasności
    final hue = _rand.nextDouble() * 360.0;
    final sat = 0.65 + _rand.nextDouble() * 0.25; // 0.65..0.90
    const light = 0.52;                            // blisko środka
    final base = HSLColor.fromAHSL(1, hue, sat, light);

    final sign = _rand.nextBool() ? 1.0 : -1.0;
    final oddL = (light + sign * _colorDelta).clamp(0.0, 1.0);

    setState(() {
      _baseColor = base.toColor();
      _oddColor  = HSLColor.fromAHSL(1, hue, sat, oddL).toColor();
    });
  }

  void _updateTilesByScore() {
    final s = _score;
    int newTotal;
    if (s <= 80) {
      newTotal = 4;
    } else if (s <= 200) {
      newTotal = 6;
    } else if (s <= 400) {
      newTotal = 8;
    } else if (s <= 600) {
      newTotal = 10;
    } else {
      const pool = [4, 6, 8, 12];
      newTotal = pool[_rand.nextInt(pool.length)];
    }
    if (newTotal != _tilesTotal) {
      _tilesTotal = newTotal;
    }
  }

  void _restartRoundTimer() {
    _progress.stop();
    _progress.duration = Duration(seconds: _roundSeconds);
    _progress.value = 1.0;          // pełny pasek
    _progress.reverse(from: 1.0);   // płynnie do 0.0
  }

  // ── Start/Stop ───────────────────────────────────────────────────────────────
  void _startGame() {
    setState(() {
      _running = true;
      _score = 0;
      _tilesTotal = 4;
      _gameStart = DateTime.now();
    });
    _prepareRoundColors();
    _restartRoundTimer();
  }

  void _stopGame() {
    if (!_running) return;
    _endGame(showDialogBox: false);
  }

  void _endGame({required bool showDialogBox}) async {
    _progress.stop();

    final totalSeconds = _gameStart == null
        ? 0
        : DateTime.now().difference(_gameStart!).inSeconds;

    // Zapis wyniku
    try {
      await FirebaseFirestore.instance.collection('game_scores').add({
        'userId': widget.currentUserId,
        'difficulty': _difficulty.name, // "easy"|"medium"|"hard"
        'score': _score,
        'duration': totalSeconds,       // czas całej gry w sekundach
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // best-effort
    }

    setState(() {
      _running = false;
    });

    if (!mounted || !showDialogBox) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Koniec gry'),
        content: Text('Wynik: $_score pkt\nCzas: ${totalSeconds}s'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  // ── Audio helpers (MUSZĄ być w klasie, nie w initState) ─────────────────────
  Future<void> _preloadSfx() async {
    await _sfxPlayer.setSourceAsset('sfx/click.mp3');
  }

  Future<void> _playClick() async {
    try {
      // odtwarzaj asset przy każdym kliknięciu
      await _sfxPlayer.play(AssetSource('sfx/click.mp3'), volume: 1.0);
    } catch (e) {
      // opcjonalnie: debugPrint('SFX error: $e');
    }
  }

  // ── Interakcja ───────────────────────────────────────────────────────────────
  void _onTapTile(int index) {
    _playClick(); // 🔊 nasz dźwięk
    HapticFeedback.selectionClick();

    if (!_running) return;

    if (index == _oddIndex) {
      setState(() {
        _score += 2;
        _updateTilesByScore();
      });
      _prepareRoundColors();
      _restartRoundTimer();
    } else {
      _endGame(showDialogBox: true);
    }
  }

  // ── Tablica wyników (3 zakładki) ─────────────────────────────────────────────
  void _openLeaderboard() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const GameLeaderboardPage(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Nagłówek
        Padding(
          padding: const EdgeInsets.only(top: 12, left: 16, right: 16, bottom: 0),
          child: Text(
            'Nudzisz się? Zagrajmy w grę!',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 16, right: 16, bottom: 4),
          child: Text(
            'Zaznacz kafelek o innym kolorze. Za każde trafienie: +2 pkt.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),

        // Sterowanie
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              DropdownButton<GameDifficulty>(
                value: _difficulty,
                onChanged: _running ? null : (v) {
                  if (v == null) return;
                  setState(() => _difficulty = v);
                },
                items: const [
                  DropdownMenuItem(value: GameDifficulty.easy,   child: Text('Łatwy (10s)')),
                  DropdownMenuItem(value: GameDifficulty.medium, child: Text('Średni (5s)')),
                  DropdownMenuItem(value: GameDifficulty.hard,   child: Text('Trudny (2s)')),
                ],
              ),
              const Spacer(),
              Text('Wynik: $_score', style: theme.textTheme.titleMedium),
              const SizedBox(width: 12),
              _running
                  ? FilledButton.tonal(onPressed: _stopGame, child: const Text('Stop'))
                  : FilledButton(onPressed: _startGame, child: const Text('Start')),
            ],
          ),
        ),

        // Pasek czasu (płynny) + stoper (od początku gry)
        AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            final progress = _running ? _progress.value : 0.0;               // 1.0..0.0
            final timeLeft = _running ? (_roundSeconds * progress).ceil() : 0;
            final elapsed = _running && _gameStart != null
                ? DateTime.now().difference(_gameStart!).inSeconds
                : 0;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: progress, // płynnie maleje dzięki AnimationController
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(_running ? '${timeLeft}s' : '0s'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('Czas gry: $elapsed s'),
                ),
              ],
            );
          },
        ),

        // Plansza – bez scrolla, zawsze mieści się w dostępnej wysokości
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 10.0;
              const pad = 16.0;

              final cols = _cols;
              final rows = _rows;

              final availW = constraints.maxWidth - pad * 2;
              final availH = constraints.maxHeight - pad * 2;

              final tileSideByWidth  = (availW - (cols - 1) * spacing) / cols;
              final tileSideByHeight = (availH - (rows - 1) * spacing) / rows;
              final tileSide = min(tileSideByWidth, tileSideByHeight);

              final gridW = cols * tileSide + (cols - 1) * spacing;
              final gridH = rows * tileSide + (rows - 1) * spacing;

              return Center(
                child: SizedBox(
                  width: gridW,
                  height: gridH,
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: spacing,
                      childAspectRatio: 1,
                    ),
                    itemCount: _tilesTotal,
                    itemBuilder: (_, i) {
                      final color = (i == _oddIndex) ? _oddColor : _baseColor;
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _onTapTile(i),
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),

        // Tablica wyników (pełny ekran)
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.leaderboard_outlined),
            label: const Text('Tablica wyników'),
            onPressed: _openLeaderboard,
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────────
// PEŁNOEKRANOWA TABLICA WYNIKÓW Z 3 ZAKŁADKAMI
// ───────────────────────────────────────────────────────────────────────────────

class GameLeaderboardPage extends StatelessWidget {
  const GameLeaderboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tablica wyników'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Łatwy'),
              Tab(text: 'Średni'),
              Tab(text: 'Trudny'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _LeaderboardList(difficulty: 'easy'),
            _LeaderboardList(difficulty: 'medium'),
            _LeaderboardList(difficulty: 'hard'),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardList extends StatelessWidget {
  const _LeaderboardList({required this.difficulty});
  final String difficulty;

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('game_scores')
        .where('difficulty', isEqualTo: difficulty)
        .orderBy('score', descending: true)
        .orderBy('duration') // rosnąco – lepszy czas wyżej przy remisie
        .limit(50)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Błąd wczytywania wyników:\n${snap.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('Brak wyników.'));
        }

        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final rank = i + 1;
            final userId  = (d['userId'] as String?) ?? '???';
            final score   = (d['score'] as num?)?.toInt() ?? 0;
            final seconds = (d['duration'] as num?)?.toInt() ?? 0;

            return ListTile(
              leading: CircleAvatar(child: Text('$rank')),
              title: _AnonUserName(userId: userId),
              subtitle: Text('Czas: ${seconds}s'),
              trailing: Text(
                '$score pkt',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            );
          },
        );
      },
    );
  }
}

/// Wyświetla anonimową nazwę: pierwsze 3 litery imienia i nazwiska + „...”
/// w razie braku – „Uczestnik”.
class _AnonUserName extends StatelessWidget {
  const _AnonUserName({required this.userId});
  final String userId;

  String _mask3(String s) {
    final t = (s).trim();
    if (t.isEmpty) return '...';
    final n = t.length >= 3 ? 3 : t.length;
    return '${t.substring(0, n)}...';
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('users').doc(userId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        String first = '', last = '';

        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data()!;
          first = (d['firstName'] as String?)?.trim() ?? '';
          last  = (d['lastName']  as String?)?.trim() ?? '';

          if (first.isEmpty && last.isEmpty) {
            final dn = (d['displayName'] as String?)?.trim() ?? '';
            if (dn.isNotEmpty) {
              final parts = dn.split(RegExp(r'\s+'));
              first = parts.isNotEmpty ? parts.first : '';
              last  = parts.length > 1 ? parts.sublist(1).join(' ') : '';
            } else {
              final em = (d['email'] as String?)?.trim() ?? '';
              if (em.isNotEmpty) {
                first = em.split('@').first; // np. "damian.wrzeszcz"
                last  = '';
              }
            }
          }
        }

        final text = (first.isEmpty && last.isEmpty)
            ? 'Uczestnik'
            : '${_mask3(first)} ${_mask3(last)}'.trim();

        return Text(text, overflow: TextOverflow.ellipsis);
      },
    );
  }
}
