from __future__ import annotations

from pathlib import Path
from typing import Callable

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / "docs" / "images"

COLORS = {
    "background": "#091C17",
    "background_2": "#0C241D",
    "surface": "#0F2921",
    "raised": "#17382E",
    "felt": "#126044",
    "felt_light": "#197454",
    "gold": "#D6AD57",
    "gold_soft": "#8C713C",
    "warm_white": "#F5EDE0",
    "secondary": "#9AAFA5",
    "line": "#29483F",
    "walnut": "#55321B",
    "walnut_light": "#794A28",
    "red": "#B83D45",
    "black": "#050B09",
}


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        (Path("/System/Library/Fonts/Hiragino Sans GB.ttc"), 1 if bold else 0),
        (Path("/System/Library/Fonts/STHeiti Medium.ttc"), 0),
        (
            Path(
                "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
                if bold
                else "/System/Library/Fonts/Supplemental/Arial.ttf"
            ),
            0,
        ),
    ]
    for path, index in candidates:
        if not path.exists():
            continue
        try:
            return ImageFont.truetype(str(path), size=size, index=index)
        except OSError:
            continue
    return ImageFont.load_default()


def symbol_font(size: int) -> ImageFont.FreeTypeFont:
    path = Path("/System/Library/Fonts/Supplemental/Arial Unicode.ttf")
    if path.exists():
        return ImageFont.truetype(str(path), size=size)
    return font(size)


def text(
    draw: ImageDraw.ImageDraw,
    position: tuple[int, int],
    value: str,
    size: int,
    color: str = COLORS["warm_white"],
    bold: bool = False,
    anchor: str | None = None,
) -> None:
    draw.text(position, value, font=font(size, bold), fill=color, anchor=anchor)


def rounded_panel(
    draw: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    radius: int = 28,
    fill: str = COLORS["surface"],
    outline: str = COLORS["line"],
    width: int = 2,
) -> None:
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def pill(
    draw: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    label: str,
    selected: bool = False,
    size: int = 18,
) -> None:
    fill = COLORS["gold"] if selected else COLORS["raised"]
    label_color = COLORS["background"] if selected else COLORS["secondary"]
    draw.rounded_rectangle(box, radius=(box[3] - box[1]) // 2, fill=fill)
    text(draw, ((box[0] + box[2]) // 2, (box[1] + box[3]) // 2), label, size, label_color, True, "mm")


def chip_balance(draw: ImageDraw.ImageDraw, x: int, y: int, value: str = "128,500") -> None:
    draw.ellipse((x, y + 4, x + 22, y + 26), fill=COLORS["gold"], outline=COLORS["warm_white"], width=2)
    text(draw, (x + 33, y + 15), value, 18, COLORS["gold"], True, "lm")


def draw_sidebar(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], active: str) -> None:
    x0, y0, x1, y1 = box
    draw.rounded_rectangle(box, radius=18, fill=COLORS["background_2"])
    text(draw, (x0 + 22, y0 + 28), "RIVER", 13, COLORS["gold"], True)
    text(draw, (x0 + 22, y0 + 47), "CLUB", 22, COLORS["warm_white"], True)
    items = [("大厅", "lobby"), ("锦标赛", "tournaments"), ("我的牌局", "tables"), ("个人中心", "profile")]
    y = y0 + 96
    for label, key in items:
        if key == active:
            draw.rounded_rectangle((x0 + 12, y - 10, x1 - 12, y + 32), radius=12, fill=COLORS["raised"])
            draw.rectangle((x0 + 12, y - 2, x0 + 16, y + 23), fill=COLORS["gold"])
        text(draw, (x0 + 29, y + 10), label, 16, COLORS["warm_white"] if key == active else COLORS["secondary"], key == active, "lm")
        y += 54
    draw.ellipse((x0 + 22, y1 - 58, x0 + 56, y1 - 24), fill=COLORS["gold"])
    text(draw, (x0 + 39, y1 - 41), "R", 15, COLORS["background"], True, "mm")
    text(draw, (x0 + 68, y1 - 41), "RiverAce", 14, COLORS["warm_white"], True, "lm")


def draw_card(draw: ImageDraw.ImageDraw, x: int, y: int, rank: str, suit: str, scale: float = 1.0) -> None:
    width, height, radius = int(47 * scale), int(66 * scale), int(7 * scale)
    draw.rounded_rectangle((x, y, x + width, y + height), radius=radius, fill="#F7F2E9", outline="#D8D2C8", width=max(1, int(2 * scale)))
    color = COLORS["red"] if suit in {"♥", "♦"} else "#151B19"
    text(draw, (x + int(8 * scale), y + int(7 * scale)), rank, max(10, int(17 * scale)), color, True)
    draw.text(
        (x + int(10 * scale), y + int(30 * scale)),
        suit,
        font=symbol_font(max(10, int(18 * scale))),
        fill=color,
    )


def draw_seat(
    draw: ImageDraw.ImageDraw,
    center: tuple[int, int],
    initials: str,
    name: str,
    chips: str,
    local: bool = False,
    acting: bool = False,
    scale: float = 1.0,
) -> None:
    cx, cy = center
    avatar = int(24 * scale)
    panel_w, panel_h = int(124 * scale), int(54 * scale)
    border = COLORS["gold"] if acting or local else COLORS["line"]
    draw.rounded_rectangle(
        (cx - panel_w // 2, cy - panel_h // 2, cx + panel_w // 2, cy + panel_h // 2),
        radius=int(16 * scale), fill=COLORS["background_2"], outline=border, width=max(1, int(2 * scale)),
    )
    draw.ellipse((cx - panel_w // 2 + 8, cy - avatar, cx - panel_w // 2 + 8 + avatar * 2, cy + avatar), fill=COLORS["gold"] if local else COLORS["raised"])
    text(draw, (cx - panel_w // 2 + 8 + avatar, cy), initials, max(9, int(12 * scale)), COLORS["background"] if local else COLORS["warm_white"], True, "mm")
    tx = cx - panel_w // 2 + 17 + avatar * 2
    text(draw, (tx, cy - int(8 * scale)), name, max(9, int(12 * scale)), COLORS["warm_white"], True, "lm")
    text(draw, (tx, cy + int(10 * scale)), chips, max(8, int(11 * scale)), COLORS["gold"], True, "lm")


def draw_table_scene(image: Image.Image, box: tuple[int, int, int, int], compact: bool = False) -> None:
    draw = ImageDraw.Draw(image)
    x0, y0, x1, y1 = box
    width, height = x1 - x0, y1 - y0
    draw.rounded_rectangle(box, radius=28, fill=COLORS["background_2"], outline=COLORS["line"], width=2)

    margin_x = int(width * 0.105)
    margin_y = int(height * 0.15)
    rail = (x0 + margin_x, y0 + margin_y, x1 - margin_x, y1 - margin_y)
    draw.ellipse(rail, fill=COLORS["walnut_light"], outline=COLORS["gold_soft"], width=3)
    felt_inset = max(10, int(min(width, height) * 0.026))
    felt = (rail[0] + felt_inset, rail[1] + felt_inset, rail[2] - felt_inset, rail[3] - felt_inset)
    draw.ellipse(felt, fill=COLORS["felt"], outline=COLORS["felt_light"], width=3)
    inner_inset = max(16, int(min(width, height) * 0.05))
    draw.ellipse((felt[0] + inner_inset, felt[1] + inner_inset, felt[2] - inner_inset, felt[3] - inner_inset), outline="#2B8064", width=2)

    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    card_scale = 0.62 if compact else 0.78
    card_w = int(47 * card_scale)
    gap = max(3, int(5 * card_scale))
    ranks = [("A", "♠"), ("10", "♥"), ("7", "♦"), ("3", "♣"), ("K", "♠")]
    start_x = cx - (card_w * 5 + gap * 4) // 2
    card_y = cy - (34 if compact else 45)
    for index, (rank, suit) in enumerate(ranks):
        draw_card(draw, start_x + index * (card_w + gap), card_y, rank, suit, card_scale)
    text(draw, (cx, cy + (27 if compact else 35)), "底池 3,600", 13 if compact else 17, COLORS["warm_white"], True, "mm")
    for index in range(5):
        chip_x = cx - 27 + index * 12
        draw.ellipse((chip_x, cy + (42 if compact else 55), chip_x + 17, cy + (59 if compact else 72)), fill=COLORS["gold"], outline=COLORS["background"], width=2)

    scale = 0.68 if compact else 0.82
    rx, ry = width * 0.39, height * 0.38
    seat_data = [
        (0.06, "SO", "Sora", "19,700"), (0.14, "MK", "Mika", "42,800"),
        (0.38, "JW", "J.W.", "25,400"), (0.46, "AX", "Alex", "91,600"),
        (0.56, "NO", "Noah", "38,900"), (0.64, "LN", "Lena", "67,200"),
        (0.75, "EM", "Emma", "54,100"), (0.88, "LI", "Liam", "72,300"),
    ]
    import math
    for idx, (fraction, initials, name, chips) in enumerate(seat_data):
        angle = math.pi * 2 * fraction
        px = int(cx + math.cos(angle) * rx)
        py = int(cy + math.sin(angle) * ry)
        draw_seat(draw, (px, py), initials, name, chips, acting=idx == 0, scale=scale)
    draw_seat(draw, (cx, int(y1 - height * 0.17)), "RA", "RiverAce", "128,500", local=True, scale=scale)

    if not compact:
        action_y = y1 - 68
        action_w = 104
        labels = [("弃牌", False), ("跟注 800", False), ("加注", True)]
        for idx, (label, selected) in enumerate(labels):
            left = x1 - 344 + idx * 112
            pill(draw, (left, action_y, left + action_w, action_y + 42), label, selected, 15)
        text(draw, (x0 + 28, y0 + 29), "<  松林牌桌 · 100 / 200", 16, COLORS["warm_white"], True, "lm")
        chip_balance(draw, x1 - 185, y0 + 14)


def screen_shell(image: Image.Image, box: tuple[int, int, int, int], title: str, active: str) -> tuple[ImageDraw.ImageDraw, tuple[int, int, int, int]]:
    draw = ImageDraw.Draw(image)
    rounded_panel(draw, box, 22, COLORS["surface"])
    x0, y0, x1, y1 = box
    sidebar_w = int((x1 - x0) * 0.22)
    draw_sidebar(draw, (x0 + 1, y0 + 1, x0 + sidebar_w, y1 - 1), active)
    content = (x0 + sidebar_w + 24, y0 + 24, x1 - 24, y1 - 24)
    text(draw, (content[0], content[1]), title, 28, COLORS["warm_white"], True)
    return draw, content


def draw_screen_card(image: Image.Image, box: tuple[int, int, int, int], title: str, variant: str) -> None:
    draw, content = screen_shell(image, box, title, variant)
    x0, y0, x1, y1 = content
    top = y0 + 52

    if variant == "lobby":
        text(draw, (x0, top), "晚上好，RiverAce", 16, COLORS["secondary"])
        chip_balance(draw, x1 - 122, top - 13)
        labels = ["为你推荐", "常规牌桌", "已收藏", "新手专区"]
        px = x0
        for i, label in enumerate(labels):
            width = 90 if i != 3 else 82
            pill(draw, (px, top + 32, px + width, top + 62), label, i == 0, 12)
            px += width + 8
        rounded_panel(draw, (x0, top + 78, x1, top + 154), 16, COLORS["raised"], COLORS["gold_soft"])
        text(draw, (x0 + 18, top + 94), "为你推荐", 11, COLORS["gold"], True)
        text(draw, (x0 + 18, top + 119), "松林牌桌", 21, COLORS["warm_white"], True)
        pill(draw, (x1 - 104, top + 101, x1 - 18, top + 137), "立即入桌", True, 12)
        for row in range(2):
            yy = top + 170 + row * 47
            rounded_panel(draw, (x0, yy, x1, yy + 39), 12, COLORS["background_2"])
            text(draw, (x0 + 14, yy + 20), "河湾 %s  ·  100 / 200" % (row + 1), 13, COLORS["warm_white"], True, "lm")
            text(draw, (x1 - 15, yy + 20), "加入", 12, COLORS["gold"], True, "rm")
    elif variant == "tables":
        filters = ["全部", "低盲注", "中盲注", "高盲注", "收藏"]
        px = x0
        for i, label in enumerate(filters):
            pill(draw, (px, top, px + 66, top + 31), label, i == 0, 12)
            px += 73
        for row in range(4):
            yy = top + 50 + row * 55
            rounded_panel(draw, (x0, yy, x1, yy + 45), 11, COLORS["background_2"])
            text(draw, (x0 + 14, yy + 14), ["松林牌桌", "河湾牌桌", "灯塔牌桌", "码头牌桌"][row], 13, COLORS["warm_white"], True)
            text(draw, (x0 + 155, yy + 24), ["100 / 200", "200 / 400", "500 / 1,000", "100 / 200"][row], 11, COLORS["secondary"], False, "lm")
            text(draw, (x1 - 14, yy + 23), "加入" if row != 2 else "候补", 12, COLORS["gold"], True, "rm")
    elif variant == "tournaments":
        tabs = ["即将开始", "已报名", "进行中", "已结束"]
        px = x0
        for i, label in enumerate(tabs):
            pill(draw, (px, top, px + 82, top + 31), label, i == 0, 11)
            px += 90
        cards = [("新手免费赛", "河畔新秀杯"), ("经典赛事", "周末经典赛"), ("快速赛事", "闪电挑战")]
        card_w = (x1 - x0 - 20) // 3
        for i, (kind, name) in enumerate(cards):
            left = x0 + i * (card_w + 10)
            rounded_panel(draw, (left, top + 50, left + card_w, top + 222), 14, COLORS["background_2"])
            text(draw, (left + 14, top + 67), kind, 11, COLORS["gold"], True)
            text(draw, (left + 14, top + 94), name, 15, COLORS["warm_white"], True)
            text(draw, (left + 14, top + 127), "报名 72 / 180", 11, COLORS["secondary"])
            text(draw, (left + 14, top + 151), "娱乐筹码奖池", 11, COLORS["secondary"])
            pill(draw, (left + 14, top + 174, left + card_w - 14, top + 208), "免费报名" if i == 0 else "报名", True, 12)
    elif variant == "profile":
        draw.ellipse((x0, top, x0 + 64, top + 64), fill=COLORS["gold"])
        text(draw, (x0 + 32, top + 32), "R", 24, COLORS["background"], True, "mm")
        text(draw, (x0 + 80, top + 8), "RiverAce", 22, COLORS["warm_white"], True)
        text(draw, (x0 + 80, top + 41), "白银会员 · 等级 12", 13, COLORS["secondary"])
        stats = [("12,480", "总手数"), ("24.6%", "入池率"), ("18", "赛事奖励")]
        stat_w = (x1 - x0 - 16) // 3
        for i, (value, label) in enumerate(stats):
            left = x0 + i * (stat_w + 8)
            rounded_panel(draw, (left, top + 82, left + stat_w, top + 145), 12, COLORS["background_2"])
            text(draw, (left + stat_w // 2, top + 102), value, 18, COLORS["gold"], True, "mm")
            text(draw, (left + stat_w // 2, top + 128), label, 11, COLORS["secondary"], False, "mm")
        links = ["牌局记录", "成就徽章", "账户与安全", "声音与震动"]
        for i, label in enumerate(links):
            col, row = i % 2, i // 2
            left = x0 + col * ((x1 - x0) // 2 + 4)
            right = x0 + (col + 1) * ((x1 - x0) // 2) - 4
            yy = top + 162 + row * 44
            rounded_panel(draw, (left, yy, right, yy + 36), 10, COLORS["raised"])
            text(draw, (left + 13, yy + 18), label, 12, COLORS["warm_white"], True, "lm")


def add_header(draw: ImageDraw.ImageDraw, subtitle: str, badge_labels: list[str]) -> None:
    draw.ellipse((72, 56, 126, 110), fill=COLORS["gold"])
    text(draw, (99, 83), "R", 27, COLORS["background"], True, "mm")
    text(draw, (146, 57), "RIVER CLUB", 18, COLORS["gold"], True)
    text(draw, (146, 81), subtitle, 30, COLORS["warm_white"], True)
    right = 1528
    for label in reversed(badge_labels):
        width = 105 if len(label) < 9 else 126
        pill(draw, (right - width, 66, right, 104), label, False, 14)
        right -= width + 10


def render_cover() -> Image.Image:
    image = Image.new("RGB", (1600, 760), COLORS["background"])
    draw = ImageDraw.Draw(image)
    draw.ellipse((1240, -280, 1770, 250), outline=COLORS["gold_soft"], width=2)
    draw.ellipse((1300, -220, 1710, 190), outline=COLORS["line"], width=2)
    add_header(draw, "沉浸式横屏扑克体验", ["Swift 6", "SwiftUI", "iOS 18+"])
    text(draw, (72, 148), "经典赌场气质 · 原生 SwiftUI · 为 iPhone 横屏而设计", 20, COLORS["secondary"])
    draw_table_scene(image, (72, 205, 1035, 674), compact=True)
    cards = [
        ("7 个核心界面", "从登录、选桌到九人牌局"),
        ("九人完整牌桌", "8 位对手 + 1 位本地玩家"),
        ("状态覆盖完整", "加载、空数据、离线与重试"),
        ("可验证的原型", "XCTest 与 XCUITest 覆盖核心流程"),
    ]
    for i, (title_value, detail) in enumerate(cards):
        top = 205 + i * 112
        rounded_panel(draw, (1070, top, 1528, top + 92), 18, COLORS["surface"])
        draw.rectangle((1070, top + 20, 1075, top + 72), fill=COLORS["gold"])
        text(draw, (1095, top + 19), title_value, 20, COLORS["warm_white"], True)
        text(draw, (1095, top + 53), detail, 14, COLORS["secondary"])
    text(draw, (1528, 716), "只为娱乐 · 虚拟筹码无现金价值", 14, COLORS["secondary"], False, "rs")
    return image


def render_table() -> Image.Image:
    image = Image.new("RGB", (1600, 820), COLORS["background"])
    draw = ImageDraw.Draw(image)
    add_header(draw, "九人游戏牌桌", ["9 Seats", "Landscape"])
    draw_table_scene(image, (72, 138, 1528, 760), compact=False)
    return image


def render_screens() -> Image.Image:
    image = Image.new("RGB", (1600, 900), COLORS["background"])
    draw = ImageDraw.Draw(image)
    add_header(draw, "核心页面总览", ["4 Screens", "SwiftUI"])
    text(draw, (72, 128), "固定侧边导航串联大厅、牌桌列表、锦标赛与个人中心。", 18, COLORS["secondary"])
    specs: list[tuple[str, str, tuple[int, int, int, int]]] = [
        ("游戏大厅", "lobby", (72, 180, 782, 500)),
        ("牌桌列表", "tables", (818, 180, 1528, 500)),
        ("锦标赛", "tournaments", (72, 530, 782, 850)),
        ("个人中心", "profile", (818, 530, 1528, 850)),
    ]
    for title_value, variant, box in specs:
        draw_screen_card(image, box, title_value, variant)
    return image


def render_all(output_dir: Path = OUTPUT_DIR) -> list[Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    renderers: dict[str, Callable[[], Image.Image]] = {
        "river-club-cover.png": render_cover,
        "river-club-table.png": render_table,
        "river-club-screens.png": render_screens,
    }
    paths: list[Path] = []
    for name, renderer in renderers.items():
        path = output_dir / name
        renderer().save(path, format="PNG", optimize=True)
        paths.append(path)
    return paths


if __name__ == "__main__":
    for rendered in render_all():
        print(rendered.relative_to(ROOT))
