import Foundation
import Testing
import PokerBot

@Test func 推荐设置符合已确认规格() throws {
    let settings = BotSettings.recommended

    #expect(settings.schemaVersion == 1)
    #expect(settings.difficulty == .standard)
    #expect(settings.model == .balanced)
    #expect(settings.aggression == 50)
    #expect(settings.bluffFrequency == 30)
    #expect(settings.callingWidth == 50)
    #expect(settings.betSizing == 50)
    #expect(settings.thinkingSpeed == .standard)
    #expect(settings.analyzesHistory)
}

@Test func 设置拒绝范围外参数() throws {
    #expect(throws: BotError.invalidSettings) {
        try BotSettings(
            difficulty: .hard,
            model: .adaptive,
            aggression: 101,
            bluffFrequency: 30,
            callingWidth: 50,
            betSizing: 50,
            thinkingSpeed: .natural,
            analyzesHistory: true
        )
    }
}

@Test func 设置解码时重新验证版本和数值() throws {
    let invalidVersion = Data(#"{"schemaVersion":2,"difficulty":"standard","model":"balanced","aggression":50,"bluffFrequency":30,"callingWidth":50,"betSizing":50,"thinkingSpeed":"standard","analyzesHistory":true}"#.utf8)
    let invalidValue = Data(#"{"schemaVersion":1,"difficulty":"standard","model":"balanced","aggression":50,"bluffFrequency":-1,"callingWidth":50,"betSizing":50,"thinkingSpeed":"standard","analyzesHistory":true}"#.utf8)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(BotSettings.self, from: invalidVersion)
    }
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(BotSettings.self, from: invalidValue)
    }
}

@Test func 困难模式模拟次数按思考速度固定() {
    #expect(BotThinkingSpeed.fast.hardSimulationIterations == 800)
    #expect(BotThinkingSpeed.standard.hardSimulationIterations == 2_000)
    #expect(BotThinkingSpeed.natural.hardSimulationIterations == 5_000)
}

@Test func 机器人性格偏移稳定且不超过正负五() {
    let first = BotPersonality.offsets(for: "robot-7", schemaVersion: 1)
    let second = BotPersonality.offsets(for: "robot-7", schemaVersion: 1)

    #expect(first == second)
    #expect(first.values.allSatisfy { (-5...5).contains($0) })
    #expect(BotPersonality.offsets(for: "robot-8", schemaVersion: 1) != first)
}

@Test func 性格偏移应用后仍处于参数范围() {
    let offsets = BotPersonalityOffsets(
        aggression: 5,
        bluffFrequency: -5,
        callingWidth: 5,
        betSizing: -5
    )

    #expect(offsets.applying(to: 98, keyPath: \.aggression) == 100)
    #expect(offsets.applying(to: 2, keyPath: \.bluffFrequency) == 0)
}
