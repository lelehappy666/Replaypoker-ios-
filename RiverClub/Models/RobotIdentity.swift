import Foundation

struct RobotIdentity: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let avatarAssetName: String
    let sourceURL: URL
    let photographer: String
    let accessibilityDescription: String
}

enum RobotIdentityCatalog {
    static let all: [RobotIdentity] = [
        identity("lin-mo", "林墨", "robot-lin-mo", 17824398, "Sandro Tavares", "微笑的成年男性真人头像"),
        identity("qing-yu", "青屿", "robot-qing-yu", 17824399, "Sandro Tavares", "微笑的成年男性真人头像"),
        identity("kong-shan", "空山", "robot-kong-shan", 9618120, "Ron Lach", "戴眼镜的成年男性真人头像"),
        identity("yun-que", "云雀", "robot-yun-que", 11357453, "Mehmet Turgut Kirkgoz", "户外的中年成年男性真人头像"),
        identity("chen-xing", "晨星", "robot-chen-xing", 16645005, "rao qingwei", "室内的成年男性真人头像"),
        identity("hai-yan", "海盐", "robot-hai-yan", 8590404, "Yusron El Jihan", "市集中的中年成年男性真人头像"),
        identity("jiu-wei", "玖未", "robot-jiu-wei", 14378609, "Abhishek Shekhawat", "穿西装的成年男性真人头像"),
        identity("shen-ye", "深野", "robot-shen-ye", 33323692, "Murat IŞIK", "户外微笑的中年成年男性真人头像"),
        identity("mu-chuan", "沐川", "robot-mu-chuan", 24350758, "Tri Warno", "穿红衬衫的中年成年男性真人头像"),
        identity("su-he", "苏禾", "robot-su-he", 33853466, "Ab Pixels", "穿传统服饰的成年男性真人头像"),
        identity("jiang-yu", "江屿", "robot-jiang-yu", 29292086, "Darkshade Photos", "穿传统服饰的成年男性真人头像"),
        identity("ruo-lan", "若岚", "robot-ruo-lan", 34986918, "Filmy Kashif", "戴眼镜的中年成年男性真人头像"),
        identity("an-lan", "安澜", "robot-an-lan", 5264739, "cottonbro studio", "年长成年女性真人头像"),
        identity("chi-ye", "迟野", "robot-chi-ye", 7984817, "AI25.Studio Studio", "微笑的中年成年女性真人头像"),
        identity("xing-yao", "星遥", "robot-xing-yao", 29107543, "Cliff Onsarigo", "穿蓝色服装的中年成年女性真人头像"),
        identity("yan-zhou", "砚舟", "robot-yan-zhou", 36825213, "Giovanna Kamimura", "红发的中年成年女性真人头像"),
        identity("nan-qiao", "南乔", "robot-nan-qiao", 14848133, "Alimurat Üral", "年长成年女性真人头像"),
        identity("jing-xing", "景行", "robot-jing-xing", 31646743, "Adem Erkoç", "微笑的中年成年女性真人头像"),
        identity("qing-he", "清和", "robot-qing-he", 36763514, "Vitaly Gariev", "沉思的中年成年女性真人头像"),
        identity("zhi-xia", "知夏", "robot-zhi-xia", 29405854, "Alimi Sandrine", "微笑的中年成年女性真人头像"),
        identity("gui-wan", "归晚", "robot-gui-wan", 7984908, "AI25.Studio Studio", "戴珍珠饰品的中年成年女性真人头像"),
        identity("yun-chuan", "云川", "robot-yun-chuan", 34896898, "Guillermo Berlin", "长发的成年女性真人头像"),
        identity("zhao-yue", "昭月", "robot-zhao-yue", 11768461, "Mehmet Turgut Kirkgoz", "市集中的中年成年女性真人头像"),
        identity("yuan-shan", "远山", "robot-yuan-shan", 36838816, "Luriko Yamaguchi", "微笑的中年成年女性真人头像"),
    ]

    static func draw<R: RandomNumberGenerator>(
        count: Int,
        using generator: inout R
    ) -> [RobotIdentity] {
        Array(all.shuffled(using: &generator).prefix(clampedCount(count)))
    }

    static func preview<TableIdentifier: Hashable>(
        for tableIdentifier: TableIdentifier,
        count: Int
    ) -> [RobotIdentity] {
        var generator = StableIdentityGenerator(seed: stableSeed(for: String(describing: tableIdentifier)))
        return draw(count: count, using: &generator)
    }

    private static func identity(
        _ id: String,
        _ displayName: String,
        _ avatarAssetName: String,
        _ pexelsPhotoID: Int,
        _ photographer: String,
        _ accessibilityDescription: String
    ) -> RobotIdentity {
        RobotIdentity(
            id: id,
            displayName: displayName,
            avatarAssetName: avatarAssetName,
            sourceURL: URL(string: "https://www.pexels.com/photo/\(pexelsPhotoID)/")!,
            photographer: photographer,
            accessibilityDescription: accessibilityDescription
        )
    }

    private static func clampedCount(_ count: Int) -> Int {
        min(max(count, 0), all.count)
    }

    private static func stableSeed(for value: String) -> UInt64 {
        value.utf8.reduce(0xcbf2_9ce4_8422_2325) { seed, byte in
            (seed ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
    }
}

private struct StableIdentityGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9e37_79b9_7f4a_7c15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
        value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
        return value ^ (value >> 31)
    }
}
