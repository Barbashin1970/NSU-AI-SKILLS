#!/usr/bin/env bash
# Пересборка готовых архивов навыков в каталоге zip/.
#
#   ./soberi-zip.sh
#
# Архивы лежат в репозитории и обновляются этим сценарием после правки навыков.
# Скачивающему с GitHub собирать ничего не нужно: он берёт нужный zip прямо
# со страницы репозитория и грузит в свою среду.
#
# Один навык — один архив, SKILL.md в корне архива. Описания навыков уже уложены
# в 1024 БАЙТА, поэтому подменять здесь нечего: что в репозитории, то и в архиве.
#
# В архивы НЕ кладётся:
#   .DS_Store и служебные двойники Finder (`._имя`, `__MACOSX`);
#   любой PDF — навык с PDF внутри не собирается вовсе: в исходных PDF этого
#   хозяйства лежат НЕобезличенные данные, и один такой файл в архиве дороже
#   всего остального вместе взятого.
#
# Почему через python3, а не командой zip: Apple-версия zip не умеет ключ
# -UN=UTF8 и пишет русские имена файлов без признака кодировки. На Windows такой
# архив распаковывается кракозябрами, а у образцов имя файла — часть обозначения
# документа по ЕСПД. python3 проставляет признак UTF-8 сам.

set -uo pipefail
cd "$(dirname "$0")" || exit 1

command -v python3 >/dev/null || { echo "нужен python3"; exit 1; }

python3 - "$@" <<'PY'
import os, re, shutil, sys, zipfile

PREDEL_FAJLOV = 100       # потолок числа файлов на архив у приёмной стороны
PREDEL_OPISANIYA = 1024   # потолок длины description, В БАЙТАХ
ZA_OTPRAVKU = 5           # сколько файлов Perplexity принимает за один раз
VYHOD = "zip"
MUSOR = {".DS_Store", "Thumbs.db", "desktop.ini", "__MACOSX"}

# Про байты. Perplexity меряет description байтами, а не знаками: в отказе виден
# Go-сервис, а там len(строки) — длина в байтах. Кириллица в UTF-8 весит два байта
# на букву, поэтому русское описание упирается в предел вдвое раньше — около
# 512 знаков. Замер 19.09.2026: из десяти навыков принят был ровно один —
# единственный с описанием короче 1024 байт, хотя по ЗНАКАМ проходили девять.
# Ключевые слова, которые из-за этого не помещаются в description, живут
# в поле when_to_use: Claude учитывает его при отборе навыка наравне с описанием
# (общий предел там 1536 ЗНАКОВ), а приёмная сторона его просто не читает.

zamechaniy = 0

def zamechanie(tekst):
    global zamechaniy
    print(tekst)
    zamechaniy += 1

def musor(imya):
    return imya in MUSOR or imya.startswith("._")

def polya_shapki(put):
    """description и when_to_use из YAML-шапки, без кавычек."""
    tekst = open(put, encoding="utf-8").read()
    shapka = re.match(r"^---\n(.*?)\n---\n", tekst, re.S)
    if shapka is None:
        return None, None
    def pole(imya):
        m = re.search(rf"^{imya}:\s*(.*)$", shapka.group(1), re.M)
        return m.group(1).strip().strip('"') if m else ""
    return pole("description"), pole("when_to_use")

shutil.rmtree(VYHOD, ignore_errors=True)
os.makedirs(VYHOD)

navyki = sorted(d for d in os.listdir("skills")
                if os.path.isfile(f"skills/{d}/SKILL.md"))

print(f'{"Навык":<20}{"Файлов":>8}{"Размер":>9}{"Описание":>10}{"+ключи":>8}')

for imya in navyki:
    katalog = f"skills/{imya}"

    fajly = []
    for koren, katalogi, imena in os.walk(katalog):
        katalogi[:] = sorted(k for k in katalogi if not musor(k))
        for f in sorted(imena):
            if not musor(f):
                fajly.append(os.path.join(koren, f))

    pdf = [f for f in fajly if f.lower().endswith(".pdf")]
    if pdf:
        zamechanie(f"   {imya}: внутри PDF ({len(pdf)} шт.) — проверьте, "
                   f"обезличены ли они; архив не собран")
        continue

    opisanie, klyuchi = polya_shapki(f"{katalog}/SKILL.md")
    if opisanie is None:
        zamechanie(f"   {imya}: в SKILL.md не читается YAML-шапка")
        continue

    bajt = len(opisanie.encode("utf-8"))
    if bajt > PREDEL_OPISANIYA:
        izlishek = bajt - PREDEL_OPISANIYA
        zamechanie(f"   {imya}: description весит {bajt} байт при пределе "
                   f"{PREDEL_OPISANIYA}: сократить на {izlishek} байт (по-русски "
                   f"это примерно {(izlishek + 1)//2} знаков), лишние ключевые "
                   f"слова перенести в when_to_use")
        continue

    arhiv = os.path.join(VYHOD, imya + ".zip")
    with zipfile.ZipFile(arhiv, "w", zipfile.ZIP_DEFLATED) as z:
        for f in fajly:
            z.write(f, os.path.relpath(f, katalog))

    vesit = os.path.getsize(arhiv)
    razmer = f"{vesit/1024:.0f}K" if vesit < 1024**2 else f"{vesit/1024**2:.1f}M"
    print(f"{imya:<20}{len(fajly):>8}{razmer:>9}{bajt:>10}{len(klyuchi.encode()):>8}")

    if len(fajly) > PREDEL_FAJLOV:
        zamechanie(f"   ^ файлов больше {PREDEL_FAJLOV}: навык надо делить")

    # Claude читает description и when_to_use вместе; предел там в ЗНАКАХ.
    if len(opisanie) + len(klyuchi) > 1536:
        zamechanie(f"   ^ description и when_to_use вместе {len(opisanie)+len(klyuchi)} "
                   f"знаков при пределе 1536: хвост обрежется при отборе навыка")

zahodov = (len(navyki) + ZA_OTPRAVKU - 1) // ZA_OTPRAVKU
print()
print(f"Готово. {VYHOD}/ — {len(navyki)} архивов. В Perplexity грузить "
      f"{zahodov} заходами по {ZA_OTPRAVKU}."
      if zamechaniy == 0 else f"Замечаний: {zamechaniy}.")
sys.exit(1 if zamechaniy else 0)
PY
