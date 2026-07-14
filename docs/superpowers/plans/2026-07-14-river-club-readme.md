# River Club GitHub README Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a polished Chinese GitHub README for River Club, create three accurate product showcase images, validate the result, and publish it through a draft pull request.

**Architecture:** A deterministic Pillow renderer creates project-owned visuals from shapes, text, and the existing design tokens. The README references those local PNG files and derives every claim from the repository. A validation script checks required sections, image links, dimensions, and the no-cash-value disclaimer.

**Tech Stack:** Markdown, Python 3, Pillow 12.2.0, Swift 6 project metadata, local Git, GitHub CLI or GitHub connector.

## Global Constraints

- The README is Chinese-first and targets clients and the project team.
- The product name is always “River Club”; the workspace directory name is not branding.
- Describe an iPhone landscape SwiftUI Texas Hold’em UI prototype using virtual chips with no cash value.
- Do not claim multiplayer networking, a rules engine, production authentication, a backend, App Store availability, or real-money features.
- Use the established deep green, near-black green, warm white, walnut brown, and antique gold visual language.
- Do not use Replay Poker trademarks, logos, illustrations, or proprietary assets.
- Images live under `docs/images/` and remain readable on light and dark GitHub themes.
- Runtime requirements match `project.yml`: Swift 6, iOS 18+, iPhone, landscape orientations.
- Do not claim tests passed when full Xcode is unavailable.
- Publish `agent/add-project-readme` through a draft PR; do not push directly to `main`.

---

## Planned File Structure

```text
README.md                              GitHub project landing page
docs/images/river-club-cover.png       1600×760 branded overview
docs/images/river-club-table.png       1600×820 nine-seat table
docs/images/river-club-screens.png     1600×900 four-screen overview
scripts/render_readme_assets.py        Deterministic Pillow image source
scripts/validate_readme.py             Markdown and image integrity checks
```

### Task 1: Deterministic README Artwork

**Files:**
- Create: `scripts/render_readme_assets.py`
- Create: `docs/images/river-club-cover.png`
- Create: `docs/images/river-club-table.png`
- Create: `docs/images/river-club-screens.png`

**Interfaces:**
- Consumes: colors from `RiverClub/DesignSystem/Theme.swift` and layout facts from the feature views.
- Produces: `render_all(output_dir: Path) -> list[Path]` and three PNG files with exact dimensions.

- [ ] **Step 1: Create the renderer foundation**

Create `scripts/render_readme_assets.py` with the following public constants and interfaces:

```python
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "docs" / "images"
COLORS = {
    "background": "#091C17", "surface": "#0F2921",
    "raised": "#17382E", "felt": "#126044",
    "gold": "#D6AD57", "warm_white": "#F5EDE0",
    "secondary": "#9AAFA5", "walnut": "#55321B",
    "red": "#B53A3A",
}

def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    path = Path("/System/Library/Fonts/PingFang.ttc")
    if path.exists():
        return ImageFont.truetype(str(path), size=size, index=1 if bold else 0)
    return ImageFont.load_default()

def rounded_panel(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int],
                  radius: int = 28, fill: str = COLORS["surface"]) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline="#29483F", width=2)

def draw_table_scene(image: Image.Image, box: tuple[int, int, int, int], compact: bool = False) -> None:
    """Draw rail, felt, board, pot, chip stack, nine seats and actions."""

def draw_screen_card(image: Image.Image, box: tuple[int, int, int, int],
                     title: str, variant: str) -> None:
    """Draw one of lobby, tables, tournaments or profile."""

def render_cover() -> Image.Image:
    """Return the 1600×760 brand and product overview."""

def render_table() -> Image.Image:
    """Return the 1600×820 full nine-seat table showcase."""

def render_screens() -> Image.Image:
    """Return the 1600×900 two-by-two core-screen overview."""

def render_all(output_dir: Path = OUTPUT_DIR) -> list[Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    assets = {
        "river-club-cover.png": render_cover(),
        "river-club-table.png": render_table(),
        "river-club-screens.png": render_screens(),
    }
    paths = []
    for name, image in assets.items():
        path = output_dir / name
        image.save(path, format="PNG", optimize=True)
        paths.append(path)
    return paths

if __name__ == "__main__":
    for rendered in render_all():
        print(rendered.relative_to(ROOT))
```

Implement each drawing function with explicit Pillow primitives. The table scene contains eight opponents, one centered local player, five community cards, pot, chips, and three actions. The screen cards reuse one sidebar and the established green/gold hierarchy. Do not load network images or third-party art.

- [ ] **Step 2: Render and inspect the images**

Run:

```bash
/Users/lele/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 scripts/render_readme_assets.py
```

Expected: the three `docs/images/river-club-*.png` paths. Open each at original detail and confirm no clipped Chinese text, nine visible seats, a centered local player, non-overlapping board/actions, and four distinguishable overview screens.

- [ ] **Step 3: Verify dimensions**

Run:

```bash
/Users/lele/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -c 'from pathlib import Path; from PIL import Image; expected={"river-club-cover.png":(1600,760),"river-club-table.png":(1600,820),"river-club-screens.png":(1600,900)}; [print(p.name, Image.open(p).size) for p in sorted(Path("docs/images").glob("river-club-*.png")) if Image.open(p).size == expected[p.name]]'
```

Expected: three lines with the exact dimensions.

- [ ] **Step 4: Commit artwork**

```bash
git add scripts/render_readme_assets.py docs/images
git commit -m "docs: add River Club showcase artwork"
```

### Task 2: Chinese GitHub README

**Files:**
- Create: `README.md`
- Read: `project.yml`
- Read: `RiverClub/App/AppSession.swift`
- Read: `RiverClub/Services/PokerRepository.swift`
- Read: `RiverClubTests/*.swift`
- Read: `RiverClubUITests/*.swift`

**Interfaces:**
- Consumes: Task 1 images and verified repository facts.
- Produces: a GitHub-renderable README with stable relative image paths.

- [ ] **Step 1: Create the approved Markdown structure**

Create `README.md` with this exact section and media skeleton, then fill each heading with concise repository-verifiable Chinese copy:

```markdown
<p align="center">
  <img src="docs/images/river-club-cover.png" alt="River Club iOS 横屏扑克 UI 原型概览" width="100%">
</p>

# River Club

> 使用 SwiftUI 构建的沉浸式 iPhone 横屏德州扑克 UI 原型。

![Swift 6](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![iOS 18+](https://img.shields.io/badge/iOS-18%2B-111111?logo=apple)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0B84F3)

## 项目简介
## 界面展示
![River Club 九人横屏牌桌](docs/images/river-club-table.png)
![River Club 核心页面](docs/images/river-club-screens.png)
## 核心功能
## 体验流程
## 技术实现
## 项目结构
## 本地运行
## 测试
## 当前范围
## 后续方向
## 免责声明
```

The run section states Xcode 26, iOS 18 Simulator, and XcodeGen 2.43+, then uses `xcodegen generate` and opens `RiverClub.xcodeproj`. The test section gives the repository `xcodebuild test` command and notes that a full Xcode developer directory is required.

- [ ] **Step 2: Verify claims against source**

```bash
rg -n "enum AppRoute|sidebarRoutes|case login|case lobby|case tables|case table|case tournaments|case profile" RiverClub/App
rg -n "loading|empty|offline|failed|seats.count == 9" RiverClub RiverClubTests RiverClubUITests
rg -n "SWIFT_VERSION|IPHONEOS_DEPLOYMENT_TARGET|UIInterfaceOrientationLandscape" project.yml
```

Expected: evidence for all seven screens, state handling, nine seats, Swift 6, iOS 18, and landscape orientation.

- [ ] **Step 3: Commit README**

```bash
git add README.md
git commit -m "docs: add River Club project README"
```

### Task 3: Integrity Validation

**Files:**
- Create: `scripts/validate_readme.py`
- Test: `README.md`
- Test: `docs/images/river-club-cover.png`
- Test: `docs/images/river-club-table.png`
- Test: `docs/images/river-club-screens.png`

**Interfaces:**
- Consumes: final Markdown and PNG assets.
- Produces: exit code `0` and `README validation passed`, or a precise assertion failure.

- [ ] **Step 1: Create the validator**

```python
import re
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
README = ROOT / "README.md"
EXPECTED_IMAGES = {
    "docs/images/river-club-cover.png": (1600, 760),
    "docs/images/river-club-table.png": (1600, 820),
    "docs/images/river-club-screens.png": (1600, 900),
}
REQUIRED_HEADINGS = [
    "项目简介", "界面展示", "核心功能", "体验流程", "技术实现",
    "项目结构", "本地运行", "测试", "当前范围", "后续方向", "免责声明",
]

def main() -> None:
    text = README.read_text(encoding="utf-8")
    for heading in REQUIRED_HEADINGS:
        assert re.search(rf"^## {re.escape(heading)}$", text, re.MULTILINE), f"missing heading: {heading}"
    assert "无现金价值" in text, "missing no-cash-value disclaimer"
    assert all(word in text for word in ("充值", "提现", "兑换", "真钱")), "incomplete product boundary"
    for relative, size in EXPECTED_IMAGES.items():
        assert relative in text, f"image is not referenced: {relative}"
        path = ROOT / relative
        assert path.is_file(), f"image does not exist: {relative}"
        with Image.open(path) as image:
            assert image.size == size, f"wrong dimensions for {relative}: {image.size}"
            assert image.mode in {"RGB", "RGBA"}, f"unexpected mode for {relative}: {image.mode}"
    print("README validation passed")

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run validation and scope checks**

```bash
/Users/lele/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 scripts/validate_readme.py
git diff --check main...HEAD
git status -sb
git diff --stat main...HEAD
```

Expected: `README validation passed`, no whitespace errors, and only the design spec, plan, README, two scripts, and three PNG files differ from `main`.

- [ ] **Step 3: Commit validator**

```bash
git add scripts/validate_readme.py
git commit -m "test: validate River Club README assets"
```

### Task 4: GitHub Publication

**Files:**
- No repository file changes expected.

**Interfaces:**
- Consumes: clean `agent/add-project-readme` with passing validation.
- Produces: pushed branch and draft PR targeting the default branch.

- [ ] **Step 1: Confirm prerequisites**

```bash
git remote -v
gh --version
gh auth status
```

Expected: an `origin` GitHub remote, installed GitHub CLI, and authenticated session. If any is missing, stop and request the repository URL or authentication setup.

- [ ] **Step 2: Re-run final validation and push**

```bash
/Users/lele/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 scripts/validate_readme.py
git status -sb
git push -u origin agent/add-project-readme
```

Expected: validation passes, branch is clean, and its remote tracking branch is created.

- [ ] **Step 3: Create a draft PR**

Use title `docs: add River Club project showcase`. The body lists the Chinese README, three original product visuals, documented scope/setup/tests, the validation command, and the environment note that full iOS tests were not rerun because Command Line Tools is selected. Prefer the GitHub connector; use `gh pr create --draft` only if repository inference is unavailable.

- [ ] **Step 4: Report publication details**

Report the branch, commit hashes, validation output, PR target, and draft PR URL. Do not state that the work is merged.
