#!/usr/bin/env bash
set -euo pipefail

# Export ALL committed source files of the current B45 branch into Downloads.
# No local untracked files, caches, build output, .git history or phone data.
if ! command -v git >/dev/null || ! command -v unzip >/dev/null; then
  echo "ERRORE: servono git e unzip."
  exit 2
fi
root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERRORE: esegui lo script nella cartella del progetto Git."
  exit 2
}
cd "$root"
branch="$(git branch --show-current)"
if [[ "$branch" != "feature/b45-p20-4-multiday" ]]; then
  echo "ERRORE: branch attuale '$branch'; atteso feature/b45-p20-4-multiday."
  echo "Non cambio branch automaticamente per non toccare il lavoro locale."
  exit 2
fi
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "ATTENZIONE: ci sono modifiche non committate."
  echo "Lo ZIP contiene solo i file del commit HEAD, NON tali modifiche."
fi

# Guard against accidentally exporting committed runtime secrets if added later.
if git ls-files | grep -Ei '(^|/)(\.env($|\.)|google-service-info\.plist$|.*\.(p8|p12|pfx|jks|keystore|pem|key)$|service.?account[^/]*\.json$)' >/dev/null; then
  echo "ERRORE: trovato possibile file di credenziali tracciato."
  echo "Archivio annullato per evitare di copiare segreti."
  exit 3
fi

downloads="$HOME/Downloads"
mkdir -p "$downloads"
sha="$(git rev-parse --short=12 HEAD)"
timestamp="$(date +%Y%m%d_%H%M%S)"
filename="GoalVdLine_Build45_Sorgenti_${sha}_${timestamp}.zip"
destination="$downloads/$filename"
prefix="GoalVdLine_Build45_${sha}/"

git archive --format=zip --prefix="$prefix" --output="$destination" HEAD
if ! unzip -tq "$destination" >/dev/null; then
  rm -f "$destination"
  echo "ERRORE: verifica dello ZIP non superata."
  exit 1
fi

echo "ZIP COMPLETO CREATO E VERIFICATO:"
echo "$destination"
echo
echo "Dimensioni: $(du -h "$destination" | awk '{print $1}')"
echo "Commit: $(git rev-parse HEAD)"
echo "Contenuto: sorgenti Flutter/iOS/Android, backend, test e documentazione."
echo "Non include: .git, cache, build, .ipa, file locali non tracciati, dati iPhone/Neon."
echo "Rapporto: docs/B45_SIMULAZIONE_E_LEARNING_STATO.md (dentro lo ZIP)"
