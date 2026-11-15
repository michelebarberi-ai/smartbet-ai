/// B57: UI edition for distribution. NOT an authorization credential.
///
/// Internal diagnostics can be compiled into a separately distributed owner
/// build by specifying --dart-define=GOALVDLINE_INTERNAL_DIAGNOSTICS=true.
///
/// The public build defaults to false. Never embed a server admin token into
/// either build. Remote administrative functions still require authenticated
/// server-side roles; compile-time UI flags are not a security boundary.
class GoalVdLineUiEdition {
  const GoalVdLineUiEdition._();

  static const bool internalDiagnostics = bool.fromEnvironment(
    'GOALVDLINE_INTERNAL_DIAGNOSTICS',
    defaultValue: false,
  );
}
