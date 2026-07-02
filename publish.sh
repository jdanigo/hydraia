#!/usr/bin/env bash
# Publica Hydraia en tu cuenta de GitHub. Ejecútalo TÚ, localmente,
# con `gh` ya autenticado (gh auth login).
#
#   bash publish.sh                 -> repo privado llamado "hydraia"
#   bash publish.sh mi-nombre pub   -> repo público con otro nombre
set -euo pipefail

REPO_NAME="${1:-hydraia}"
VISIBILITY="${2:-private}"   # private | public

# git identity local al repo (ajústalo si quieres)
GIT_NAME="${GIT_AUTHOR_NAME:-$(git config user.name || echo Daniel)}"
GIT_EMAIL="${GIT_AUTHOR_EMAIL:-$(git config user.email || echo you@example.com)}"

cd "$(dirname "$0")"

if [ ! -d .git ]; then
  git init -q
fi
git config user.name  "$GIT_NAME"
git config user.email "$GIT_EMAIL"

cat > .gitignore << 'EOF'
node_modules/
*.log
.DS_Store
EOF

git add -A
# Commit limpio: describe el cambio, sin ninguna línea de coautoría/atribución.
git commit -q -m "Initial commit: Hydraia agentic development harness

Full feature pipeline (analyze, plan with self-review, sub-agent
execution, double code review, security gates) packaged as a
Claude Code plugin." || echo "Nada que commitear."

echo "Creando repo $REPO_NAME ($VISIBILITY) y haciendo push..."
gh repo create "$REPO_NAME" --"$VISIBILITY" --source=. --remote=origin --push

echo ""
echo "Listo. Instálalo con:"
echo "  claude plugin marketplace add $(gh repo view "$REPO_NAME" --json url -q .url)"
echo "  claude plugin install hydraia"
