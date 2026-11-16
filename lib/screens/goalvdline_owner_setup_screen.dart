import 'package:flutter/material.dart';

import '../services/goalvdline_owner_setup_client.dart';

enum _OwnerSetupStage { unavailable, requestEmail, verifyEmail, pairTotp, done }

/// B61: no account can be created without a code delivered to the fixed
/// owner mailbox configured on the server. Never use a client-controlled
/// email address or turn a local UI flag into owner authorization.
class GoalVdLineOwnerSetupScreen extends StatefulWidget {
  const GoalVdLineOwnerSetupScreen({super.key, this.client});

  final GoalVdLineOwnerSetupClient? client;

  @override
  State<GoalVdLineOwnerSetupScreen> createState() =>
      _GoalVdLineOwnerSetupScreenState();
}

class _GoalVdLineOwnerSetupScreenState
    extends State<GoalVdLineOwnerSetupScreen> {
  final _mailCode = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirmation = TextEditingController();
  final _authCode = TextEditingController();
  late final GoalVdLineOwnerSetupClient _client;

  _OwnerSetupStage _stage = _OwnerSetupStage.unavailable;
  bool _working = true;
  bool _showPassword = false;
  String _message = 'Controllo della prima attivazione...';
  String? _ticket;
  String? _manualTotpKey;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? GoalVdLineOwnerSetupClient();
    _check();
  }

  @override
  void dispose() {
    _mailCode.clear();
    _password.clear();
    _passwordConfirmation.clear();
    _authCode.clear();
    _mailCode.dispose();
    _password.dispose();
    _passwordConfirmation.dispose();
    _authCode.dispose();
    _ticket = null;
    _manualTotpKey = null;
    _client.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final result = await _client.status();
    if (!mounted) return;
    setState(() {
      _working = false;
      _message = result.message;
      _stage = result.activated
          ? _OwnerSetupStage.done
          : result.ready
              ? _OwnerSetupStage.requestEmail
              : _OwnerSetupStage.unavailable;
    });
  }

  void _retryServerCheck() {
    if (_working) return;
    setState(() {
      _working = true;
      _message = 'Nuova verifica del server in corso...';
    });
    _check();
  }

  Future<void> _request() async {
    if (_working) return;
    setState(() => _working = true);
    final r = await _client.requestCode();
    if (!mounted) return;
    setState(() {
      _working = false;
      _message = r.message;
      if (r.success) _stage = _OwnerSetupStage.verifyEmail;
    });
  }

  Future<void> _verifyEmail() async {
    if (_working) return;
    setState(() => _working = true);
    final r = await _client.verifyEmail(_mailCode.text.trim());
    _mailCode.clear();
    if (!mounted) return;
    if (!r.success || r.ticket == null) {
      setState(() {
        _working = false;
        _message = r.message;
      });
      return;
    }
    _ticket = r.ticket;
    final pair = await _client.startAuthenticator(_ticket!);
    if (!mounted) return;
    setState(() {
      _working = false;
      _message = pair.message;
      if (pair.success && pair.totpManualKey != null) {
        _manualTotpKey = pair.totpManualKey;
        _stage = _OwnerSetupStage.pairTotp;
      }
    });
  }

  Future<void> _finish() async {
    if (_working || _ticket == null) return;
    if (_password.text != _passwordConfirmation.text) {
      setState(() => _message = 'Le due password non coincidono.');
      return;
    }
    setState(() => _working = true);
    final r = await _client.finish(
      ticket: _ticket!,
      password: _password.text,
      code: _authCode.text.trim(),
    );
    _password.clear();
    _passwordConfirmation.clear();
    _authCode.clear();
    if (!mounted) return;
    setState(() {
      _working = false;
      _message = r.message;
      if (r.activated) {
        _manualTotpKey = null;
        _ticket = null;
        _stage = _OwnerSetupStage.done;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      appBar: AppBar(title: const Text('Attiva area proprietario')),
      body: ListView(
        key: const Key('b61-owner-setup'),
        padding: const EdgeInsets.all(18),
        children: [
          const Icon(Icons.shield_outlined,
              color: Colors.lightGreenAccent, size: 45),
          const SizedBox(height: 15),
          const Text(
            'Prima attivazione protetta',
            style: TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '1. Verifica la tua email.  2. Abbina Authenticator.  '
            '3. Scegli una password personale. Nessun dato viene '
            'inviato senza un’azione esplicita.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 18),
          if (_working) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _message,
              key: const Key('b61-setup-status'),
              style: const TextStyle(color: Colors.lightGreenAccent),
            ),
          ),
          if (_stage == _OwnerSetupStage.unavailable) ...[
            const Text(
              'Il server deve avere prima una casella verificata, '
              'il database protetto e le chiavi segrete configurate. '
              'Non inserire password o codici finché questa '
              'attivazione non risulta disponibile.',
              key: Key('b61-setup-not-ready'),
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('b62-retry-owner-status'),
              onPressed: _working ? null : _retryServerCheck,
              icon: const Icon(Icons.refresh),
              label: const Text('Riprova verifica server'),
            ),
          ],
          if (_stage == _OwnerSetupStage.requestEmail)
            FilledButton.icon(
              key: const Key('b61-send-email-code'),
              onPressed: _working ? null : _request,
              icon: const Icon(Icons.mail_outline),
              label: const Text('Invia codice alla mia email'),
            ),
          if (_stage == _OwnerSetupStage.verifyEmail) ...[
            TextField(
              key: const Key('b61-email-code'),
              controller: _mailCode,
              enabled: !_working,
              keyboardType: TextInputType.number,
              maxLength: 8,
              autofillHints: const [AutofillHints.oneTimeCode],
              decoration: const InputDecoration(
                labelText: 'Codice email (8 cifre)', counterText: '',
              ),
            ),
            FilledButton.icon(
              key: const Key('b61-verify-email'),
              onPressed: _working ? null : _verifyEmail,
              icon: const Icon(Icons.mark_email_read_outlined),
              label: const Text('Verifica email'),
            ),
          ],
          if (_stage == _OwnerSetupStage.pairTotp) ...[
            const SizedBox(height: 8),
            const Text(
              'Apri l’app Authenticator e scegli '
              '“Aggiungi account” → “Inserisci chiave manualmente”. '
              'La chiave qui sotto è privata: non condividerla.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _manualTotpKey ?? '',
              key: const Key('b61-authenticator-manual-key'),
              style: const TextStyle(
                color: Colors.lightGreenAccent,
                fontSize: 17, fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              key: const Key('b61-new-password'),
              controller: _password,
              enabled: !_working,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Nuova password (almeno 16 caratteri)',
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(_showPassword
                      ? Icons.visibility_off : Icons.visibility),
                ),
              ),
            ),
            TextField(
              key: const Key('b61-confirm-password'),
              controller: _passwordConfirmation,
              enabled: !_working,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Conferma password',
              ),
            ),
            TextField(
              key: const Key('b61-first-totp'),
              controller: _authCode,
              enabled: !_working,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Codice Authenticator (6 cifre)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('b61-finish-activation'),
              onPressed: _working ? null : _finish,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Conferma e attiva'),
            ),
          ],
          if (_stage == _OwnerSetupStage.done)
            FilledButton(
              key: const Key('b61-back-to-login'),
              onPressed: () => Navigator.pop(context),
              child: const Text('Torna al login'),
            ),
          const SizedBox(height: 20),
          const Text(
            'L’email viene fissata sul server e non può essere cambiata '
            'dal telefono durante la registrazione. '
            'Le sessioni restano separate dalle API amministrative.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
