import 'package:flutter/material.dart';

import '../services/goalvdline_owner_session_client.dart';
import 'goalvdline_owner_setup_screen.dart';
import '../widgets/goalvdline_central_learning_consent_card.dart';
import 'smartbet_learning_monitor_screen.dart';
import 'smartbet_learning_overview_screen.dart';

/// A public app may display an entry to the owner login. This widget does
/// not trust a compile-time flag or a saved client token. The server must
/// validate the owner's password + 30-second Authenticator code.
class GoalVdLineOwnerAccessScreen extends StatefulWidget {
  const GoalVdLineOwnerAccessScreen({super.key, this.client});

  /// Test-only or higher-level dependency injection.
  /// Production always creates a network client that verifies server sessions.
  final GoalVdLineOwnerSessionClient? client;

  @override
  State<GoalVdLineOwnerAccessScreen> createState() =>
      _GoalVdLineOwnerAccessScreenState();
}

class _GoalVdLineOwnerAccessScreenState extends State<GoalVdLineOwnerAccessScreen>
    with WidgetsBindingObserver {
  final _password = TextEditingController();
  final _totp = TextEditingController();
  late final GoalVdLineOwnerSessionClient _client;
  bool _checking = true;
  bool _working = false;
  bool _loggedIn = false;
  bool _showPassword = false;
  bool _emailRecovery = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? GoalVdLineOwnerSessionClient();
    WidgetsBinding.instance.addObserver(this);
    _checkSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _password.clear();
    _password.dispose();
    _totp.clear();
    _totp.dispose();
    _client.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _checkSession();
  }

  Future<void> _checkSession() async {
    if (_working) return;
    if (mounted) setState(() => _checking = true);
    final valid = await _client.hasValidSession();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _loggedIn = valid;
    });
  }

  Future<void> _login() async {
    if (_working || _checking) return;
    setState(() { _working = true; _message = null; });
    final outcome = _emailRecovery
        ? await _client.loginByEmailRecovery(
            password: _password.text, code: _totp.text.trim(),
          )
        : await _client.login(
            password: _password.text, code: _totp.text.trim(),
          );
    _password.clear();
    _totp.clear();
    if (!mounted) return;
    setState(() {
      _working = false;
      _loggedIn = outcome.success;
      _message = outcome.success ? null : outcome.message;
    });
  }

  Future<void> _requestRecovery() async {
    if (_working || _checking) return;
    setState(() { _working = true; _message = null; });
    final outcome = await _client.requestEmailRecovery(
      password: _password.text,
    );
    if (!mounted) return;
    setState(() {
      _working = false;
      _message = outcome.message;
    });
  }

  Future<void> _logout() async {
    if (_working) return;
    setState(() => _working = true);
    await _client.logout();
    if (!mounted) return;
    setState(() {
      _loggedIn = false;
      _working = false;
      _message = null;
    });
  }

  Future<void> _openProtected(Widget page) async {
    if (_working || _checking) return;
    setState(() => _checking = true);
    final verified = await _client.hasValidSession();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _loggedIn = verified;
    });
    if (!verified) {
      setState(() => _message =
        'Sessione scaduta: accedi nuovamente con Authenticator.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    if (mounted) await _checkSession();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF111827),
    appBar: AppBar(
      title: const Text('Area proprietario'),
      actions: [
        if (_loggedIn)
          IconButton(
            tooltip: 'Disconnetti',
            onPressed: _working ? null : _logout,
            icon: const Icon(Icons.logout),
          ),
      ],
    ),
    body: _checking
        ? const Center(child: CircularProgressIndicator())
        : _loggedIn ? _ownerConsole() : _loginForm(),
  );

  Widget _loginForm() => ListView(
    key: const Key('b59-owner-login'),
    padding: const EdgeInsets.all(20),
    children: [
      const Icon(Icons.admin_panel_settings_outlined,
          color: Colors.lightGreenAccent, size: 52),
      const SizedBox(height: 20),
      const Text(
        'Accesso riservato al proprietario',
        style: TextStyle(
            color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Text(
        _emailRecovery
          ? 'Recupero: inserisci password e codice di 8 cifre '
            'ricevuto sulla casella email verificata del proprietario.'
          : 'La password resta personale. Inserisci il codice di 6 cifre '
            'generato dal tuo Authenticator: cambia ogni 30 secondi.',
        style: const TextStyle(color: Colors.white70, height: 1.5),
      ),
      const SizedBox(height: 22),
      TextField(
        controller: _password,
        key: const Key('b59-owner-password'),
        enabled: !_working,
        autofillHints: const [AutofillHints.password],
        obscureText: !_showPassword,
        enableSuggestions: false,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: 'Password proprietario',
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            tooltip: _showPassword ? 'Nascondi password' : 'Mostra password',
            onPressed: () => setState(() => _showPassword = !_showPassword),
            icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
          ),
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _totp,
        key: const Key('b59-owner-totp'),
        enabled: !_working,
        keyboardType: TextInputType.number,
        maxLength: _emailRecovery ? 8 : 6,
        autofillHints: const [AutofillHints.oneTimeCode],
        decoration: InputDecoration(
          labelText: _emailRecovery
              ? 'Codice ricevuto via email'
              : 'Codice Authenticator',
          prefixIcon: const Icon(Icons.pin_outlined),
          counterText: '',
        ),
        onSubmitted: (_) => _login(),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const Key('b59-owner-submit'),
        onPressed: _working ? null : _login,
        icon: const Icon(Icons.verified_user_outlined),
        label: Text(_emailRecovery
          ? 'Verifica codice email'
          : 'Verifica accesso'),
      ),
      const SizedBox(height: 9),
      TextButton.icon(
        key: const Key('b59-owner-recovery-toggle'),
        onPressed: _working ? null : () => setState(() {
          _emailRecovery = !_emailRecovery;
          _totp.clear();
          _message = null;
        }),
        icon: Icon(_emailRecovery
            ? Icons.app_shortcut : Icons.mark_email_read_outlined),
        label: Text(_emailRecovery
          ? 'Usa invece Authenticator'
          : 'Non ho Authenticator: recupero via email'),
      ),
      if (_emailRecovery)
        OutlinedButton.icon(
          key: const Key('b59-owner-recovery-request'),
          onPressed: _working ? null : _requestRecovery,
          icon: const Icon(Icons.mail_outline),
          label: const Text('Richiedi codice via email'),
        ),
      const SizedBox(height: 8),
      TextButton.icon(
        key: const Key('b61-first-activation-link'),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Prima attivazione: scegli la password'),
        onPressed: _working ? null : () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const GoalVdLineOwnerSetupScreen(),
          ),
        ),
      ),
      if (_working) const LinearProgressIndicator(),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            _message!,
            key: const Key('b59-owner-login-error'),
            style: const TextStyle(color: Colors.orangeAccent),
          ),
        ),
      const SizedBox(height: 20),
      const Text(
        'La casella proprietario e l’invio email devono essere '
        'configurati e verificati sul server. Il recupero resta '
        'disabilitato finché non lo saranno. '
        'Nessun codice o password è preimpostato nell’app.',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      ),
    ],
  );

  Widget _ownerConsole() => ListView(
    key: const Key('b59-owner-dashboard'),
    padding: const EdgeInsets.all(16),
    children: [
      const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Centro di controllo GoalVdLine',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
              SizedBox(height: 7),
              Text('Sessione proprietario verificata dal server. '
                'I dati tecnici restano separati dall’esperienza pubblica.'),
              SizedBox(height: 7),
              Text('Accesso temporaneo: nuova verifica dopo scadenza.',
                style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.query_stats_outlined),
              title: const Text('Statistiche, campionati e QuoteLab'),
              subtitle: const Text('Storico verificato e qualità dei modelli'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openProtected(
                const SmartBetLearningOverviewScreen(),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.psychology_alt_outlined),
              title: const Text('Learning Monitor e simulazioni'),
              subtitle: const Text('Brier, SHADOW, calibrazione e confronti'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openProtected(
                const SmartBetLearningMonitorScreen(),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const Text('Controlli locali e sincronizzazione autorizzata',
        style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const GoalVdLineCentralLearningConsentCard(),
      const SizedBox(height: 12),
      const Text(
        'Questa sessione non utilizza né rivela il token amministrativo '
        'di servizio. Le azioni protette sul server richiederanno '
        'autorizzazioni specifiche oltre al login.',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      ),
    ],
  );
}
