//
//  ContentView.swift
//  PigDice
//
//  Created by 林嘉誠 on 2025/11/13.
//

import SwiftUI

struct ContentView: View {
    // 遊戲設定
    private let targetScore = 100
    private let playerNames = ["Player 1", "Player 2"]

    enum GameMode: String, CaseIterable, Identifiable {
        case oneDie = "One Dice"
        case twoDice = "Two Dice"
        var id: String { rawValue }
    }

    enum VersusMode: String, CaseIterable, Identifiable {
        case pvp = "Player 1 vs Player 2"
        case pvc = "Player vs Computer"
        var id: String { rawValue }
    }

    @State private var gameMode: GameMode = .twoDice
    @State private var versusMode: VersusMode = .pvp
    @State private var enablePairsBonus: Bool = false // 只在雙骰模式下適用

    // 遊戲狀態
    @State private var scores: [Int] = [0, 0]       // 總分
    @State private var roundScore: Int = 0          // 本回合累積分
    @State private var currentPlayer: Int = 0       // 目前玩家索引 0 或 1

    // 骰子顯示（先手決定階段用單骰）
    @State private var dieFace1: Int = 1            // 骰子1 1...6
    @State private var dieFace2: Int = 1            // 骰子2 1...6（雙骰模式使用）

    @State private var winnerIndex: Int? = nil      // 勝者索引
    @State private var isDecidingFirstPlayer = true // 是否在決定先手階段
    @State private var firstRolls: [Int?] = [nil, nil] // 先手擲骰結果（單骰）
    @State private var isRolling: Bool = false      // 先手決定用的動畫鎖

    // AI 風險門檻（可依需要調整或之後做成設定）
    private var aiThresholdOneDie: Int { 15 }
    private var aiThresholdTwoDice: Int { 20 }

    var body: some View {
        VStack(spacing: 16) {
            Text(gameMode == .oneDie ? "Pig (單顆骰子)" : "Dice Game Pig")
                .font(.largeTitle.bold())

            // 模式選擇
            VStack(spacing: 8) {
                Picker("骰子模式", selection: $gameMode) {
                    ForEach(GameMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: gameMode) { _, _ in
                    // newGame()
                    triggerAITurnIfNeeded()
                }

                Picker("對戰模式", selection: $versusMode) {
                    ForEach(VersusMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: versusMode) { _, _ in
                    // newGame()
                    triggerAITurnIfNeeded()
                }
            }
            .padding(.horizontal)

            // 分數顯示
            HStack(spacing: 16) {
                playerScoreView(index: 0, name: versusMode == .pvc ? "你" : playerNames[0])
                playerScoreView(index: 1, name: versusMode == .pvc ? "電腦" : playerNames[1])
            }
            .padding(.horizontal)

            // 骰子顯示
            if isDecidingFirstPlayer {
                Image(systemName: "die.face.\(dieFace1)")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("骰子 \(dieFace1) 點")
            } else {
                if gameMode == .oneDie {
                    Image(systemName: "die.face.\(dieFace1)")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .foregroundStyle(.primary)
                        .accessibilityLabel("骰子 \(dieFace1) 點")
                } else {
                    HStack(spacing: 24) {
                        Image(systemName: "die.face.\(dieFace1)")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .foregroundStyle(.primary)
                            .accessibilityLabel("骰子一 \(dieFace1) 點")
                        Image(systemName: "die.face.\(dieFace2)")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .foregroundStyle(.primary)
                            .accessibilityLabel("骰子二 \(dieFace2) 點")
                    }
                }
            }

            // 狀態/提示
            if let winner = winnerIndex {
                Text("\(displayName(for: winner)) 獲勝！")
                    .font(.title2.bold())
                    .foregroundStyle(.green)
            } else if isDecidingFirstPlayer {
                Text("決定先手：每位玩家擲一次骰子，點數高者先")
                    .font(.headline)
                HStack {
                    firstRollResultView(player: 0, name: displayName(for: 0))
                    firstRollResultView(player: 1, name: displayName(for: 1))
                }
            } else {
                Text("目前回合：\(displayName(for: currentPlayer))")
                    .font(.headline)
                Text("本回合累積：\(roundScore)")
                    .font(.title3)
            }

            // 特殊規則切換（只在雙骰模式顯示）
            if gameMode == .twoDice {
                Toggle(isOn: $enablePairsBonus) {
                    Text("擲出一對可獲得一次獎勵再擲")
                }
                .toggleStyle(SwitchToggleStyle())
                .padding(.horizontal)
            }

            // 操作按鈕
            VStack(spacing: 12) {
                if let _ = winnerIndex {
                    Button {
                        newGame()
                    } label: {
                        Label("新遊戲", systemImage: "gobackward")
                    }
                    .buttonStyle(.borderedProminent)
                } else if isDecidingFirstPlayer {
                    Button {
                        decideFirstPlayerRoll()
                    } label: {
                        Label("擲骰決定先手", systemImage: "dice")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRolling)
                } else {
                    HStack(spacing: 16) {
                        Button {
                            if gameMode == .oneDie {
                                playerRollOneDie()
                            } else {
                                playerRollTwoDice()
                            }
                        } label: {
                            Label(gameMode == .oneDie ? "擲骰" : "擲雙骰", systemImage: "dice")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRolling || isAIsturn)

                        Button {
                            playerHold()
                        } label: {
                            Label("停手", systemImage: "hand.raised")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRolling || isAIsturn || roundScore == 0)
                    }
                }

                Button(role: .destructive) {
                    newGame()
                } label: {
                    Label("重置遊戲", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(isRolling)
            }
            .padding(.top, 8)

            Spacer()

            Text("目標分數：\(targetScore)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .animation(.default, value: scores)
        .animation(.default, value: roundScore)
        .animation(.default, value: currentPlayer)
        .animation(.default, value: enablePairsBonus)
        .animation(.default, value: gameMode)
        .animation(.default, value: versusMode)
        .onChange(of: currentPlayer) { _, _ in
            triggerAITurnIfNeeded()
        }
    }

    // MARK: - 計算屬性

    private var isAIsturn: Bool {
        versusMode == .pvc && currentPlayer == 1 && !isDecidingFirstPlayer && winnerIndex == nil
    }

    private func displayName(for index: Int) -> String {
        if versusMode == .pvc {
            return index == 0 ? "你" : "電腦"
        } else {
            return playerNames[index]
        }
    }

    // MARK: - 子視圖

    @ViewBuilder
    private func playerScoreView(index: Int, name: String) -> some View {
        let isCurrent = (index == currentPlayer) && !isDecidingFirstPlayer && winnerIndex == nil
        VStack(spacing: 8) {
            Text(name)
                .font(.headline)
            Text("\(scores[index])")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(isCurrent ? .blue : .primary)
            if isDecidingFirstPlayer {
                if let roll = firstRolls[index] {
                    Text("先手擲：\(roll)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("等待擲骰")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if isCurrent {
                Text("你的回合")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
        )
    }

    @ViewBuilder
    private func firstRollResultView(player index: Int, name: String) -> some View {
        VStack {
            Text(name)
            Text(firstRolls[index].map { "\($0)" } ?? "-")
                .font(.title)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 遊戲邏輯（玩家按鈕操作）

    private func newGame() {
        scores = [0, 0]
        roundScore = 0
        currentPlayer = 0
        dieFace1 = 1
        dieFace2 = 1
        winnerIndex = nil
        isDecidingFirstPlayer = true
        firstRolls = [nil, nil]
        isRolling = false
    }

    private func decideFirstPlayerRoll() {
        guard isDecidingFirstPlayer, !isRolling else { return }
        isRolling = true
        rollDieAnimationSingle { roll in
            if firstRolls[0] == nil {
                firstRolls[0] = roll
            } else if firstRolls[1] == nil {
                firstRolls[1] = roll
            }

            if let a = firstRolls[0], let b = firstRolls[1] {
                if a == b {
                    firstRolls = [nil, nil]
                } else {
                    currentPlayer = (a > b) ? 0 : 1
                    isDecidingFirstPlayer = false
                }
            }
            isRolling = false
            triggerAITurnIfNeeded()
        }
    }

    private func playerRollOneDie() {
        rollOneDieCore()
        triggerAITurnIfNeeded()
    }

    private func playerRollTwoDice() {
        rollTwoDiceCore()
        triggerAITurnIfNeeded()
    }

    private func playerHold() {
        holdCore()
        triggerAITurnIfNeeded()
    }

    // MARK: - 核心擲骰/停手（同步，玩家與 AI 共用）

    private func rollOneDieCore() {
        guard winnerIndex == nil, !isDecidingFirstPlayer else { return }
        let roll = Int.random(in: 1...6)
        dieFace1 = roll

        if roll == 1 {
            roundScore = 0
            switchPlayer()
        } else {
            roundScore += roll
        }
    }

    private func rollTwoDiceCore() {
        guard winnerIndex == nil, !isDecidingFirstPlayer else { return }
        let r1 = Int.random(in: 1...6)
        let r2 = Int.random(in: 1...6)
        dieFace1 = r1
        dieFace2 = r2

        if r1 == 1 && r2 == 1 {
            scores[currentPlayer] = 0
            roundScore = 0
            switchPlayer()
        } else if r1 == 1 || r2 == 1 {
            roundScore = 0
            switchPlayer()
        } else {
            roundScore += (r1 + r2)
            // 一對獎勵：不強制自動再擲，僅影響 AI 的門檻調整
        }
    }

    private func holdCore() {
        guard winnerIndex == nil, !isDecidingFirstPlayer else { return }
        scores[currentPlayer] += roundScore
        roundScore = 0

        if scores[currentPlayer] >= targetScore {
            winnerIndex = currentPlayer
        } else {
            switchPlayer()
        }
    }

    private func switchPlayer() {
        currentPlayer = (currentPlayer + 1) % 2
    }

    // MARK: - AI 控制（同步立即行動）

    private func triggerAITurnIfNeeded() {
        guard isAIsturn, winnerIndex == nil else { return }

        // 連續執行 AI 的回合：直到因規則結束或 AI 決定 Hold 或有人勝利
        while isAIsturn, winnerIndex == nil {
            let thresholdBase = (gameMode == .oneDie) ? aiThresholdOneDie : aiThresholdTwoDice
            let adjustedThreshold = (gameMode == .twoDice && enablePairsBonus) ? (thresholdBase + 4) : thresholdBase
            let canWinIfHold = scores[currentPlayer] + roundScore >= targetScore

            let shouldHold = canWinIfHold || roundScore >= adjustedThreshold

            if shouldHold {
                holdCore()
            } else {
                if gameMode == .oneDie {
                    rollOneDieCore()
                } else {
                    rollTwoDiceCore()
                }
            }
            // 如果 roll 出 1/雙1，會在 core 中自動換人，while 條件會停止
        }
    }

    // MARK: - 骰子動畫（只用於先手決定）

    private func rollDieAnimationSingle(completion: @escaping (Int) -> Void) {
        let ticks = 10
        let interval = 0.05

        var currentTick = 0
        func tick() {
            currentTick += 1
            dieFace1 = Int.random(in: 1...6)
            if currentTick < ticks {
                DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                    tick()
                }
            } else {
                completion(dieFace1)
            }
        }
        tick()
    }
}

#Preview {
    ContentView()
}
