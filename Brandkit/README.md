# mq-dir Brandkit

Generates the brand assets for mq-dir via OpenAI `gpt-image-2`.

Single source of truth lives in `gen.py` as a Python dataclass (`Brand`,
`PALETTE`). Each asset is one prompt that pulls from that spec — no hidden
duplication.

## Setup

```bash
cd Brandkit
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# put your key in either:
echo "OPENAI_API_KEY=sk-..." > .env             # this dir's .env
# ── or ─────────────────────────────────────────────────────────────
echo "OPENAI_API_KEY=sk-..." > ../.env          # repo-root .env
```

## Usage

```bash
python gen.py --list                # show all assets and which already exist
python gen.py --dry-run             # print plan, no API calls
python gen.py app_icon              # generate one asset
python gen.py app_icon mark         # generate several
python gen.py                       # generate every MISSING asset
python gen.py --force all           # regenerate everything (overwrites)
```

Outputs land in `output/`. Logs are written to `output/_logs/` with a
timestamp suffix.

## Wire the App Icon into Xcode

After `python gen.py app_icon` produces `output/app_icon_master.png`:

```bash
python postprocess.py
```

This writes 10 size variants and a fresh `Contents.json` to
`../Resources/Assets.xcassets/AppIcon.appiconset/`. Re-run xcodegen and
rebuild — the dock icon, Finder icon, and About box will all switch over.

## Asset list

| key                | size       | use                                            |
|--------------------|------------|------------------------------------------------|
| `app_icon`         | 1024×1024  | macOS App Icon master (squircle)               |
| `mark`             | 1024×1024  | standalone brand mark (favicons, social)       |
| `wordmark`         | 1536×1024  | horizontal "mq-dir" wordmark + mark lock-up    |
| `identity_sheet`   | 1024×1536  | brand spec one-pager (palette, type, lockups)  |
| `readme_hero`      | 1536×1024  | GitHub README banner                           |
| `og_card`          | 1536×1024  | OpenGraph social-preview card (→ 1200×630)     |
| `hero_illustration`| 1024×1536  | landing-page hero (faux-screenshot illustration)|
| `dmg_background`   | 1536×1024  | DMG installer backdrop (→ 540×380)             |

`gpt-image-2` natively supports only `1024x1024`, `1024x1536`, `1536x1024`.
Other targets (e.g. 1200×630 OG, 540×380 DMG) are post-cropped from the
nearest aspect-ratio source — done outside this script with `sips` or PIL.

## Cost & rate

`gpt-image-2 high` is ~3¢ per `1024×1024`, ~5¢ per `1024×1536` / `1536×1024`
at the time of writing. The full kit (8 assets) is ~$0.35. Skip-if-exists
prevents accidental re-runs from burning credit.

Concurrency capped at 3 simultaneous calls.

## Files

- `gen.py` — CLI generator + brand DNA + asset definitions
- `postprocess.py` — App Icon size-variant resampler (sips)
- `requirements.txt` — pip deps (openai, python-dotenv)
- `output/` — generated PNGs (gitignored)
- `output/_logs/` — timestamped run logs (gitignored)
