import 'package:flutter/material.dart';

import '../services/settings_store.dart';
import '../services/smartbet_ai_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsStore _store = SettingsStore.instance;

  @override
  void initState() {
    super.initState();

    _store.initialize();
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: const Text(
            'Ripristina impostazioni',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Vuoi ripristinare le impostazioni predefinite di SmartBet?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('ANNULLA'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('RIPRISTINA'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await _store.resetDefaults();
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _settingsCard({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Text(
          'Impostazioni',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: AnimatedBuilder(
        animation: _store,
        builder: (context, child) {
          if (!_store.initialized) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
            children: [
              _sectionTitle('Analisi AI'),

              _settingsCard(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Smart Score minimo',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Soglia minima per considerare un pronostico affidabile.',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Text(
                        '${_store.minimumSmartScore}',
                        style: const TextStyle(
                          color: Color(0xFF00C853),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  Slider(
                    value: _store.minimumSmartScore.toDouble(),
                    min: 50,
                    max: 90,
                    divisions: 8,
                    label: '${_store.minimumSmartScore}',
                    onChanged: (value) {
                      _store.setMinimumSmartScore(value.round());
                    },
                  ),

                  const Divider(color: Colors.white10),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Solo pronostici giocabili',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'Mostra soltanto i pronostici che superano anche Stake Engine e Value Bet.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: _store.onlyPlayablePredictions,
                    onChanged: _store.setOnlyPlayablePredictions,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              _sectionTitle('Schedina AI'),

              _settingsCard(
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Numero massimo di selezioni',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: List.generate(5, (index) {
                      final value = index + 2;

                      final selected = _store.couponSelections == value;

                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: OutlinedButton(
                            onPressed: () {
                              _store.setCouponSelections(value);
                            },
                            style: OutlinedButton.styleFrom(
                              backgroundColor: selected
                                  ? const Color(0xFF00C853)
                                  : null,
                              foregroundColor: selected
                                  ? Colors.white
                                  : Colors.white70,
                              side: BorderSide(
                                color: selected
                                    ? const Color(0xFF00C853)
                                    : Colors.white24,
                              ),
                            ),
                            child: Text('$value'),
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'SmartBet potrà usare fino a '
                    '${_store.couponSelections} selezioni nella schedina.',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              _sectionTitle('Pulizia dati'),

              _settingsCard(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Rimuovi automaticamente dati scaduti',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'Elimina automaticamente pronostici e quote relativi a partite già iniziate.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    value: _store.autoRemoveExpired,
                    onChanged: _store.setAutoRemoveExpired,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              _sectionTitle('Sistema'),

              _settingsCard(
                children: [
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.sports_soccer,
                      color: Color(0xFF00C853),
                    ),
                    title: Text(
                      'SmartBet AI',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      'Versione 1.0.0',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),

                  const Divider(color: Colors.white10),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.dns_outlined,
                      color: Colors.orange,
                    ),
                    title: const Text(
                      'Backend AI',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      SmartBetAiService.backendUrl,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('RIPRISTINA IMPOSTAZIONI'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
