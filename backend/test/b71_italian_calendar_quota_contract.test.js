'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

function read(file) {
  return fs.readFileSync(path.join(__dirname, '../../', file), 'utf8');
}
const app = read('lib/app.dart');
const period = read('lib/screens/create_ai_coupon_screen.dart');
const policy = read('lib/services/goalvdline_quote_policy.dart');
const odds = read('lib/services/odds_service.dart');
const guard = read('lib/services/goalvdline_odds_scan_guard.dart');
const pub = read('pubspec.yaml');

test('B71: date picker receives Italian Material, Widgets and Cupertino localization', () => {
  assert.match(pub, /flutter_localizations:\s*\n\s+sdk: flutter/);
  assert.match(app, /locale: const Locale\('it', 'IT'\)/);
  assert.match(app, /GlobalMaterialLocalizations\.delegate/);
  assert.match(app, /GlobalWidgetsLocalizations\.delegate/);
  assert.match(app, /GlobalCupertinoLocalizations\.delegate/);
  assert.match(period, /showDateRangePicker\([\s\S]*?locale: const Locale\('it', 'IT'\)/);
  assert.match(period, /cancelText: 'ANNULLA'/);
  assert.match(period, /chip\(_CouponPeriod\.weekend, 'FINE SETTIMANA'\)/);
});

test('B71: Italy is default, can still be disabled and remains no guarantee of .it market', () => {
  assert.match(policy, /static const bool italianOnlyByDefault = true/);
  assert.match(period, /_italyScheduleOnly = GoalVdLineQuotePolicy\.italianOnlyByDefault/);
  assert.match(period, /italianScheduleOnly: _italyScheduleOnly/);
  assert.match(period, /italianBookmakerOnly: _italyScheduleOnly/);
});

test('B71: provider cooldown 503 is a quota pause, not a missing sportsbook market', () => {
  assert.match(odds, /FOOTBALL_PROVIDER_COOLDOWN/);
  assert.match(odds, /FOOTBALL_PROVIDER_RATE_LIMIT/);
  assert.match(odds, /providerCooldownActive/);
  assert.match(odds, /retry-after/);
  assert.match(odds, /_providerCooldownUntil/);
  assert.match(odds, /\.timeout\(const Duration\(seconds: 18\)\)/);
  assert.match(guard, /OddsLookupStatus\.providerCooldownActive/);
  assert.match(period, /evitate durante pausa API/);
  assert.match(period, /non siano prive di quote|non significa che le partite siano prive di quote/i);
});

test('B71: unquoted preview does not prioritize broad OR union picks as 99% forecasts', () => {
  const start = period.indexOf('final preview = <_SportsPreview>[];');
  const end = period.indexOf('// Fase 4: quote', start);
  assert.ok(start > 0 && end > start);
  const preview = period.slice(start, end);
  assert.match(preview, /SmartBetMarketProbabilityService\.orMarkets/);
  assert.match(preview, /markets\.firstWhere\(/);
  assert.match(preview, /_sportsOnlyPreview/);
  assert.doesNotMatch(preview, /_results\.add\(/);
});
