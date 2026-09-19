#!/usr/bin/env bash
# Сборка архивов навыков для загрузки в чужие среды.
#
#   ./soberi-zip.sh               собрать dist/ и dist/perplexity/
#   ./soberi-zip.sh --otpechatki  пересчитать отпечатки в perplexity-opisaniya.json
#
# Собирается ДВА набора одного и того же материала:
#
#   dist/             — по архиву на навык, описания как в репозитории.
#                       Основной набор: ученикам, в другие среды, про запас.
#   dist/perplexity/  — то же, но описания, не влезающие в 1024 БАЙТА, заменены
#                       короткими из perplexity-opisaniya.json. SKILL.md навыков
#                       при этом не правится: подмена живёт только в архиве.
#                       Perplexity принимает по пять файлов за отправку —
#                       десять навыков грузятся тремя заходами.
#
# В архивы НЕ кладётся:
#   _ishodniki/  — исходные PDF с НЕобезличенными данными;
#   .git/        — история репозитория, сотни файлов;
#   .DS_Store и служебные двойники Finder (`._имя`, `__MACOSX`).
# Первое — причина, по которой архивы собираются этим сценарием, а не мышью:
# «Сжать» в Finder кладёт в архив всю папку целиком, вместе с исходниками.
#
# Почему через python3, а не командой zip: Apple-версия zip не умеет ключ
# -UN=UTF8 и пишет русские имена файлов без признака кодировки. На Windows такой
# архив распаковывается кракозябрами, а у образцов имя файла — часть обозначения
# документа по ЕСПД. python3 проставляет признак UTF-8 сам.

set -uo pipefail
cd "$(dirname "$0")" || exit 1

command -v python3 >/dev/null || { echo "нужен python3"; exit 1; }

python3 - "$@" <<'PY'
import hashlib, json, os, re, shutil, sys, zipfile

PREDEL_FAJLOV = 100       # потолок числа файлов на архив
PREDEL_OPISANIYA = 1024   # потолок длины description, В БАЙТАХ
ZA_OTPRAVKU = 5           # сколько файлов Perplexity принимает за один раз
VYHOD = "dist"
OPISANIYA = "perplexity-opisaniya.json"
MUSOR = {".DS_Store", "Thumbs.db", "desktop.ini", "__MACOSX"}

# Про байты. Perplexity меряет description байтами, а не знаками: в отказе виден
# Go-сервис, а там len(строки) — длина в байтах. Кириллица в UTF-8 весит два байта
# на букву, поэтому русское описание упирается в предел вдвое раньше — около
# 512 знаков. Замер 19.09.2026: из десяти навыков принят был ровно один —
# единственный с описанием короче 1024 байт, хотя по ЗНАКАМ проходили девять.

zamechaniy = 0

def zamechanie(tekst):
    global zamechaniy
    print(tekst)
    zamechaniy += 1

def musor(imya):
    return imya in MUSOR or imya.startswith("._")

def fajly_navyka(katalog):
    """Файлы навыка без мусора, в устойчивом порядке."""
    sobrano = []
    for koren, katalogi, imena in os.walk(katalog):
        katalogi[:] = sorted(k for k in katalogi if not musor(k))
        for f in sorted(imena):
            if not musor(f):
                sobrano.append(os.path.join(koren, f))
    return sobrano

def shapka_i_telo(put):
    """YAML-шапка и остальной текст SKILL.md."""
    tekst = open(put, encoding="utf-8").read()
    m = re.match(r"^(---\n.*?\n---\n)(.*)$", tekst, re.S)
    return (m.group(1), m.group(2)) if m else (None, tekst)

def opisanie(put):
    """Значение description из шапки, без кавычек."""
    shapka, _ = shapka_i_telo(put)
    if shapka is None:
        return None
    m = re.search(r"^description:\s*(.*)$", shapka, re.M)
    return m.group(1).strip().strip('"') if m else None

def otpechatok(tekst):
    return hashlib.sha256(tekst.encode("utf-8")).hexdigest()[:12]

def bajt(tekst):
    return len(tekst.encode("utf-8"))

def zapisat(arhiv, pary):
    """pary — список (путь на диске, путь внутри архива)."""
    with zipfile.ZipFile(arhiv, "w", zipfile.ZIP_DEFLATED) as z:
        for otkuda, kuda in pary:
            z.write(otkuda, kuda)

def ves(put):
    b = os.path.getsize(put)
    return f"{b/1024:.0f}K" if b < 1024**2 else f"{b/1024**2:.1f}M"

nastrojki = json.load(open(OPISANIYA, encoding="utf-8"))
korotkie = {k: v for k, v in nastrojki.items() if not k.startswith("_")}

navyki = sorted(d for d in os.listdir("skills")
                if os.path.isfile(f"skills/{d}/SKILL.md"))

# ─────────────────────────────────────────────── пересчёт отпечатков

if "--otpechatki" in sys.argv:
    for imya, zapis in korotkie.items():
        polnoe = opisanie(f"skills/{imya}/SKILL.md")
        if polnoe is None:
            print(f"{imya:<20}навыка нет в skills/ — запись лишняя")
            continue
        zapis["otpechatok"] = otpechatok(polnoe)
        print(f"{imya:<20}{zapis['otpechatok']}")
    json.dump(nastrojki, open(OPISANIYA, "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)
    print(f"\nОтпечатки записаны в {OPISANIYA}.")
    sys.exit(0)

# ─────────────────────────────────────────────── набор 1: как в репозитории

shutil.rmtree(VYHOD, ignore_errors=True)
os.makedirs(os.path.join(VYHOD, "perplexity"))

sobrannye = {}   # навык → (файлы, вес архива)

print("dist/ — по архиву на навык, описания как в репозитории")
print(f'{"Навык":<20}{"Файлов":>8}{"Размер":>9}{"Описание":>10}')

for imya in navyki:
    katalog = f"skills/{imya}"
    fajly = fajly_navyka(katalog)

    pdf = [f for f in fajly if f.lower().endswith(".pdf")]
    if pdf:
        zamechanie(f"   {imya}: внутри PDF ({len(pdf)} шт.) — проверьте, "
                   f"обезличены ли они; архив не собран")
        continue

    arhiv = os.path.join(VYHOD, imya + ".zip")
    zapisat(arhiv, [(f, os.path.relpath(f, katalog)) for f in fajly])
    sobrannye[imya] = fajly

    print(f"{imya:<20}{len(fajly):>8}{ves(arhiv):>9}{bajt(opisanie(f'{katalog}/SKILL.md') or ''):>10}")
    if len(fajly) > PREDEL_FAJLOV:
        zamechanie(f"   ^ файлов больше {PREDEL_FAJLOV}: навык надо делить")

# ─────────────────────────────────────────────── набор 2: под Perplexity

katalog_p = os.path.join(VYHOD, "perplexity")

print(f"\ndist/perplexity/ — description ≤ {PREDEL_OPISANIYA} байт "
      f"(грузить по {ZA_OTPRAVKU} файлов за отправку)")
print(f'{"Навык":<20}{"Файлов":>8}{"Размер":>9}{"Описание":>10}  Откуда описание')

lishnie = set(korotkie) - set(navyki)
if lishnie:
    zamechanie(f"   в {OPISANIYA} записи для несуществующих навыков: "
               f"{', '.join(sorted(lishnie))}")

for imya, fajly in sobrannye.items():
    katalog = f"skills/{imya}"
    skill_md = f"{katalog}/SKILL.md"
    polnoe = opisanie(skill_md) or ""

    if bajt(polnoe) <= PREDEL_OPISANIYA:
        # Влезает как есть — короткий вариант не нужен и не заводится:
        # чем меньше текста живёт в двух местах, тем меньше ему расходиться.
        itogovoe, otkuda = polnoe, "как в навыке"
        if imya in korotkie:
            zamechanie(f"   {imya}: полное описание влезает ({bajt(polnoe)} байт), "
                       f"запись в {OPISANIYA} больше не нужна")
    else:
        zapis = korotkie.get(imya)
        if zapis is None:
            zamechanie(f"   {imya}: описание весит {bajt(polnoe)} байт при пределе "
                       f"{PREDEL_OPISANIYA}, а короткого в {OPISANIYA} нет — "
                       f"архив не собран")
            continue

        if not zapis.get("otpechatok"):
            zamechanie(f"   {imya}: отпечаток не проставлен, сверить не с чем. "
                       f"Выполнить ./soberi-zip.sh --otpechatki")
        elif zapis["otpechatok"] != otpechatok(polnoe):
            zamechanie(f"   {imya}: полное описание переписали, а короткое в "
                       f"{OPISANIYA} осталось прежним. Перечитать его и выполнить "
                       f"./soberi-zip.sh --otpechatki")

        itogovoe, otkuda = zapis["description"], "короткое"
        if bajt(itogovoe) > PREDEL_OPISANIYA:
            izlishek = bajt(itogovoe) - PREDEL_OPISANIYA
            zamechanie(f"   {imya}: короткое описание само весит {bajt(itogovoe)} байт: "
                       f"сократить ещё на {izlishek} байт (по-русски это примерно "
                       f"{(izlishek + 1)//2} знаков)")
            continue

    shapka, telo = shapka_i_telo(skill_md)
    shapka = re.sub(r"^description:.*$",
                    "description: " + json.dumps(itogovoe, ensure_ascii=False),
                    shapka, count=1, flags=re.M)

    vremennyj = os.path.join(VYHOD, f".{imya}.SKILL.md")
    open(vremennyj, "w", encoding="utf-8").write(shapka + telo)

    pary = [(vremennyj, "SKILL.md")]
    pary += [(f, os.path.relpath(f, katalog)) for f in fajly
             if os.path.relpath(f, katalog) != "SKILL.md"]

    arhiv = os.path.join(katalog_p, imya + ".zip")
    zapisat(arhiv, pary)
    os.remove(vremennyj)

    print(f"{imya:<20}{len(pary):>8}{ves(arhiv):>9}{bajt(itogovoe):>10}  {otkuda}")

zahodov = (len(sobrannye) + ZA_OTPRAVKU - 1) // ZA_OTPRAVKU
print()
print(f"Готово. dist/ — {len(sobrannye)} архивов; dist/perplexity/ — столько же "
      f"с короткими описаниями, грузить {zahodov} заходами по {ZA_OTPRAVKU}."
      if zamechaniy == 0 else f"Замечаний: {zamechaniy}.")
sys.exit(1 if zamechaniy else 0)
PY
