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
    "项目简介",
    "界面展示",
    "核心功能",
    "体验流程",
    "技术实现",
    "项目结构",
    "本地运行",
    "测试",
    "当前范围",
    "后续方向",
    "免责声明",
]


def main() -> None:
    source = README.read_text(encoding="utf-8")

    for heading in REQUIRED_HEADINGS:
        assert re.search(
            rf"^## {re.escape(heading)}$", source, re.MULTILINE
        ), f"缺少章节：{heading}"

    assert "无现金价值" in source, "缺少虚拟筹码无现金价值声明"
    assert all(
        word in source for word in ("充值", "提现", "兑换", "真钱")
    ), "娱乐筹码或真钱边界声明不完整"

    for relative_path, expected_size in EXPECTED_IMAGES.items():
        assert relative_path in source, f"README 未引用图片：{relative_path}"
        image_path = ROOT / relative_path
        assert image_path.is_file(), f"图片不存在：{relative_path}"
        with Image.open(image_path) as image:
            assert image.size == expected_size, (
                f"图片尺寸错误：{relative_path}，"
                f"实际 {image.size}，预期 {expected_size}"
            )
            assert image.mode in {"RGB", "RGBA"}, (
                f"图片色彩模式异常：{relative_path}，实际 {image.mode}"
            )

    print("README 校验通过")


if __name__ == "__main__":
    main()
