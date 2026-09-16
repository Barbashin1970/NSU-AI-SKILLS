#!/usr/bin/env bash
# Сторож пакета: проверяет, что текст навыков не разошёлся с диском.
# Запуск из корня репозитория:  ./check.sh
#
# Проверка 1. Каждая справка, упомянутая в тексте, существует.
# Проверка 2. Каждое число в таблицах-описях верно:
#             строка вида  | `имя` | … | N | …
#             имя-файл     → N обязано равняться числу строк файла;
#             имя-каталог/ → N обязано равняться числу файлов в каталоге.
#             Имена, которые не разрешаются в существующий путь, пропускаются:
#             таблица может перечислять не файлы.
#
# Предмет проверки — только СВОЙ текст пакета: SKILL.md и README.md навыков.
# Сами образцы не проверяются: это чужие сданные документы, их описи говорят
# о своём изделии и своей дате, а не об этом диске.

set -uo pipefail
cd "$(dirname "$0")" || exit 1

oshibok=0
skazat() { printf '%s\n' "$1"; oshibok=$((oshibok + 1)); }

echo "1. Ссылки на справки"
while read -r p; do
  [ -f "skills/$p" ] || skazat "   нет файла: skills/$p"
done < <(grep -rhoE '`[a-z0-9-]+/references/[a-z0-9-]+\.md`' skills | tr -d '`' | sort -u)

echo "2. Числа в таблицах-описях"
while read -r md; do
  katalog=$(dirname "$md")
  while IFS=$'\t' read -r imya zayavleno; do
    put="$katalog/$imya"
    if [ -f "$put" ]; then
      fakt=$(wc -l < "$put" | tr -d ' ')
      edinica="строк"
    elif [ -d "$put" ]; then
      fakt=$(find "$put" -type f | wc -l | tr -d ' ')
      edinica="файлов"
    else
      case "$imya" in
        *.md | */) skazat "   нет файла: $put (объявлен в $md)" ;;
      esac
      continue
    fi
    [ "$fakt" = "$zayavleno" ] || skazat \
      "   $put: в $md объявлено $zayavleno, на диске $fakt ($edinica)"
  done < <(sed -nE 's/^\| *`([^`]+)` *\|[^|]*\| *([0-9]+) *\|.*$/\1\t\2/p' "$md")
done < <(find skills \( -name SKILL.md -o -name README.md \) -not -path '*/komplekt-*')

if [ "$oshibok" -eq 0 ]; then
  echo "Расхождений нет."
else
  echo "Расхождений: $oshibok. Перемерить и поправить текст."
fi
exit $((oshibok > 0))
