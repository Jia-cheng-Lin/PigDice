//
//  ContentView.swift
//  PigDice
//
//  Created by 林嘉誠 on 2025/11/13.
//

import SwiftUI

struct ContentView: View {
    // 遊戲設定（Target Score 可調整與持久化）
    @AppStorage("targetScore") private var targetScore: Double = 100

    // 玩家數量（2...4）
    @AppStorage("playerCount") private var playerCount: Int = 2

    // 玩家名稱（JSON 持久化）
    @AppStorage("playerNamesJSON") private var playerNamesJSON: String = ""
    // 戰績（JSON 持久化）
    @AppStorage("winsJSON") private var winsJSON: String = ""
    @AppStorage("lossesJSON") private var lossesJSON: String = ""

    enum GameMode: String, CaseIterable, Identifiable {
        case oneDice = "One Dice"
        case twoDice = "Two Dice"
        var id: String { rawValue }
    }

    enum VersusMode: String, CaseIterable, Identifiable {
        case pvp = "VS Player"
        case pvc = "VS Computer"
        var id: String { rawValue }
    }

    @State private var gameMode: GameMode = .twoDice
    @State private var versusMode: VersusMode = .pvp

    // 遊戲狀態
    @State private var scores: [Int] = [0, 0]       // 總分（動態長度）
    @State private var roundScore: Int = 0          // 本回合累積分
    @State private var currentPlayer: Int = 0       // 目前玩家索引

    // 骰子顯示（先手決定階段用單骰；遊戲階段依模式）
    @State private var dieFace1: Int = 1            // 骰子1 1...6
    @State private var dieFace2: Int = 1            // 骰子2 1...6（雙骰模式使用）

    @State private var winnerIndex: Int? = nil      // 勝者索引
    @State private var isDecidingFirstPlayer = true // 是否在決定先手階段
    @State private var firstRolls: [Int?] = [nil, nil] // 先手擲骰結果（動態）
    @State private var isRolling: Bool = false      // 動畫鎖（先手與遊戲擲骰）

    // 先手決定「不重複點數」的可用池
    @State private var availableFirstRolls: Set<Int> = Set(1...6)
    @State private var nextFirstRollIndex: Int = 0

    // 新規則：雙骰出現相同且非 1 時，強制必須繼續擲（不能 Hold）
    @State private var forcedToRoll: Bool = false

    // AI 風險門檻
    private var aiThresholdOneDie: Int { 15 }
    private var aiThresholdTwoDice: Int { 20 }

    // 可調參數：電腦反應時間與擲骰動畫時間
    @State private var aiReactionDelay: Double = 2.2      // 秒
    @State private var playerRollDuration: Double = 0.6   // 秒
    @State private var aiRollDuration: Double = 0.35      // 秒

    // 舊的兩人戰績（不再使用，但保留兼容，不顯示）
    @AppStorage("winsP0") private var winsP0: Int = 0
    @AppStorage("winsP1") private var winsP1: Int = 0
    @AppStorage("lossesP0") private var lossesP0: Int = 0
    @AppStorage("lossesP1") private var lossesP1: Int = 0

    // 背景透明度（持久化）
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.25

    // 設定頁面顯示
    @State private var showingSettings: Bool = false

    // 先手提示 Alert
    @State private var pendingFirstPlayer: Int? = nil
    @State private var showFirstPlayerAlert: Bool = false

    // 規則顯示（自訂 Overlay）
    @State private var showRulesOverlay: Bool = false
    @State private var rulesModeForAlert: GameMode = .oneDice
    // 規則背景遮罩透明度（越高越暗，建議 0.35~0.6）
    @State private var rulesBackdropOpacity: Double = 0.45

    // TextField 輸入（Target Score 的文字綁定）
    @State private var targetInputText: String = "100"

    // 內部玩家名稱與戰績陣列（對應 JSON）
    @State private var playerNames: [String] = ["Player 1", "Player 2", "Player 3", "Computer"]
    @State private var wins: [Int] = [0, 0, 0, 0]
    @State private var losses: [Int] = [0, 0, 0, 0]

    // Inline name input for Player 1（將移除用不到，但先保留變數避免編譯錯誤）
    @State private var player1InlineName: String = ""

    var body: some View {
        GeometryReader { proxy in
            let contentMaxWidth = min(proxy.size.width, 700)
            let horizontalPadding: CGFloat = 16

            ZStack(alignment: .top) {
                // 背景圖片鋪滿（放大 1.2 倍）
                Image("background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height+100)
                    .clipped()
                    .opacity(backgroundOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .layoutPriority(-1)

                // 可捲動的主要內容
                ScrollView {
                    VStack(spacing: 16) {
                        Text(gameMode == .oneDice ? "Dice Game Pig" : "Two Dice Pig")
                            .font(.largeTitle.bold())

                        // 模式選擇 + 玩家數量
                        VStack(spacing: 8) {
                            Picker("骰子模式", selection: $gameMode) {
                                ForEach(GameMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: gameMode) { _, _ in
                                triggerAITurnIfNeeded()
                            }

                            Picker("對戰模式", selection: $versusMode) {
                                ForEach(VersusMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: versusMode) { _, _ in
                                triggerAITurnIfNeeded()
                            }

                            // 玩家數量（2...4）
                            HStack {
                                Text("Players")
                                Spacer()
                                Picker("Players", selection: Binding(
                                    get: { playerCount },
                                    set: { newValue in
                                        playerCount = min(max(newValue, 2), 4)
                                        normalizeArraysForPlayerCount()
                                        newGame()
                                    }
                                )) {
                                    ForEach(2...4, id: \.self) { count in
                                        Text("\(count)").tag(count)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 240)
                            }

                            // Target Score 區塊
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    Text("Target Score")
                                        .font(.title2.weight(.semibold))

                                    Spacer()

                                    Text("\(Int(targetScore))")
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundStyle(.black)
                                        .accessibilityLabel("目前目標分數 \(Int(targetScore))")
                                }

                                HStack(spacing: 8) {
                                    TextField("Reset target", text: $targetInputText)
                                        .textFieldStyle(.roundedBorder)
                                        .keyboardType(.numberPad)
                                        .frame(width: 180)
                                        .onChange(of: targetInputText) { _, newValue in
                                            let filtered = newValue.filter { $0.isNumber }
                                            if filtered != newValue {
                                                targetInputText = filtered
                                            }
                                        }

                                    Button("Enter") {
                                        applyTargetInput()
                                    }
                                    .font(.headline)
                                    .buttonStyle(.borderedProminent)

                                    Button("Reset") {
                                        targetScore = 100
                                        targetInputText = "100"
                                    }
                                    .font(.headline)
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.horizontal)

                        // 分數顯示 + 戰績（動態，2 欄網格）
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                            ForEach(0..<playerCount, id: \.self) { idx in
                                playerScoreView(index: idx, name: displayName(for: idx))
                            }
                        }
                        .padding(.horizontal)

                        // 骰子顯示與先手決定
                        Group {
                            if isDecidingFirstPlayer {
                                Image(systemName: "die.face.\(dieFace1)")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120, height: 120)
                                    .foregroundStyle(.primary)
                                    .accessibilityLabel("骰子 \(dieFace1) 點")
                                    .modifier(ShakeEffect(animating: isRolling))
                                // 顯示每位玩家的先手點數
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    ForEach(0..<playerCount, id: \.self) { idx in
                                        firstRollResultView(player: idx, name: displayName(for: idx))
                                    }
                                }
                                .padding(.horizontal)
                                Text("Rolling a dice to decide the order of play")
                                    .font(.headline)

                                // 新增：先手決定階段的玩家名稱輸入
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Player Names")
                                        .font(.headline)
                                    ForEach(0..<playerCount, id: \.self) { idx in
                                        HStack(spacing: 8) {
                                            Text("Player \(idx + 1)")
                                                .frame(width: 84, alignment: .leading)
                                                .foregroundStyle(.secondary)
                                            if versusMode == .pvc && idx == playerCount - 1 {
                                                // 電腦：顯示不可編輯
                                                Text("電腦")
                                                    .foregroundStyle(.secondary)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(10)
                                                    .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                                                    .accessibilityLabel("電腦")
                                            } else {
                                                TextField("Name (English letters)", text: Binding(
                                                    get: {
                                                        if playerNames.indices.contains(idx) {
                                                            return playerNames[idx]
                                                        } else {
                                                            return "Player \(idx + 1)"
                                                        }
                                                    },
                                                    set: { newValue in
                                                        // 只允許英文字母與空白，最大長度 16
                                                        let filtered = newValue.filter { $0.isLetter || $0 == " " }
                                                        let trimmed = String(filtered.prefix(16))
                                                        if idx >= playerNames.count {
                                                            let need = idx - playerNames.count + 1
                                                            playerNames.append(contentsOf: (0..<need).map { _ in "" })
                                                        }
                                                        playerNames[idx] = trimmed
                                                        savePersistentArrays()
                                                    }
                                                ))
                                                .textInputAutocapitalization(.words)
                                                .disableAutocorrection(true)
                                                .textFieldStyle(.roundedBorder)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)

                                Button {
                                    decideFirstPlayerRoll()
                                } label: {
                                    Label("Rolling for order", systemImage: "dice")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isRolling || nextFirstRollIndex >= playerCount)
                            } else {
                                if gameMode == .oneDice {
                                    Image(systemName: "die.face.\(dieFace1)")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 120, height: 120)
                                        .foregroundStyle(.primary)
                                        .accessibilityLabel("骰子 \(dieFace1) 點")
                                        .modifier(ShakeEffect(animating: isRolling))
                                } else {
                                    HStack(spacing: 24) {
                                        Image(systemName: "die.face.\(dieFace1)")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 100, height: 100)
                                            .foregroundStyle(.primary)
                                            .accessibilityLabel("骰子一 \(dieFace1) 點")
                                            .modifier(ShakeEffect(animating: isRolling))
                                        Image(systemName: "die.face.\(dieFace2)")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 100, height: 100)
                                            .foregroundStyle(.primary)
                                            .accessibilityLabel("骰子二 \(dieFace2) 點")
                                            .modifier(ShakeEffect(animating: isRolling))
                                    }
                                }
                                // 狀態/提示（非先手決定階段）
                                Text("Current round for：\(displayName(for: currentPlayer))")
                                    .font(.headline)
                                Text("Accumulated score：\(roundScore)")
                                    .font(.title3)
                                if gameMode == .twoDice && forcedToRoll {
                                    Text("擲出非1的相同點數，必須繼續擲骰。")
                                        .font(.title2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }

                        // 勝利提示
                        if let winner = winnerIndex {
                            Text("\(displayName(for: winner)) 獲勝！")
                                .font(.title2.bold())
                                .foregroundStyle(.green)
                        }

                        // 操作按鈕
                        VStack(spacing: 12) {
                            if let _ = winnerIndex {
                                Button {
                                    newGame()
                                } label: {
                                    Label("Replay", systemImage: "gobackward")
                                }
                                .buttonStyle(.borderedProminent)
                            } else if !isDecidingFirstPlayer {
                                HStack(spacing: 16) {
                                    Button {
                                        if gameMode == .oneDice {
                                            playerRollOneDie()
                                        } else {
                                            playerRollTwoDice()
                                        }
                                    } label: {
                                        Label(gameMode == .oneDice ? "One Dice" : "Two Dice", systemImage: "dice")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isRolling || isAIsturn)

                                    Button {
                                        playerHold()
                                    } label: {
                                        Label("Hold", systemImage: "hand.raised")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isRolling || isAIsturn || roundScore == 0 || (gameMode == .twoDice && forcedToRoll))
                                }
                            }

                            HStack(spacing: 12) {
                                Button(role: .destructive) {
                                    newGame()
                                } label: {
                                    Label("Restart", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isRolling)

                                Button {
                                    showingSettings = true
                                } label: {
                                    Label("Setting", systemImage: "slider.horizontal.3")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isRolling)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: contentMaxWidth)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 16)
                    .animation(.default, value: scores)
                    .animation(.default, value: roundScore)
                    .animation(.default, value: currentPlayer)
                    .animation(.default, value: forcedToRoll)
                    .animation(.default, value: gameMode)
                    .animation(.default, value: versusMode)
                    .onChange(of: currentPlayer) { _, _ in
                        triggerAITurnIfNeeded()
                    }
                }
                .ignoresSafeArea(edges: .bottom)

                // 右上角規則按鈕（位於背景之上、主要內容之上）
                Button {
                    rulesModeForAlert = gameMode
                    withAnimation(.spring) {
                        showRulesOverlay = true
                    }
                } label: {
                    Label("Rule", systemImage: "questionmark.circle.fill")
                }
                .accessibilityLabel("規則說明")
                .padding(.trailing, 16)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .zIndex(50)

                // 規則 Overlay（最高層，覆蓋全畫面；背景仍可見）
                if showRulesOverlay {
                    rulesOverlayView
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(100)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .onAppear {
            // 初始化資料
            loadPersistentArrays()
            normalizeArraysForPlayerCount()
            targetInputText = String(Int(targetScore))
            // 初始化 Player 1 inline name 顯示（已不再使用）
            if playerNames.indices.contains(0) {
                player1InlineName = playerNames[0]
            } else {
                player1InlineName = "Player 1"
            }
            if isDecidingFirstPlayer {
                resetFirstRollPhase()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                playerCount: $playerCount,
                playerNames: $playerNames,
                wins: $wins,
                losses: $losses,
                aiReactionDelay: $aiReactionDelay,
                playerRollDuration: $playerRollDuration,
                aiRollDuration: $aiRollDuration,
                backgroundOpacity: $backgroundOpacity,
                targetScore: $targetScore,
                versusMode: $versusMode,
                onResetRecords: resetRecords,
                onApply: {
                    savePersistentArrays()
                    normalizeArraysForPlayerCount()
                },
                onClose: { showingSettings = false }
            )
        }
        // 先手提示 Alert
        .alert(isPresented: $showFirstPlayerAlert) {
            let name = pendingFirstPlayer.map { displayName(for: $0) } ?? ""
            return Alert(
                title: Text("先手玩家"),
                message: Text("\(name) 先開始"),
                dismissButton: .default(Text("OK")) {
                    if let first = pendingFirstPlayer {
                        currentPlayer = first
                        isDecidingFirstPlayer = false
                        pendingFirstPlayer = nil
                        triggerAITurnIfNeeded()
                    }
                }
            )
        }
    }

    // MARK: - 規則 Overlay View

    private var rulesOverlayView: some View {
        ZStack {
            // 可調暗背景
            Color.black.opacity(rulesBackdropOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring) {
                        showRulesOverlay = false
                    }
                }

            // 中央卡片
            VStack(spacing: 0) {
                Text(rulesTitle(for: rulesModeForAlert))
                    .font(.title2.bold())
                    .padding(.top, 16)
                    .padding(.horizontal, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(rulesMessage(for: rulesModeForAlert))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: 360)

                Divider()

                HStack(spacing: 12) {
                    Button(rulesSwitchButtonTitle(for: rulesModeForAlert)) {
                        withAnimation(.easeInOut) {
                            rulesModeForAlert = (rulesModeForAlert == .oneDice) ? .twoDice : .oneDice
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(role: .cancel) {
                        withAnimation(.spring) {
                            showRulesOverlay = false
                        }
                    } label: {
                        Text("關閉")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
            }
            .frame(maxWidth: 520)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thinMaterial)
                    .shadow(radius: 18, y: 8)
            )
            .padding(.horizontal, 24)
        }
        .accessibilityAddTraits(.isModal)
    }

    // MARK: - 計算屬性

    private var isAIsturn: Bool {
        // PvC 時最後一位為電腦
        versusMode == .pvc && currentPlayer == playerCount - 1 && !isDecidingFirstPlayer && winnerIndex == nil
    }

    private func displayName(for index: Int) -> String {
        // PvC: 最後一位為電腦
        if versusMode == .pvc && index == playerCount - 1 {
            return "電腦"
        }
        // 取得使用者輸入的名稱（若有），否則回退到 Player N
        let candidate: String
        if index < playerNames.count {
            let trimmed = playerNames[index].trimmingCharacters(in: .whitespacesAndNewlines)
            candidate = trimmed.isEmpty ? "Player \(index + 1)" : trimmed
        } else {
            candidate = "Player \(index + 1)"
        }
        // PvP：永遠不顯示「電腦/Computer」，若名字剛好是這些字樣，改為預設 Player N
        let lowered = candidate.lowercased()
        if versusMode == .pvp && (lowered == "computer" || lowered == "電腦") {
            return "Player \(index + 1)"
        }
        return candidate
    }

    // MARK: - 規則字串

    private func rulesTitle(for mode: GameMode) -> String {
        switch mode {
        case .oneDice: return "單顆骰子規則"
        case .twoDice: return "兩顆骰子規則"
        }
    }

    private func rulesSwitchButtonTitle(for mode: GameMode) -> String {
        switch mode {
        case .oneDice: return "查看兩顆骰子規則"
        case .twoDice: return "查看單顆骰子規則"
        }
    }

    private func rulesMessage(for mode: GameMode) -> String {
        switch mode {
        case .oneDice:
            return """
            - 每回合擲一顆骰子。
            - 擲到 1：本回合分數歸零並換人。
            - 擲到 2~6：點數累加到本回合分數，可選擇繼續擲或 Hold。
            - 達到目標分數（\(Int(targetScore))）即獲勝。若擲完即達標，無需按 Hold。
            """
        case .twoDice:
            return """
            - 每回合擲兩顆骰子。
            - 其中一顆為 1：本回合分數歸零並換人。
            - 兩顆都是 1：本回合分數歸零，且你的總分歸零，然後換人。
            - 兩顆相同但不是 1：點數累加，同時你必須繼續擲，不能 Hold。
            - 其他情況：兩顆點數相加累加到本回合分數，可選擇繼續擲或 Hold。
            - 達到目標分數（\(Int(targetScore))）即獲勝。若擲完即達標，無需按 Hold。
            """
        }
    }

    // MARK: - 子視圖

    @ViewBuilder
    private func playerScoreView(index: Int, name: String) -> some View {
        let isCurrent = (index == currentPlayer) && !isDecidingFirstPlayer && winnerIndex == nil

        @State var pulse: Bool = false

        let borderColor = isCurrent ? Color.red : Color.clear
        let baseOpacity: Double = isCurrent ? 1.0 : 0.0
        let animatedOpacity: Double = (isCurrent && isRolling) ? (pulse ? 1.0 : 0.25) : baseOpacity

        VStack(spacing: 8) {
            Text(name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // 已移除：卡片內的 Player 1 名稱輸入欄位

            Text("\(scores[safe: index] ?? 0)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            if isDecidingFirstPlayer {
                if let roll = firstRolls[safe: index] ?? nil {
                    Text("First：\(roll)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Waiting")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if isCurrent {
                Label {
                    Text("Your turn")
                        .font(.caption.weight(.semibold))
                } icon: {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.red.opacity(0.9))
                )
                .foregroundStyle(Color.white)
                .accessibilityLabel("Your turn")
            }

            // 簡易顯示個人戰績
            Text("W-L：\(wins[safe: index] ?? 0) - \(losses[safe: index] ?? 0)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor.opacity(animatedOpacity), lineWidth: 3)
        )
        .shadow(color: isCurrent ? .red.opacity(animatedOpacity * 0.7) : .clear, radius: isCurrent ? 8 : 0)
        .onChange(of: isRolling) { _, newValue in
            if newValue && isCurrent {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                pulse = false
            }
        }
        .onChange(of: currentPlayer) { _, _ in
            pulse = false
        }
        .onAppear {
            if index == 0 {
                // 同步初始名稱（即便不再顯示輸入欄位）
                if playerNames.indices.contains(0) {
                    player1InlineName = playerNames[0]
                } else {
                    player1InlineName = "Player 1"
                }
            }
            if isRolling && isCurrent {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }

    @ViewBuilder
    private func firstRollResultView(player index: Int, name: String) -> some View {
        VStack {
            Text(name).lineLimit(1).minimumScaleFactor(0.7)
            Text(firstRolls[safe: index].map { "\($0)" } ?? "--")
                .font(.title2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 遊戲邏輯（玩家操作入口）

    private func newGame() {
        scores = Array(repeating: 0, count: playerCount)
        roundScore = 0
        currentPlayer = 0
        dieFace1 = 1
        dieFace2 = 1
        winnerIndex = nil
        isDecidingFirstPlayer = true
        firstRolls = Array(repeating: nil, count: playerCount)
        isRolling = false
        forcedToRoll = false
        pendingFirstPlayer = nil
        showFirstPlayerAlert = false
        showRulesOverlay = false
        resetFirstRollPhase()
    }

    private func resetFirstRollPhase() {
        availableFirstRolls = Set(1...6)
        nextFirstRollIndex = 0
    }

    // 先手決定（不重複點數）
    private func decideFirstPlayerRoll() {
        guard isDecidingFirstPlayer, !isRolling else { return }
        guard nextFirstRollIndex < playerCount else { return }
        guard !availableFirstRolls.isEmpty else {
            finalizeFirstPlayer()
            return
        }

        isRolling = true
        rollDieAnimationSingle { _ in
            // 從可用點數隨機取一個
            if let roll = availableFirstRolls.randomElement() {
                availableFirstRolls.remove(roll)
                firstRolls[nextFirstRollIndex] = roll
                dieFace1 = roll
                nextFirstRollIndex += 1
            }
            isRolling = false

            if nextFirstRollIndex >= playerCount {
                finalizeFirstPlayer()
            }
        }
    }

    private func finalizeFirstPlayer() {
        let pairs = firstRolls.enumerated().compactMap { (idx, val) -> (Int, Int)? in
            guard let v = val else { return nil }
            return (idx, v)
        }
        guard let maxPair = pairs.max(by: { $0.1 < $1.1 }) else { return }
        pendingFirstPlayer = maxPair.0
        showFirstPlayerAlert = true
    }

    private func playerRollOneDie() {
        guard !isRolling else { return }
        isRolling = true
        animateSingleRoll(duration: playerRollDuration, ticks: 10) {
            rollOneDieCore()
            isRolling = false
            triggerAITurnIfNeeded()
        }
    }

    private func playerRollTwoDice() {
        guard !isRolling else { return }
        isRolling = true
        animateDoubleRoll(duration: playerRollDuration, ticks: 10) {
            rollTwoDiceCore()
            isRolling = false
            triggerAITurnIfNeeded()
        }
    }

    private func playerHold() {
        if gameMode == .twoDice && forcedToRoll { return }
        holdCore()
        triggerAITurnIfNeeded()
    }

    // MARK: - 核心擲骰/停手（同步，玩家與 AI 共用）

    private func rollOneDieCore() {
        guard winnerIndex == nil, !isDecidingFirstPlayer else { return }
        let roll = Int.random(in: 1...6)
        dieFace1 = roll
        forcedToRoll = false

        if roll == 1 {
            roundScore = 0
            switchPlayer()
        } else {
            roundScore += roll
            if scores[currentPlayer] + roundScore >= Int(targetScore) {
                scores[currentPlayer] += roundScore
                roundScore = 0
                setWinnerIfNeeded(currentPlayer)
            }
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
            forcedToRoll = false
            switchPlayer()
        } else if r1 == 1 || r2 == 1 {
            roundScore = 0
            forcedToRoll = false
            switchPlayer()
        } else {
            roundScore += (r1 + r2)
            forcedToRoll = (r1 == r2)

            if scores[currentPlayer] + roundScore >= Int(targetScore) {
                scores[currentPlayer] += roundScore
                roundScore = 0
                setWinnerIfNeeded(currentPlayer)
                forcedToRoll = false
            }
        }
    }

    private func holdCore() {
        guard winnerIndex == nil, !isDecidingFirstPlayer else { return }
        scores[currentPlayer] += roundScore
        roundScore = 0
        forcedToRoll = false

        if scores[currentPlayer] >= Int(targetScore) {
            setWinnerIfNeeded(currentPlayer)
        } else {
            switchPlayer()
        }
    }

    private func switchPlayer() {
        currentPlayer = (currentPlayer + 1) % playerCount
        forcedToRoll = false
    }

    // 確認勝利並記錄戰績
    private func setWinnerIfNeeded(_ winner: Int) {
        guard winnerIndex == nil else { return }
        winnerIndex = winner

        // 勝者 +1，其餘玩家 losses +1
        if winner < wins.count { wins[winner] += 1 }
        for idx in 0..<playerCount where idx != winner {
            if idx < losses.count { losses[idx] += 1 }
        }
        savePersistentArrays()
    }

    private func resetRecords() {
        for i in wins.indices { wins[i] = 0 }
        for i in losses.indices { losses[i] = 0 }
        savePersistentArrays()
    }

    // MARK: - AI 控制

    private func triggerAITurnIfNeeded() {
        guard isAIsturn, winnerIndex == nil, !isRolling else { return }

        // 起手延遲 1.2 秒
        let initialDelay: Double = 1.2

        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) {
            guard self.isAIsturn, self.winnerIndex == nil, !self.isRolling else { return }

            func aiStep() {
                guard self.isAIsturn, self.winnerIndex == nil else { return }

                let thresholdBase = (self.gameMode == .oneDice) ? self.aiThresholdOneDie : self.aiThresholdTwoDice
                let canWinIfHold = self.scores[self.currentPlayer] + self.roundScore >= Int(self.targetScore)
                let forced = (self.gameMode == .twoDice && self.forcedToRoll)
                let shouldHold = !forced && (canWinIfHold || self.roundScore >= thresholdBase)

                if shouldHold {
                    self.holdCore()
                    return
                } else {
                    if self.gameMode == .oneDice {
                        self.isRolling = true
                        self.animateSingleRoll(duration: self.aiRollDuration, ticks: 6) {
                            self.rollOneDieCore()
                            self.isRolling = false
                            if self.isAIsturn, self.winnerIndex == nil {
                                DispatchQueue.main.asyncAfter(deadline: .now() + self.aiReactionDelay) {
                                    aiStep()
                                }
                            }
                        }
                    } else {
                        self.isRolling = true
                        self.animateDoubleRoll(duration: self.aiRollDuration, ticks: 6) {
                            self.rollTwoDiceCore()
                            self.isRolling = false
                            if self.isAIsturn, self.winnerIndex == nil {
                                DispatchQueue.main.asyncAfter(deadline: .now() + self.aiReactionDelay) {
                                    aiStep()
                                }
                            }
                        }
                    }
                }
            }

            aiStep()
        }
    }

    // MARK: - 動畫

    private func animateSingleRoll(duration: Double, ticks: Int, completion: @escaping () -> Void) {
        guard ticks > 0 else { completion(); return }
        let interval = duration / Double(ticks)
        var currentTick = 0

        func tick() {
            currentTick += 1
            dieFace1 = Int.random(in: 1...6)
            if currentTick < ticks {
                DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                    tick()
                }
            } else {
                completion()
            }
        }
        tick()
    }

    private func animateDoubleRoll(duration: Double, ticks: Int, completion: @escaping () -> Void) {
        guard ticks > 0 else { completion(); return }
        let interval = duration / Double(ticks)
        var currentTick = 0

        func tick() {
            currentTick += 1
            dieFace1 = Int.random(in: 1...6)
            dieFace2 = Int.random(in: 1...6)
            if currentTick < ticks {
                DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                    tick()
                }
            } else {
                completion()
            }
        }
        tick()
    }

    // MARK: - 先手決定的動畫

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

    // MARK: - Target Score 輸入套用

    private func applyTargetInput() {
        guard !targetInputText.isEmpty else { return }
        if let value = Int(targetInputText) {
            let clamped = min(max(value, 10), 300)
            targetScore = Double(clamped)
            targetInputText = String(clamped)
        } else {
            targetInputText = String(Int(targetScore))
        }
    }

    // MARK: - 持久化（JSON 陣列）

    private func loadPersistentArrays() {
        // 預設名稱
        if playerNamesJSON.isEmpty {
            playerNames = ["Player 1", "Player 2", "Player 3", "Computer"]
        } else {
            playerNames = decodeArray(from: playerNamesJSON) ?? ["Player 1", "Player 2", "Player 3", "Computer"]
        }
        // 預設戰績
        wins = decodeArray(from: winsJSON) ?? Array(repeating: 0, count: max(playerCount, 4))
        losses = decodeArray(from: lossesJSON) ?? Array(repeating: 0, count: max(playerCount, 4))
        // 長度對齊至少 4（保留資料），後續再按 playerCount 顯示/使用
        ensureLength(&playerNames, target: max(playerCount, 4), filler: "Player")
        ensureLength(&wins, target: max(playerCount, 4), filler: 0)
        ensureLength(&losses, target: max(playerCount, 4), filler: 0)
    }

    private func savePersistentArrays() {
        playerNamesJSON = encodeArray(playerNames) ?? playerNamesJSON
        winsJSON = encodeArray(wins) ?? winsJSON
        lossesJSON = encodeArray(losses) ?? lossesJSON
    }

    private func normalizeArraysForPlayerCount() {
        // 確保本地 scores/firstRolls 依 playerCount
        scores = Array(scores.prefix(playerCount)) + Array(repeating: 0, count: max(0, playerCount - scores.count))
        firstRolls = Array(firstRolls.prefix(playerCount)) + Array(repeating: nil, count: max(0, playerCount - firstRolls.count))
        // 名稱最少有 playerCount 筆
        ensureLength(&playerNames, target: playerCount) { "Player \($0 + 1)" }
        // 戰績維持既有長度（至少 4），不裁切，僅使用前 playerCount 位
        if wins.count < playerCount { ensureLength(&wins, target: playerCount, filler: 0) }
        if losses.count < playerCount { ensureLength(&losses, target: playerCount, filler: 0) }
        savePersistentArrays()
    }

    private func ensureLength<T>(_ array: inout [T], target: Int, filler: T) {
        if array.count < target {
            array.append(contentsOf: Array(repeating: filler, count: target - array.count))
        }
    }
    private func ensureLength(_ array: inout [String], target: Int, filler: (Int) -> String) {
        if array.count < target {
            let start = array.count
            for i in start..<target {
                array.append(filler(i))
            }
        }
    }

    private func encodeArray<T: Encodable>(_ array: [T]) -> String? {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(array) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private func decodeArray<T: Decodable>(from string: String) -> [T]? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([T].self, from: data)
    }
}

// 安全索引小工具
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - 晃動效果
private struct ShakeEffect: GeometryEffect {
    var animating: Bool
    var amplitude: CGFloat = 6
    var shakesPerUnit: CGFloat = 6

    var animatableData: CGFloat {
        get { animating ? 1 : 0 }
        set { }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard animating else { return ProjectionTransform(.identity) }
        let translation = amplitude * sin(.pi * 2 * shakesPerUnit * 1.0)
        let transform = CGAffineTransform(translationX: translation, y: 0)
        return ProjectionTransform(transform)
    }
}

// MARK: - 設定頁面
private struct SettingsView: View {
    @Binding var playerCount: Int
    @Binding var playerNames: [String]
    @Binding var wins: [Int]
    @Binding var losses: [Int]

    @Binding var aiReactionDelay: Double
    @Binding var playerRollDuration: Double
    @Binding var aiRollDuration: Double
    @Binding var backgroundOpacity: Double
    @Binding var targetScore: Double
    @Binding var versusMode: ContentView.VersusMode

    var onResetRecords: () -> Void
    var onApply: () -> Void
    var onClose: () -> Void

    private var top3Indices: [Int] {
        let count = min(playerNames.count, max(playerCount, 4))
        let indices = Array(0..<count)
        // 依勝負差排序
        return indices.sorted { (wins[$0] - losses[$0]) > (wins[$1] - losses[$1]) }.prefix(3).map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("玩家設定") {
                    Picker("玩家數量", selection: Binding(
                        get: { playerCount },
                        set: { newValue in
                            playerCount = min(max(newValue, 2), 4)
                        }
                    )) {
                        ForEach(2...4, id: \.self) { count in
                            Text("\(count) 位").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)

                    // 名稱編輯（顯示前 playerCount 位）
                    ForEach(0..<playerCount, id: \.self) { idx in
                        HStack {
                            Text("玩家 \(idx + 1)")
                            TextField("Name (English letters)", text: Binding(
                                get: { idx < playerNames.count ? playerNames[idx] : "Player \(idx + 1)" },
                                set: { newValue in
                                    // 只允許英文字母與空白，並限制最大長度 16
                                    let filtered = newValue.filter { ch in
                                        ch.isLetter || ch == " "
                                    }
                                    let trimmed = String(filtered.prefix(16))

                                    if idx >= playerNames.count {
                                        let need = idx - playerNames.count + 1
                                        playerNames.append(contentsOf: (0..<need).map { _ in "" })
                                    }
                                    playerNames[idx] = trimmed
                                }
                            ))
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        }
                    }

                    // PvC 說明
                    if versusMode == .pvc {
                        Text("PvC 模式下，最後一位玩家為電腦。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("目標分數") {
                    HStack {
                        Text("Target Score")
                        Spacer()
                        Text("\(Int(targetScore))")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $targetScore, in: 10...300, step: 0.1)
                }

                Section("動畫與電腦反應") {
                    HStack {
                        Text("電腦反應時間")
                        Spacer()
                        Text("\(aiReactionDelay, specifier: "%.1f") 秒")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $aiReactionDelay, in: 0.2...4.0, step: 0.1)

                    HStack {
                        Text("玩家擲骰動畫")
                        Spacer()
                        Text("\(playerRollDuration, specifier: "%.1f") 秒")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $playerRollDuration, in: 0.2...1.5, step: 0.1)

                    HStack {
                        Text("電腦擲骰動畫")
                        Spacer()
                        Text("\(aiRollDuration, specifier: "%.1f") 秒")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $aiRollDuration, in: 0.2...1.5, step: 0.1)
                }

                Section("背景") {
                    HStack {
                        Text("背景透明度")
                        Spacer()
                        Text("\(backgroundOpacity, specifier: "%.1f")")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $backgroundOpacity, in: 0.0...1.0, step: 0.1)
                }

                Section("戰績（前三名）") {
                    if top3Indices.isEmpty {
                        Text("尚無戰績")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(top3Indices, id: \.self) { idx in
                            HStack {
                                Text(playerNames[safe: idx] ?? "Player \(idx+1)")
                                Spacer()
                                Text("\(wins[safe: idx] ?? 0) 勝 - \(losses[safe: idx] ?? 0) 敗")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button(role: .destructive) {
                        onResetRecords()
                    } label: {
                        Label("重置戰績", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("自訂設定")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("套用") {
                        onApply()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("關閉")
                }
            }
        }
        .presentationDetents([.large])
    }
}

#Preview {
    ContentView()
}
