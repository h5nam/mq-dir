"""mq-dir brandkit generator — gpt-image-2.

Usage:
    python gen.py --list                 list known assets
    python gen.py --dry-run              print plan, no API calls
    python gen.py app_icon               generate one asset
    python gen.py app_icon mark          generate several
    python gen.py                        generate ALL missing assets
    python gen.py --force all            regenerate everything (overwrites)

Skip-if-exists by default. Re-runs are free unless --force.
Concurrency capped at 3 to stay polite to the API.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import os
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent / ".env")
    load_dotenv(Path(__file__).parent.parent / ".env")
except ImportError:
    pass

# `openai` is imported lazily inside `_runner` so that --list and --dry-run
# work without requiring the SDK to be installed.


# ─────────────────────────────────────────────────────────────────────────────
# Brand spec (single source of truth)
# ─────────────────────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class Swatch:
    name: str
    hex: str
    role: str


PALETTE: tuple[Swatch, ...] = (
    Swatch("Desktop",   "#0a0a0c", "near-black, deep window backdrop"),
    Swatch("Window",    "#1d1d1f", "primary surface, pane interior"),
    Swatch("Surface",   "#28282a", "elevated chrome (toolbar, sidebar)"),
    Swatch("Accent",    "#0a84ff", "macOS system blue — focus, selection"),
    Swatch("Label",     "#f5f5f7", "paper-white text"),
)


# Shared brief context. Every asset uses this so the brand voice stays
# consistent. Style is intentionally a designer's brief — situation, context,
# desired output — not a pixel-level spec sheet.
CLIENT_CONTEXT = """\
CLIENT
mq-dir is a new open-source macOS file manager for power users.
Tagline: "The file manager that remembers." It persists exactly where you
were when you quit — sort, scroll, view mode, every tab. MIT-licensed,
no telemetry, native Apple Silicon, dark-mode-first, monospace-accented.
Lineage: obsessively-crafted indie Mac apps (Iina, NetNewsWire, Things 3)
and developer-tool branding (Linear, Vercel, Stripe Press). Opposite of
Electron, opposite of flashy.

AUDIENCE
Senior software engineers who recognize editorial design when they see it.

PALETTE NOTE
Mostly very dark surfaces (near-black + deep charcoal). Type is paper-white.
The single accent is macOS system blue. The brand reads as quiet, technical,
restrained.

LOGO TREATMENT
The brand mark is rendered in GLASSMORPHISM — frosted translucent panels,
subtle 1px light-catching borders, soft inner luminance, hints of color
bleeding through the glass. Apple Big Sur / Sonoma / iOS 17+ icon era,
visionOS panes. Premium, calm, native — never flashy or cartoonish. The
mark's form is at the designer's discretion (literal Q-Dir 4-pane heritage,
abstract, monogram, typographic — all valid).
"""


PERSONA = (
    "You are a senior brand designer at a Pentagram-tier studio with full "
    "creative latitude. Make every layout, hierarchy, and composition "
    "decision yourself."
)


GLOBAL_DON_TS = """\
DON'T
No photographic imagery. No people or devices in illustration. No marketing
copy. No emoji. No flashy startup energy. No cartoonish treatments.
"""


# ─────────────────────────────────────────────────────────────────────────────
# Asset definitions
# ─────────────────────────────────────────────────────────────────────────────


@dataclass
class Asset:
    key: str
    size: str          # "1024x1024" | "1024x1536" | "1536x1024"
    quality: str       # "low" | "medium" | "high"
    out_filename: str
    prompt: str


OUT_DIR = Path(__file__).parent / "output"
LOG_DIR = OUT_DIR / "_logs"


def _brief(deliverable: str, must_convey: str, extras: str = "") -> str:
    return "\n\n".join(
        s for s in [
            PERSONA,
            CLIENT_CONTEXT,
            "DELIVERABLE\n" + deliverable.strip(),
            "MUST CONVEY\n" + must_convey.strip(),
            extras.strip(),
            GLOBAL_DON_TS,
            "TONE\nQuiet, technical, restrained, premium. Aspire to Apple HIG "
            "documentation, Stripe design-system docs, Linear's brand site.",
        ] if s
    )


def _build_assets() -> list[Asset]:
    return [
        # ──────────────────────────────────────────────────────────────
        # Asset reference page (the canonical brand contact sheet)
        # ──────────────────────────────────────────────────────────────
        Asset(
            key="brand_assets_page",
            size="1024x1536",
            quality="high",
            out_filename="brand_assets_page.png",
            prompt=_brief(
                deliverable=(
                    "A single brand-assets reference page, 1024x1536 portrait. "
                    "This is NOT a marketing poster — it is a calm, organized REFERENCE "
                    "page that a developer would screenshot and pin in Figma to remember "
                    "the brand. Reference quality target: Apple HIG asset documentation, "
                    "Stripe design-system docs, Linear's brand kit page, Material 3 "
                    "color/typography pages."
                ),
                must_convey=(
                    "— The primary logo plus 2 to 4 variations (mark-only, wordmark, "
                    "monochrome, reversed). Each variation clearly LABELED.\n"
                    "— The brand color palette as 4–5 swatches, each labeled with HEX "
                    "and a short role name (desktop, window, accent, label, etc.).\n"
                    "— Typography specimen: monospace display family (used for the "
                    "wordmark) and humanist sans body family. Use 'mq-dir' as headline "
                    "specimen, the tagline as sentence specimen.\n"
                    "— The tagline 'The file manager that remembers.' integrated "
                    "somewhere prominent.\n"
                    "— A small footer hinting at the brand stance: open source, MIT, "
                    "no telemetry, macOS 14+."
                ),
                extras=(
                    "LAYOUT NOTE\n"
                    "The glassmorphism treatment is for the LOGO ONLY — the rest of "
                    "the page (palette swatches, typography specimens, footer, labels) "
                    "stays clean editorial without glass effects."
                ),
            ),
        ),

        # ──────────────────────────────────────────────────────────────
        # macOS App Icon master (downsampled for AppIcon.appiconset)
        # ──────────────────────────────────────────────────────────────
        Asset(
            key="app_icon",
            size="1024x1024",
            quality="high",
            out_filename="app_icon_master.png",
            prompt=_brief(
                deliverable=(
                    "A 1024x1024 macOS Application Icon master. The build system will "
                    "downsample this single PNG to every standard macOS icon size "
                    "(16, 32, 64, 128, 256, 512, 1024) — the composition must remain "
                    "readable and crisp at every scale, including 16x16."
                ),
                must_convey=(
                    "— An Apple-style continuous-curvature squircle filling the canvas, "
                    "rendered in the brand's glassmorphism language.\n"
                    "— A brand mark inside the squircle (form at the designer's "
                    "discretion — see LOGO TREATMENT above; legibility at 16x16 is "
                    "non-negotiable).\n"
                    "— The brand palette showing through the glass: bright, "
                    "luminous frosted glass interior with the macOS system blue "
                    "accent. Think Apple's own Settings, Finder, or Music app icon "
                    "— bright glass body, never a dark vignette."
                ),
                extras=(
                    "ABSOLUTELY NO\n"
                    "No wordmark text or labels — this is the icon glyph only.\n"
                    "No drop shadows under the squircle — the OS adds those.\n"
                    "No dark frosted edge or vignette around the squircle's perimeter "
                    "— the squircle interior must read as uniformly bright luminous "
                    "glass from edge to edge, with only the brightness gradient "
                    "Apple's icon-grid template uses (subtle top-light highlight).\n"
                    "The canvas BACKGROUND outside the squircle MUST be pure black "
                    "(#000000) with absolutely no glow, halo, ambient light, or "
                    "gradient bleed — a hard binary edge between squircle and void."
                ),
            ),
        ),

        # ──────────────────────────────────────────────────────────────
        # Standalone mark (for favicon, social avatars, embedded contexts)
        # ──────────────────────────────────────────────────────────────
        Asset(
            key="mark",
            size="1024x1024",
            quality="high",
            out_filename="mark.png",
            prompt=_brief(
                deliverable=(
                    "A 1024x1024 standalone brand mark for use in favicons, social "
                    "avatars, and inline contexts where the App Icon's squircle frame "
                    "is not appropriate. The mark sits centered with comfortable "
                    "padding on a solid dark surface."
                ),
                must_convey=(
                    "— The brand mark, rendered in glassmorphism, consistent with the "
                    "brand assets reference page.\n"
                    "— A solid dark background filling the canvas (this asset is not "
                    "transparent — it embeds in contexts that need an opaque tile)."
                ),
                extras=(
                    "ABSOLUTELY NO\n"
                    "No surrounding squircle (this is NOT the App Icon). No wordmark, "
                    "no labels, no decoration outside the mark itself."
                ),
            ),
        ),

        # ──────────────────────────────────────────────────────────────
        # Horizontal lockup (mark + wordmark)
        # ──────────────────────────────────────────────────────────────
        Asset(
            key="wordmark",
            size="1536x1024",
            quality="high",
            out_filename="wordmark.png",
            prompt=_brief(
                deliverable=(
                    "A 1536x1024 horizontal lockup combining the brand mark and the "
                    "wordmark 'mq-dir'. Used as the primary lockup for site headers, "
                    "document covers, and presentation slides."
                ),
                must_convey=(
                    "— The glassmorphism brand mark on the left.\n"
                    "— The wordmark 'mq-dir' on the right, rendered in monospace "
                    "(JetBrains Mono Medium or equivalent), lowercase with the hyphen, "
                    "paper-white. The wordmark itself is NOT glassmorphism — it is "
                    "clean type next to the glass mark.\n"
                    "— A deep near-black background filling the canvas."
                ),
            ),
        ),

        # ──────────────────────────────────────────────────────────────
        # GitHub README hero banner
        # ──────────────────────────────────────────────────────────────
        Asset(
            key="readme_hero",
            size="1536x1024",
            quality="high",
            out_filename="readme_hero.png",
            prompt=_brief(
                deliverable=(
                    "A 1536x1024 landscape banner that lives at the top of the "
                    "project's GitHub README. It introduces the brand to a developer "
                    "who has just landed on the repo."
                ),
                must_convey=(
                    "— The wordmark 'mq-dir' prominently.\n"
                    "— The tagline 'The file manager that remembers.' integrated into "
                    "the composition.\n"
                    "— The glassmorphism brand mark, consistent with the rest of the kit.\n"
                    "— A subtle hint that this is a quad-pane file manager (designer's "
                    "choice of how — could be the mark itself, could be a stylized "
                    "illustration, could be purely typographic)."
                ),
            ),
        ),

        # ──────────────────────────────────────────────────────────────
        # OpenGraph social-preview card
        # ──────────────────────────────────────────────────────────────
        Asset(
            key="og_card",
            size="1536x1024",
            quality="high",
            out_filename="og_card.png",
            prompt=_brief(
                deliverable=(
                    "A 1536x1024 social-preview card for use as the OpenGraph image — "
                    "what is shown when someone pastes a link to mq-dir on Twitter, "
                    "Slack, iMessage, Discord. The actual displayed area when scaled "
                    "down to 1200x630 is a centered safe-area, so keep critical content "
                    "in the central region of the canvas."
                ),
                must_convey=(
                    "— The wordmark 'mq-dir', large and centered.\n"
                    "— The tagline 'The file manager that remembers.'\n"
                    "— The glassmorphism brand mark.\n"
                    "— A small footer line: 'macOS 14+ · MIT · open-source'."
                ),
                extras=(
                    "RENDER NOTE\n"
                    "Crisp text at the target display size (around 600px tall on a "
                    "social timeline). Don't pack the composition — air is part of "
                    "the brand."
                ),
            ),
        ),

        # ──────────────────────────────────────────────────────────────
        # Landing-page hero illustration (faux-screenshot stylization)
        # ──────────────────────────────────────────────────────────────
        Asset(
            key="hero_illustration",
            size="1024x1536",
            quality="high",
            out_filename="hero_illustration.png",
            prompt=_brief(
                deliverable=(
                    "A 1024x1536 portrait illustration that introduces the app on the "
                    "landing page. The viewer should look at this and instantly "
                    "understand: 'this is a quad-pane macOS file manager'. This is a "
                    "STYLIZED RENDERING of the app's interface — not a literal "
                    "screenshot, but precise enough that a developer recognizes the genre."
                ),
                must_convey=(
                    "— A four-pane 2x2 layout (the product's signature).\n"
                    "— Tabs within each pane.\n"
                    "— One focused pane indicated with a macOS system blue accent.\n"
                    "— A sidebar with file system favorites (Desktop, Documents, "
                    "Downloads, etc.).\n"
                    "— Generally that this is a polished, native, dark-mode macOS app.\n"
                    "— A small wordmark 'mq-dir' somewhere in a corner as a stamp."
                ),
                extras=(
                    "GLASSMORPHISM EXCEPTION\n"
                    "The illustration depicts the app's actual UI — DO NOT apply "
                    "glassmorphism to the UI panels themselves. The UI is rendered "
                    "in its native dark-mode style (#0a0a0c desktop, #1d1d1f panes, "
                    "#0a84ff focus). Glass treatment is reserved for the small "
                    "wordmark stamp / brand mark element only."
                ),
            ),
        ),

        # ──────────────────────────────────────────────────────────────
        # DMG installer backdrop (drag-to-Applications screen)
        # ──────────────────────────────────────────────────────────────
        Asset(
            key="dmg_background",
            size="1536x1024",
            quality="high",
            out_filename="dmg_background.png",
            prompt=_brief(
                deliverable=(
                    "A 1536x1024 background image that fills the .dmg installer window. "
                    "The user double-clicks the downloaded .dmg and sees this — they "
                    "drag the app icon onto an Applications-folder shortcut to install. "
                    "Will be scaled to 540x380 inside the .dmg window — keep critical "
                    "elements legible at that size."
                ),
                must_convey=(
                    "— The install gesture: app icon on the left → arrow pointing "
                    "right → Applications folder on the right.\n"
                    "— The app icon rendered in the brand's glassmorphism style "
                    "(consistent with the brand assets page).\n"
                    "— Restrained branding focused on the install action — not a "
                    "marketing surface.\n"
                    "— A small 'mq-dir v0.1.0' watermark somewhere in a corner is fine."
                ),
                extras=(
                    "RENDER NOTE\n"
                    "The DMG window appears against macOS Finder chrome — the "
                    "background should read clearly in that context. Dark surface "
                    "is preferred (matches the brand) but not mandatory."
                ),
            ),
        ),
    ]


ASSETS = _build_assets()


# ─────────────────────────────────────────────────────────────────────────────
# Generation runtime
# ─────────────────────────────────────────────────────────────────────────────


MODEL = "gpt-image-2"
MAX_CONCURRENT = 3


async def _generate(
    client: "openai.AsyncOpenAI",  # type: ignore[name-defined]
    asset: Asset,
    *,
    force: bool,
    log_path: Path,
) -> str:
    out = OUT_DIR / asset.out_filename
    if out.exists() and not force:
        return f"skip-exists ({out.name})"

    t0 = time.time()
    resp = await client.images.generate(
        model=MODEL,
        prompt=asset.prompt,
        size=asset.size,
        quality=asset.quality,
        n=1,
    )
    elapsed = time.time() - t0

    b64 = resp.data[0].b64_json
    if not b64:
        return "FAIL no_b64_in_response"
    png = base64.b64decode(b64)

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(png)

    return f"ok {len(png):,}B in {elapsed:.1f}s"


async def _runner(targets: list[Asset], force: bool, dry_run: bool) -> int:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_path = LOG_DIR / f"{datetime.now():%Y-%m-%d-%H%M%S}.log"

    print(f"target  : {len(targets)} asset(s)")
    print(f"model   : {MODEL}")
    print(f"force   : {force}")
    print(f"dry-run : {dry_run}")
    print(f"log     : {log_path}")
    print()

    if dry_run:
        for a in targets:
            out = OUT_DIR / a.out_filename
            mark = "EXISTS" if out.exists() else "MISSING"
            action = "skip" if out.exists() and not force else "generate"
            print(f"  [{mark:7}] {a.key:24} {a.size:11} {a.quality:6} → {action}")
        return 0

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print("ERROR: OPENAI_API_KEY not set (env or .env)", file=sys.stderr)
        return 1

    try:
        import openai  # lazy import — keeps --list / --dry-run usable without the SDK
    except ImportError:
        print("ERROR: openai SDK not installed. Run `pip install -r requirements.txt`.",
              file=sys.stderr)
        return 1

    client = openai.AsyncOpenAI(api_key=api_key)
    sem = asyncio.Semaphore(MAX_CONCURRENT)

    async def _one(asset: Asset) -> tuple[str, str]:
        async with sem:
            try:
                msg = await _generate(client, asset, force=force, log_path=log_path)
                return (asset.key, msg)
            except Exception as e:
                return (asset.key, f"FAIL {type(e).__name__}: {e}")

    results = await asyncio.gather(*(_one(a) for a in targets))
    with log_path.open("w") as f:
        for k, m in results:
            line = f"{k:24} {m}"
            print(line)
            f.write(line + "\n")

    failures = [r for r in results if r[1].startswith("FAIL")]
    return 1 if failures else 0


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────


def _resolve(keys: list[str]) -> list[Asset]:
    by_key = {a.key: a for a in ASSETS}
    if not keys or keys == ["all"]:
        return list(ASSETS)
    unknown = [k for k in keys if k not in by_key]
    if unknown:
        print(f"unknown asset key(s): {unknown}", file=sys.stderr)
        print(f"known: {list(by_key)}", file=sys.stderr)
        sys.exit(2)
    return [by_key[k] for k in keys]


def _cmd_list() -> None:
    print(f"{'KEY':22}  {'SIZE':10}  {'QUAL':6}  {'EXISTS':8}  OUTPUT")
    print(f"{'-'*22}  {'-'*10}  {'-'*6}  {'-'*8}  {'-'*30}")
    for a in ASSETS:
        out = OUT_DIR / a.out_filename
        mark = "yes" if out.exists() else " - "
        print(f"{a.key:22}  {a.size:10}  {a.quality:6}  {mark:8}  {a.out_filename}")


def main() -> int:
    p = argparse.ArgumentParser(description="mq-dir brandkit generator")
    p.add_argument("assets", nargs="*",
                   help="asset key(s) to generate; 'all' or empty = every asset")
    p.add_argument("--force", action="store_true",
                   help="regenerate even if the output file exists")
    p.add_argument("--dry-run", action="store_true",
                   help="print the plan, no API calls")
    p.add_argument("--list", action="store_true",
                   help="list known assets and which already exist")
    args = p.parse_args()

    if args.list:
        _cmd_list()
        return 0

    targets = _resolve(args.assets)
    return asyncio.run(_runner(targets, args.force, args.dry_run))


if __name__ == "__main__":
    sys.exit(main())
