import PokerBot
import SwiftUI

struct TableSettingsSheet: View {
    @AppStorage(TableSoundPreference.storageKey)
    private var soundEnabled = TableSoundPreference.defaultEnabled
    @State private var experience: TableExperienceSettings
    @State private var difficulty: BotDifficulty
    @State private var model: BotModel
    @State private var thinkingSpeed: BotThinkingSpeed
    @State private var aggression: Int
    @State private var bluffFrequency: Int
    @State private var callingWidth: Int
    @State private var betSizing: Int
    @State private var analyzesHistory: Bool
    @State private var errorMessage: String?

    let onSaveExperience: (TableExperienceSettings) throws -> Void
    let onSaveBotSettings: (BotSettings) throws -> Void
    let onClose: () -> Void

    init(
        experience: TableExperienceSettings,
        botSettings: BotSettings,
        onSaveExperience: @escaping (TableExperienceSettings) throws -> Void,
        onSaveBotSettings: @escaping (BotSettings) throws -> Void,
        onClose: @escaping () -> Void
    ) {
        _experience = State(initialValue: experience)
        _difficulty = State(initialValue: botSettings.difficulty)
        _model = State(initialValue: botSettings.model)
        _thinkingSpeed = State(initialValue: botSettings.thinkingSpeed)
        _aggression = State(initialValue: botSettings.aggression)
        _bluffFrequency = State(initialValue: botSettings.bluffFrequency)
        _callingWidth = State(initialValue: botSettings.callingWidth)
        _betSizing = State(initialValue: botSettings.betSizing)
        _analyzesHistory = State(initialValue: botSettings.analyzesHistory)
        self.onSaveExperience = onSaveExperience
        self.onSaveBotSettings = onSaveBotSettings
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("牌桌设置").font(.title3.bold())
                    Text("机器人规则在下一次行动或下一手牌生效")
                        .font(.caption2)
                        .foregroundStyle(RCTheme.secondaryText)
                }
                Spacer()
                Button("关闭", systemImage: "xmark", action: onClose)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 18) {
                experienceSettings
                Divider().overlay(RCTheme.gold.opacity(0.2))
                robotSettings
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("取消", action: onClose).buttonStyle(.bordered)
                Spacer()
                Button("应用设置", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(RCTheme.gold)
                    .foregroundStyle(Color.black)
            }
        }
        .foregroundStyle(RCTheme.primaryText)
        .padding(18)
        .frame(width: 660, height: 370)
        .background(.black.opacity(0.94), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(RCTheme.gold.opacity(0.52), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table.settingsSheet")
    }

    private var experienceSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("体验")
            Toggle("牌桌声音", isOn: $soundEnabled)
            Toggle("筹码飞行动画", isOn: $experience.chipAnimationEnabled)
            Picker("动画速度", selection: $experience.speed) {
                Text("慢").tag(TableAnimationSpeed.slow)
                Text("标准").tag(TableAnimationSpeed.standard)
                Text("快").tag(TableAnimationSpeed.fast)
            }
            .pickerStyle(.segmented)
            Toggle("显示当前牌型", isOn: $experience.currentHandHintEnabled)
            Toggle("低于门槛自动补充", isOn: $experience.autoTopUpEnabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var robotSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                sectionTitle("机器人规则")
                compactPicker("强度", selection: $difficulty, values: BotDifficulty.allCases) {
                    difficultyText($0)
                }
                compactPicker("模型", selection: $model, values: BotModel.allCases) {
                    modelText($0)
                }
                compactPicker(
                    "思考速度",
                    selection: $thinkingSpeed,
                    values: BotThinkingSpeed.allCases
                ) { thinkingSpeedText($0) }
                valueSlider("进攻性", value: $aggression)
                valueSlider("诈唬频率", value: $bluffFrequency)
                valueSlider("跟注范围", value: $callingWidth)
                valueSlider("下注尺度", value: $betSizing)
                Toggle("分析历史行动", isOn: $analyzesHistory)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.bold())
            .foregroundStyle(RCTheme.gold)
    }

    private func compactPicker<Value: Hashable>(
        _ title: String,
        selection: Binding<Value>,
        values: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        HStack {
            Text(title).font(.caption)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(label(value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func valueSlider(_ title: String, value: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).frame(width: 58, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: 0...100,
                step: 1
            )
            Text("\(value.wrappedValue)")
                .font(.caption2.monospacedDigit())
                .frame(width: 24, alignment: .trailing)
        }
    }

    private func save() {
        do {
            let botSettings = try BotSettings(
                difficulty: difficulty,
                model: model,
                aggression: aggression,
                bluffFrequency: bluffFrequency,
                callingWidth: callingWidth,
                betSizing: betSizing,
                thinkingSpeed: thinkingSpeed,
                analyzesHistory: analyzesHistory
            )
            try onSaveExperience(experience)
            try onSaveBotSettings(botSettings)
            errorMessage = nil
            onClose()
        } catch {
            errorMessage = "设置保存失败，请重试。"
        }
    }

    private func difficultyText(_ value: BotDifficulty) -> String {
        switch value {
        case .easy: "轻松"
        case .standard: "标准"
        case .hard: "高手"
        }
    }

    private func modelText(_ value: BotModel) -> String {
        switch value {
        case .conservative: "保守"
        case .balanced: "均衡"
        case .aggressive: "激进"
        case .adaptive: "自适应"
        }
    }

    private func thinkingSpeedText(_ value: BotThinkingSpeed) -> String {
        switch value {
        case .fast: "快速"
        case .standard: "标准"
        case .natural: "自然"
        }
    }
}
