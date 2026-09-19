#!/usr/bin/env bash
# Сборка архивов для загрузки навыков в чужие среды (Perplexity и подобные).
# Запуск из корня репозитория:  ./soberi-zip.sh
#
# Один навык — один архив. SKILL.md лежит в корне архива, как того требует
# приёмная сторона; пути вида references/имя.md внутри текста от этого не ломаются.
#
# В архив НЕ кладётся:
#   _ishodniki/  — исходные PDF с НЕобезличенными данными;
#   .git/        — история репозитория, сотни файлов;
#   .DS_Store и служебные двойники Finder (`._имя`, `__MACOSX`).
# Первое — причина, по которой архивы собираются этим сценарием, а не мышью:
# «Сжать» в Finder кладёт в архив всю папку целиком, вместе с исходниками.
#
# Почему сборка идёт через python3, а не командой zip: Apple-версия zip не умеет
# ключ -UN=UTF8 и пишет русские имена файлов без признака кодировки. На Windows
# такой архив распаковывается кракозябрами, а у образцов имя файла — часть
# обозначения документа по ЕСПД. python3 проставляет признак UTF-8 сам.

set -uo pipefail
cd "$(dirname "$0")" || exit 1

command -v python3 >/dev/null || { echo "нужен python3"; exit 1; }

python3 - "$@" <<'PY'
import os, shutil, sys, zipfile

PREDEL = 100            # потолок числа файлов на архив у приёмной стороны
VYHOD  = "dist"
MUSOR  = {".DS_Store", "Thumbs.db", "desktop.ini", "__MACOSX"}

def musor(imya):
    return imya in MUSOR or imya.startswith("._")

shutil.rmtree(VYHOD, ignore_errors=True)
os.makedirs(VYHOD)

zamechaniy = 0
print(f'{"Навык":<20}{"Файлов":>8}{"Размер":>10}  Архив')

for imya in sorted(os.listdir("skills")):
    katalog = os.path.join("skills", imya)
    if not os.path.isdir(katalog):
        continue

    if not os.path.isfile(os.path.join(katalog, "SKILL.md")):
        print(f"   {imya}: нет SKILL.md — пропущен")
        zamechaniy += 1
        continue

    fajly = []
    for koren, katalogi, imena in os.walk(katalog):
        katalogi[:] = [k for k in katalogi if not musor(k)]
        for f in sorted(imena):
            if not musor(f):
                fajly.append(os.path.join(koren, f))

    pdf = [f for f in fajly if f.lower().endswith(".pdf")]
    if pdf:
        print(f"   {imya}: внутри PDF ({len(pdf)} шт.) — проверьте, обезличены ли они; архив не собран")
        zamechaniy += 1
        continue

    arhiv = os.path.join(VYHOD, imya + ".zip")
    with zipfile.ZipFile(arhiv, "w", zipfile.ZIP_DEFLATED) as z:
        for f in fajly:
            # Внутри архива путь отсчитывается от папки навыка: SKILL.md — в корне.
            z.write(f, os.path.relpath(f, katalog))

    vesit = os.path.getsize(arhiv)
    razmer = f"{vesit/1024:.0f}K" if vesit < 1024**2 else f"{vesit/1024**2:.1f}M"
    print(f"{imya:<20}{len(fajly):>8}{razmer:>10}  {arhiv}")

    if len(fajly) > PREDEL:
        print(f"   ^ файлов больше {PREDEL}: этот архив не примут, навык надо делить")
        zamechaniy += 1

print()
print("Готово. Архивы в dist/ — каждый грузится отдельно."
      if zamechaniy == 0 else f"Замечаний: {zamechaniy}.")
sys.exit(1 if zamechaniy else 0)
PY
