#!/usr/bin/env bash
# Установка семейства навыков gost-19 сразу для Claude Code (~/.claude/skills)
# и Codex (~/.agents/skills) на macOS и Linux — симлинками, чтобы `git pull`
# обновлял навыки без переустановки.
#
# Сценарий можно запускать повторно: навык, чьё имя в целевом каталоге уже
# занято, ПРОПУСКАЕТСЯ. Чужое не затирается никогда.
set -euo pipefail

REPO_SKILLS="$(cd "$(dirname "$0")/skills" && pwd)"
[ -d "$REPO_SKILLS" ] || { echo "рядом со сценарием нет каталога skills/" >&2; exit 1; }

for T in "$HOME/.claude/skills" "$HOME/.agents/skills"; do
  mkdir -p "$T"
  echo
  echo "Каталог: $T"
  for d in "$REPO_SKILLS"/*/; do
    name="$(basename "$d")"
    link="$T/$name"
    if [ -e "$link" ] || [ -L "$link" ]; then
      echo "  пропущен (уже есть): $name"
    else
      ln -s "${d%/}" "$link"
      echo "  связан: $name"
    fi
  done
done

echo
echo "Готово. Перезапустите Claude Code / Codex — навыки подхватятся при старте."
echo "Обновление потом: git pull"
