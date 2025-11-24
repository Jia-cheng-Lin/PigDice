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
        case pigDice = "Pig Dice"
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

    // 小豬姿勢（1...6，對應 assets 名稱 "01"..."06"）
    @State private var pigPose1: Int = 1
    @State private var pigPose2: Int = 1

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
    private var aiThresholdPigDice: Int { 20 }

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
    @FocusState private var targetFieldFocused: Bool
    @State private var showRestartConfirm: Bool = false

    // 內部玩家名稱與戰績陣列（對應 JSON）
    @State private var playerNames: [String] = ["Player 1", "Player 2", "Player 3", "Computer"]
    @State private var wins: [Int] = [0, 0, 0, 0]
    @State private var losses: [Int] = [0, 0, 0, 0]

    // Inline name input for Player 1（將移除用不到，但先保留變數避免編譯錯誤）
    @State private var player1InlineName: String = ""

    // Pig Dice：顯示最近一次組合名稱/事件
    @State private var lastPigResultText: String = ""
    @State private var lastSpecialEventAsset: String? = nil // "08"/"09" 時顯示

    // Pig Dice：機率調整（持久化）
    @AppStorage("pig_p03") private var p03: Double = 0.10
    @AppStorage("pig_p04") private var p04: Double = 0.10
    @AppStorage("pig_p05") private var p05: Double = 0.05
    @AppStorage("pig_p06") private var p06: Double = 0.03
    @AppStorage("pig_p08") private var p08: Double = 0.02
    @AppStorage("pig_p09") private var p09: Double = 0.001

    // Probability Sheet 顯示
    @State private var showingProbabilitySheet: Bool = false

    // Pig Dice 規則視圖模式
    enum PigRulesViewMode: String, CaseIterable, Identifiable {
        case text = "Text"
        case imageText = "Image + Text"
        var id: String { rawValue }
    }
    @State private var pigRulesViewMode: PigRulesViewMode = .text

    // 規則語言切換
    @AppStorage("rules_isChinese") private var isChineseRules: Bool = false

    // 淘汰玩家集合
    @State private var eliminatedPlayers: Set<Int> = []

    // 新增：圖示詳情
    @State private var selectedPigDetail: PigDetail? = nil

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
                        Text(titleForCurrentMode)
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
                                // 模式切換時，清除強制持續擲的狀態
                                forcedToRoll = false
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
                                        .accessibilityLabel("current target score \(Int(targetScore))")
                                }

                                HStack(spacing: 8) {
                                    TextField("Reset target", text: $targetInputText)
                                        .textFieldStyle(.roundedBorder)
                                        .keyboardType(.numberPad)
                                        .focused($targetFieldFocused)
                                        .toolbar {
                                            ToolbarItemGroup(placement: .keyboard) {
                                                Spacer()
                                                Button {
                                                    targetFieldFocused = false
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                }
                                            }
                                        }
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

                            // Pig Dice 專用：Probability 按鈕
                            if gameMode == .pigDice {
                                HStack {
                                    Spacer()
                                    Button {
                                        showingProbabilitySheet = true
                                    } label: {
                                        Label("Probability", systemImage: "slider.horizontal.3")
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                        .padding(.horizontal)

                        // 分數顯示 + 戰績（動態，2 欄網格）
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                            ForEach(0..<playerCount, id: \.self) { idx in
                                playerScoreView(index: idx, name: displayName(for: idx))
                            }
                        }
                        .padding(.horizontal)

                        // 骰子/小豬顯示與先手決定
                        Group {
                            if isDecidingFirstPlayer {
                                Image(systemName: "die.face.\(dieFace1)")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120, height: 120)
                                    .foregroundStyle(.primary)
                                    .accessibilityLabel("die \(dieFace1)")
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

                                // 先手決定階段的玩家名稱輸入
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Player Names")
                                        .font(.headline)
                                    ForEach(0..<playerCount, id: \.self) { idx in
                                        HStack(spacing: 8) {
                                            Text("Player \(idx + 1)")
                                                .frame(width: 84, alignment: .leading)
                                                .foregroundStyle(.secondary)
                                            if versusMode == .pvc && idx == playerCount - 1 {
                                                Text("Computer")
                                                    .foregroundStyle(.secondary)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(10)
                                                    .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                                                    .accessibilityLabel("Computer")
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
                                switch gameMode {
                                case .oneDice:
                                    Image(systemName: "die.face.\(dieFace1)")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 120, height: 120)
                                        .foregroundStyle(.primary)
                                        .accessibilityLabel("die \(dieFace1)")
                                        .modifier(ShakeEffect(animating: isRolling))
                                case .twoDice:
                                    HStack(spacing: 24) {
                                        Image(systemName: "die.face.\(dieFace1)")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 100, height: 100)
                                            .foregroundStyle(.primary)
                                            .accessibilityLabel("die one \(dieFace1)")
                                            .modifier(ShakeEffect(animating: isRolling))
                                        Image(systemName: "die.face.\(dieFace2)")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 100, height: 100)
                                            .foregroundStyle(.primary)
                                            .accessibilityLabel("die two \(dieFace2)")
                                            .modifier(ShakeEffect(animating: isRolling))
                                    }
                                case .pigDice:
                                    if let specialAsset = lastSpecialEventAsset {
                                        // 特殊事件結果：顯示 08/09
                                        Image(specialAsset)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 180, height: 180)
                                            .accessibilityLabel("special \(specialAsset)")
                                            .modifier(ShakeEffect(animating: isRolling))
                                    } else {
                                        HStack(spacing: 24) {
                                            Image(assetNameForPigPose(pigPose1))
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 120, height: 120)
                                                .accessibilityLabel("left pig pose \(String(format: "%02d", pigPose1))")
                                                .modifier(ShakeEffect(animating: isRolling))
                                            Image(assetNameForPigPose(pigPose2))
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 120, height: 120)
                                                .accessibilityLabel("right pig pose \(String(format: "%02d", pigPose2))")
                                                .modifier(ShakeEffect(animating: isRolling))
                                        }
                                    }
                                }
                                // 狀態/提示（非先手決定階段）
                                Text("Current turn: \(displayName(for: currentPlayer))")
                                    .font(.headline)
                                Text("Accumulated score: \(roundScore)")
                                    .font(.title3)
                                if gameMode == .pigDice && !lastPigResultText.isEmpty {
                                    Text(lastPigResultText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                if gameMode == .twoDice && forcedToRoll {
                                    Text("Doubles (not 1): you must roll again.")
                                        .font(.title2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }

                        // 勝利提示
                        if let winner = winnerIndex {
                            Text("\(displayName(for: winner)) wins!")
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
                                        switch gameMode {
                                        case .oneDice:
                                            playerRollOneDie()
                                        case .twoDice:
                                            playerRollTwoDice()
                                        case .pigDice:
                                            playerRollPigDice()
                                        }
                                    } label: {
                                        Label(rollButtonTitle, systemImage: "dice")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isRolling || isAIsturn || isCurrentPlayerEliminated)

                                    Button {
                                        playerHold()
                                    } label: {
                                        Label("Hold", systemImage: "hand.raised")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isRolling || isAIsturn || roundScore == 0 || (gameMode == .twoDice && forcedToRoll))
                                }
                            }

                            // 與上一排間距加大
                            VStack(spacing: 24) {
                                Button(role: .destructive) {
                                    showRestartConfirm = true
                                } label: {
                                    Label("Restart", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                                .disabled(isRolling)
                                .alert("Restart game?", isPresented: $showRestartConfirm) {
                                    Button("Cancel", role: .cancel) { }
                                    Button("Restart", role: .destructive) {
                                        newGame()
                                    }
                                } message: {
                                    Text("Are you sure you want to restart the game?")
                                }

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
                        .padding(.bottom, 30)
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

                // 左上角語言切換（文字在上、開關在下）
                VStack(alignment: .leading, spacing: 4) {
                    Text("English / 中文")
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Toggle("", isOn: $isChineseRules)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .frame(width: 60, alignment: .leading)
                }
                .padding(.leading, 16)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .zIndex(50)

                // 右上角規則按鈕（保持右上角）
                Button {
                    rulesModeForAlert = gameMode
                    withAnimation(.spring) {
                        showRulesOverlay = true
                    }
                } label: {
                    Label("Rule", systemImage: "questionmark.circle.fill")
                }
                .accessibilityLabel("rules")
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
            enforceProbabilityConstraintsAndClamp()
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
        .sheet(isPresented: $showingProbabilitySheet) {
            ProbabilitySheet(
                isChineseRules: $isChineseRules,
                p03: $p03, p04: $p04, p05: $p05, p06: $p06,
                p08: $p08, p09: $p09,
                onReset: resetProbabilitiesToDefault,
                onApply: {
                    enforceProbabilityConstraintsAndClamp()
                    showingProbabilitySheet = false
                },
                onClose: { showingProbabilitySheet = false }
            )
        }
        // Pig detail sheet
        .sheet(item: $selectedPigDetail) { detail in
            PigDetailView(detail: detail, isChineseRules: isChineseRules) {
                selectedPigDetail = nil
            }
        }
        // 先手提示 Alert
        .alert(isPresented: $showFirstPlayerAlert) {
            let name = pendingFirstPlayer.map { displayName(for: $0) } ?? ""
            return Alert(
                title: Text(isChineseRules ? "先手玩家" : "First player"),
                message: Text(isChineseRules ? "\(name) 先開始" : "\(name) starts"),
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

                if rulesModeForAlert == .pigDice {
                    // Pig Dice 專屬：Text / Image+Text 切換
                    Picker("View", selection: $pigRulesViewMode) {
                        ForEach(PigRulesViewMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if rulesModeForAlert == .pigDice && pigRulesViewMode == .imageText {
                            pigRulesImageTextView
                        } else {
                            Text(rulesMessage(for: rulesModeForAlert))
                                .font(.body)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: 520)

                Divider()

                HStack(spacing: 12) {
                    Button(isChineseRules ? "下一個規則" : "Next") {
                        withAnimation(.easeInOut) {
                            rulesModeForAlert = nextRulesMode(after: rulesModeForAlert)
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(role: .cancel) {
                        withAnimation(.spring) {
                            showRulesOverlay = false
                        }
                    } label: {
                        Text(isChineseRules ? "關閉" : "Close")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
            }
            .frame(maxWidth: 560)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thinMaterial)
                    .shadow(radius: 18, y: 8)
            )
            .padding(.horizontal, 24)
        }
        .accessibilityAddTraits(.isModal)
    }

    private var pigRulesImageTextView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1) 基本單顆
            Text(isChineseRules ? "基本的單顆小豬骰子 (01–06)" : "Basic single-pig poses (01–06)")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(1...6, id: \.self) { pose in
                    HStack(spacing: 10) {
                        Image(String(format: "%02d", pose))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .onTapGesture {
                                openDetailForPose(pose)
                            }
                        Text(isChineseRules ? poseNameCN(pose) : poseName(pose))
                            .lineLimit(1)
                            .allowsTightening(true)
                            .minimumScaleFactor(0.8)
                        Spacer()
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
                }
            }

            Divider().padding(.vertical, 4)

            // 2) 懲罰組合 (07–09)
            Text(isChineseRules ? "懲罰組合 (07–09)" : "Penalty combos (07–09)")
                .font(.headline)
            VStack(spacing: 8) {
                // 07 Pig out = 01 + 02
                comboRow(left: "01", right: "02", label: isChineseRules ? "07: Pig out — 回合歸零" : "07: Pig out — reset round")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openDetailForCombo(p1: 1, p2: 2, code: 7)
                    }
                // 08 Oinker
                singleAssetRow(asset: "08", label: isChineseRules ? "08: Oinker — 總分歸零" : "08: Oinker — total reset")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openDetailForSpecial("08")
                    }
                // 09 Piggy back
                singleAssetRow(asset: "09", label: isChineseRules ? "09: Piggy back — 淘汰" : "09: Piggy back — eliminated")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openDetailForSpecial("09")
                    }
            }

            Divider().padding(.vertical, 4)

            // 3) 一般組合 (10–21)
            Text(isChineseRules ? "一般組合 (10–21)" : "Normal combos (10–21)")
                .font(.headline)
            VStack(spacing: 8) {
                // 10: 02+02
                comboRow(left: "02", right: "02", label: textForCombo(10))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 2, p2: 2, code: 10) }
                // 11: 01+01
                comboRow(left: "01", right: "01", label: textForCombo(11))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 1, p2: 1, code: 11) }
                // 12: (01/02)+03
                comboRow(left: "01", right: "03", label: textForCombo(12, variant: "01+03"))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 1, p2: 3, code: 12) }
                comboRow(left: "02", right: "03", label: textForCombo(12, variant: "02+03"))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 2, p2: 3, code: 12) }
                // 13: (01/02)+04
                comboRow(left: "01", right: "04", label: textForCombo(13, variant: "01+04"))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 1, p2: 4, code: 13) }
                comboRow(left: "02", right: "04", label: textForCombo(13, variant: "02+04"))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 2, p2: 4, code: 13) }
                // 14: (01/02)+05
                comboRow(left: "01", right: "05", label: textForCombo(14, variant: "01+05"))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 1, p2: 5, code: 14) }
                comboRow(left: "02", right: "05", label: textForCombo(14, variant: "02+05"))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 2, p2: 5, code: 14) }
                // 15: (01/02)+06
                comboRow(left: "01", right: "06", label: textForCombo(15, variant: "01+06"))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 1, p2: 6, code: 15) }
                comboRow(left: "02", right: "06", label: textForCombo(15, variant: "02+06"))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 2, p2: 6, code: 15) }
                // 16: 03+04
                comboRow(left: "03", right: "04", label: textForCombo(16))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 3, p2: 4, code: 16) }
                // 17: 04+05
                comboRow(left: "04", right: "05", label: textForCombo(17))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 4, p2: 5, code: 17) }
                // 18: 04+06
                comboRow(left: "04", right: "06", label: textForCombo(18))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 4, p2: 6, code: 18) }
                // 19: 03+05
                comboRow(left: "03", right: "05", label: textForCombo(19))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 3, p2: 5, code: 19) }
                // 20: 03+06
                comboRow(left: "03", right: "06", label: textForCombo(20))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 3, p2: 6, code: 20) }
                // 21: 05+06
                comboRow(left: "05", right: "06", label: textForCombo(21))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 5, p2: 6, code: 21) }
            }

            Divider().padding(.vertical, 4)

            // 4) 雙倍組合 (22–25)
            Text(isChineseRules ? "雙倍組合 (22–25)" : "Double combos (22–25)")
            .font(.headline)
            VStack(spacing: 8) {
                comboRow(left: "03", right: "03", label: textForCombo(22))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 3, p2: 3, code: 22) }
                comboRow(left: "04", right: "04", label: textForCombo(23))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 4, p2: 4, code: 23) }
                comboRow(left: "05", right: "05", label: textForCombo(24))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 5, p2: 5, code: 24) }
                comboRow(left: "06", right: "06", label: textForCombo(25))
                    .contentShape(Rectangle())
                    .onTapGesture { openDetailForCombo(p1: 6, p2: 6, code: 25) }
            }
        }
    }

    private func comboRow(left: String, right: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(left)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
            Image(right)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
            Text(label)
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.85)
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
    }

    private func singleAssetRow(asset: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
            Text(label)
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.85)
            Spacer()
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
    }

    private func nextRulesMode(after mode: GameMode) -> GameMode {
        switch mode {
        case .oneDice: return .twoDice
        case .twoDice: return .pigDice
        case .pigDice: return .oneDice
        }
    }

    // MARK: - 計算屬性

    private var isAIsturn: Bool {
        // PvC 時最後一位為電腦
        versusMode == .pvc && currentPlayer == playerCount - 1 && !isDecidingFirstPlayer && winnerIndex == nil
    }

    private var isCurrentPlayerEliminated: Bool {
        eliminatedPlayers.contains(currentPlayer)
    }

    private var titleForCurrentMode: String {
        switch gameMode {
        case .oneDice: return "Dice Game Pig"
        case .twoDice: return "Two Dice Pig"
        case .pigDice: return "Pig Dice"
        }
    }

    private var rollButtonTitle: String {
        switch gameMode {
        case .oneDice: return "One Dice"
        case .twoDice: return "Two Dice"
        case .pigDice: return "Roll Pigs"
        }
    }

    private func displayName(for index: Int) -> String {
        // PvC: 最後一位為電腦
        if versusMode == .pvc && index == playerCount - 1 {
            return "Computer"
        }
        // 取得使用者輸入的名稱（若有），否則回退到 Player N
        let candidate: String
        if index < playerNames.count {
            let trimmed = playerNames[index].trimmingCharacters(in: .whitespacesAndNewlines)
            candidate = trimmed.isEmpty ? "Player \(index + 1)" : trimmed
        } else {
            candidate = "Player \(index + 1)"
        }
        // PvP：避免顯示 Computer
        let lowered = candidate.lowercased()
        if versusMode == .pvp && (lowered == "computer" || lowered == "電腦") {
            return "Player \(index + 1)"
        }
        return candidate
    }

    // MARK: - 規則字串

    private func rulesTitle(for mode: GameMode) -> String {
        switch mode {
        case .oneDice: return isChineseRules ? "單顆骰子規則" : "One Die rules"
        case .twoDice: return isChineseRules ? "兩顆骰子規則" : "Two Dice rules"
        case .pigDice: return isChineseRules ? "小豬骰子規則" : "Pig Dice rules"
        }
    }

    private func rulesMessage(for mode: GameMode) -> String {
        switch mode {
        case .oneDice:
            return isChineseRules
            ? """
            - 每回合擲一顆骰子。
            - 擲到 1：本回合分數歸零並換人。
            - 擲到 2~6：點數累加到本回合分數，可選擇繼續擲或 Hold。
            - 達到目標分數（\(Int(targetScore))）即獲勝。若擲完即達標，無需按 Hold。
            """
            : """
            - Roll one die per turn.
            - If you roll 1: round score resets to 0 and your turn ends.
            - If you roll 2~6: add to round score; you can roll again or hold.
            - Reach target score (\(Int(targetScore))) to win. If reaching on a roll, no need to press Hold.
            """
        case .twoDice:
            return isChineseRules
            ? """
            - 每回合擲兩顆骰子。
            - 其中一顆為 1：本回合分數歸零並換人。
            - 兩顆都是 1：本回合分數歸零，且你的總分歸零，然後換人。
            - 兩顆相同但不是 1：點數累加，同時你必須繼續擲，不能 Hold。
            - 其他情況：兩顆點數相加累加到本回合分數，可選擇繼續擲或 Hold。
            - 達到目標分數（\(Int(targetScore))）即獲勝。若擲完即達標，無需按 Hold。
            """
            : """
            - Roll two dice per turn.
            - If either die is 1: round score resets to 0 and your turn ends.
            - If both are 1: round score resets to 0 and your total score resets to 0; turn ends.
            - If both dice are the same but not 1: add to round score AND you must roll again (no hold).
            - Otherwise: add the sum to round score; you can roll again or hold.
            - Reach target score (\(Int(targetScore))) to win. If reaching on a roll, no need to press Hold.
            """
        case .pigDice:
            return isChineseRules
            ? """
            🎯 目標
            - 擲出兩隻小豬累積分數，最先達到 \(Int(targetScore)) 分者獲勝。

            ▶️ 流程
            - 玩家輪流擲兩隻小豬。
            - 根據兩隻小豬落地姿勢的組合得分。
            - 每次得分後可選擇繼續擲（冒更高風險）或停擺 Hold（把本回合分數加入總分並換人）。
            - 擲到 Pig out（見下）時，本回合分數歸零並換人。

            🐷 單隻小豬的可能姿勢（代號）
            - 01: Sideways
            - 02: Point Sideways
            - 03: Standing（Troter）
            - 04: Legs up（Razorback）
            - 05: Head Down（Snouter）
            - 06: Leaning jowler

            🧮 組合與分數
            - 07: Pig out（= 01 + 02 或 02 + 01）：本回合分數歸零並換人。
            - 10: Point sider（02 + 02）= 1 分
            - 11: Sider（01 + 01）= 1 分
            - 12: Troter（01/02 + 03）= 5 分
            - 13: Razorback（01/02 + 04）= 5 分
            - 14: Snouter（01/02 + 05）= 10 分
            - 15: Leaning jowler（01/02 + 06）= 15 分
            - 16: Razorback + Troter（03 + 04）= 10 分
            - 17: Razorback + Snouter（04 + 05）= 15 分
            - 18: Razorback + Leaning jowler（04 + 06）= 20 分
            - 19: Troter + Snouter（03 + 05）= 15 分
            - 20: Troter + Leaning jowler（03 + 06）= 20 分
            - 21: Snouter + Leaning jowler（05 + 06）= 25 分
            - 22: Double Troter（03 + 03）= 20 分
            - 23: Double Razorback（04 + 04）= 20 分
            - 24: Double Snouter（05 + 05）= 40 分
            - 25: Double Leaning jowler（06 + 06）= 60 分

            ⚠️ 特殊事件
            - 08: Oinker（兩豬相碰）— 總分歸零
            - 09: Piggy back（其中一豬未碰桌）— 淘汰
            """
            : """
            Goal
            - Roll two pigs to accumulate points. First to reach \(Int(targetScore)) wins.

            Flow
            - Players take turns to roll two pigs.
            - Score depends on the two-pig combination.
            - After scoring, you may roll again (higher risk) or hold (bank the round score).
            - Pig out (see below) resets round score and ends your turn.

            Poses (single pig code)
            - 01: Sideways
            - 02: Point Sideways
            - 03: Standing (Troter)
            - 04: Legs up (Razorback)
            - 05: Head Down (Snouter)
            - 06: Leaning jowler

            Scoring combinations
            - 07: Pig out (= 01 + 02 or 02 + 01): round score resets; end turn.
            - 10: Point sider (02 + 02) = 1
            - 11: Sider (01 + 01) = 1
            - 12: Troter (01/02 + 03) = 5
            - 13: Razorback (01/02 + 04) = 5
            - 14: Snouter (01/02 + 05) = 10
            - 15: Leaning jowler (01/02 + 06) = 15
            - 16: Razorback + Troter (03 + 04) = 10
            - 17: Razorback + Snouter (04 + 05) = 15
            - 18: Razorback + Leaning jowler (04 + 06) = 20
            - 19: Troter + Snouter (03 + 05) = 15
            - 20: Troter + Leaning jowler (03 + 06) = 20
            - 21: Snouter + Leaning jowler (05 + 06) = 25
            - 22: Double Troter (03 + 03) = 20
            - 23: Double Razorback (04 + 04) = 20
            - 24: Double Snouter (05 + 05) = 40
            - 25: Double Leaning jowler (06 + 06) = 60

            Special events
            - 08: Oinker (touch together) — lose all total points
            - 09: Piggy back (one pig doesn't touch table) — eliminated
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
            HStack {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if eliminatedPlayers.contains(index) {
                    Text("(eliminated)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Text("\(scores[safe: index] ?? 0)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            if isDecidingFirstPlayer {
                if let roll = firstRolls[safe: index] ?? nil {
                    Text("First: \(roll)")
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
            Text("W-L: \(wins[safe: index] ?? 0) - \(losses[safe: index] ?? 0)")
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
        pigPose1 = 1
        pigPose2 = 1
        winnerIndex = nil
        isDecidingFirstPlayer = true
        firstRolls = Array(repeating: nil, count: playerCount)
        isRolling = false
        forcedToRoll = false
        pendingFirstPlayer = nil
        showFirstPlayerAlert = false
        showRulesOverlay = false
        lastPigResultText = ""
        lastSpecialEventAsset = nil
        eliminatedPlayers.removeAll()
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

    private func playerRollPigDice() {
        guard !isRolling else { return }
        isRolling = true
        animatePigRoll(duration: playerRollDuration, ticks: 10) {
            rollPigDiceCore()
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

    private func rollPigDiceCore() {
        guard winnerIndex == nil, !isDecidingFirstPlayer else { return }

        // 先判定特殊事件：08 / 09
        lastSpecialEventAsset = nil
        if specialEventTriggered() {
            return
        }

        // 使用權重機率抽樣（可調）
        let p1 = weightedPigPose()
        let p2 = weightedPigPose()
        pigPose1 = p1
        pigPose2 = p2
        forcedToRoll = false // 小豬模式暫無「必須繼續擲」規則
        lastPigResultText = "" // 先清

        let result = pigScoreFor(p1: p1, p2: p2)
        if result.bust { // Pig out
            roundScore = 0
            lastPigResultText = isChineseRules ? "Pig out — 回合歸零" : "Pig out — reset round"
            switchPlayer()
        } else {
            roundScore += result.points
            let label = isChineseRules ? comboNameCN(result.name) : result.name
            lastPigResultText = "\(label) (+\(result.points))"
            if scores[currentPlayer] + roundScore >= Int(targetScore) {
                scores[currentPlayer] += roundScore
                roundScore = 0
                setWinnerIfNeeded(currentPlayer)
            }
        }
    }

    // 特殊事件：08 Oinker / 09 Piggy back
    private func specialEventTriggered() -> Bool {
        // p08 與 p09 的總和不參與 01~06 的 1.0 配額；它們獨立於擲豬前判定
        let r = Double.random(in: 0..<1)
        if r < p08 {
            // Oinker：總分清零，顯示 "08"
            lastSpecialEventAsset = "08"
            lastPigResultText = isChineseRules ? "Oinker — 總分歸零" : "Oinker — total reset"
            scores[currentPlayer] = 0
            roundScore = 0
            switchPlayer()
            return true
        } else if r < p08 + p09 {
            // Piggy back：淘汰當前玩家，顯示 "09"
            lastSpecialEventAsset = "09"
            lastPigResultText = isChineseRules ? "Piggy back — 淘汰" : "Piggy back — eliminated"
            eliminatedPlayers.insert(currentPlayer)
            roundScore = 0
            // 若只剩一名未淘汰者，直接勝利
            if let sole = soleRemainingPlayer() {
                setWinnerIfNeeded(sole)
            } else {
                switchPlayer()
            }
            return true
        }
        return false
    }

    private func holdCore() {
        guard winnerIndex == nil, !isDecidingFirstPlayer else { return }
        scores[currentPlayer] += roundScore
        roundScore = 0
        forcedToRoll = false
        lastPigResultText = ""
        lastSpecialEventAsset = nil

        if scores[currentPlayer] >= Int(targetScore) {
            setWinnerIfNeeded(currentPlayer)
        } else {
            switchPlayer()
        }
    }

    private func switchPlayer() {
        // 從下一位開始往後找第一個未淘汰玩家
        guard playerCount > 0 else { return }
        var next = currentPlayer
        var attempts = 0
        repeat {
            next = (next + 1) % playerCount
            attempts += 1
            if attempts > playerCount { break }
        } while eliminatedPlayers.contains(next)

        currentPlayer = next
        forcedToRoll = false

        // 若當前玩家也被淘汰（理論上不會），再次跳轉
        if eliminatedPlayers.contains(currentPlayer) {
            if let sole = soleRemainingPlayer() {
                setWinnerIfNeeded(sole)
            }
        }
    }

    private func soleRemainingPlayer() -> Int? {
        let alive = (0..<playerCount).filter { !eliminatedPlayers.contains($0) }
        return alive.count == 1 ? alive.first : nil
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

                let thresholdBase: Int = {
                    switch self.gameMode {
                    case .oneDice: return self.aiThresholdOneDie
                    case .twoDice: return self.aiThresholdTwoDice
                    case .pigDice: return self.aiThresholdPigDice
                    }
                }()

                let canWinIfHold = self.scores[self.currentPlayer] + self.roundScore >= Int(self.targetScore)
                let forced = (self.gameMode == .twoDice && self.forcedToRoll)
                let shouldHold = !forced && (canWinIfHold || self.roundScore >= thresholdBase)

                if shouldHold {
                    self.holdCore()
                    return
                } else {
                    switch self.gameMode {
                    case .oneDice:
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
                    case .twoDice:
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
                    case .pigDice:
                        self.isRolling = true
                        self.animatePigRoll(duration: self.aiRollDuration, ticks: 6) {
                            self.rollPigDiceCore()
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

    private func animatePigRoll(duration: Double, ticks: Int, completion: @escaping () -> Void) {
        guard ticks > 0 else { completion(); return }
        let interval = duration / Double(ticks)
        var currentTick = 0

        func tick() {
            currentTick += 1
            // 動畫也使用權重，讓閃動更貼近最終分佈（僅視覺）
            pigPose1 = weightedPigPose()
            pigPose2 = weightedPigPose()
            lastSpecialEventAsset = nil
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

    // MARK: - Pig Dice 計分與抽樣

    private func pigScoreFor(p1: Int, p2: Int) -> (points: Int, bust: Bool, name: String) {
        // Pig out: 01+02 或 02+01
        if (p1 == 1 && p2 == 2) || (p1 == 2 && p2 == 1) {
            return (0, true, "Pig out")
        }

        func isSidewaysOrPoint(_ v: Int) -> Bool { v == 1 || v == 2 }

        // 02+02 / 01+01
        if p1 == 2 && p2 == 2 { return (1, false, "Point sider") }
        if p1 == 1 && p2 == 1 { return (1, false, "Sider") }

        // (01/02)+03 = 5
        if (isSidewaysOrPoint(p1) && p2 == 3) || (isSidewaysOrPoint(p2) && p1 == 3) {
            return (5, false, "Troter")
        }
        // (01/02)+04 = 5
        if (isSidewaysOrPoint(p1) && p2 == 4) || (isSidewaysOrPoint(p2) && p1 == 4) {
            return (5, false, "Razorback")
        }
        // (01/02)+05 = 10
        if (isSidewaysOrPoint(p1) && p2 == 5) || (isSidewaysOrPoint(p2) && p1 == 5) {
            return (10, false, "Snouter")
        }
        // (01/02)+06 = 15
        if (isSidewaysOrPoint(p1) && p2 == 6) || (isSidewaysOrPoint(p2) && p1 == 6) {
            return (15, false, "Leaning jowler")
        }

        // 03+04 = 10
        if (p1 == 3 && p2 == 4) || (p1 == 4 && p2 == 3) { return (10, false, "Razorback + Troter") }
        // 04+05 = 15
        if (p1 == 4 && p2 == 5) || (p1 == 5 && p2 == 4) { return (15, false, "Razorback + Snouter") }
        // 04+06 = 20
        if (p1 == 4 && p2 == 6) || (p1 == 6 && p2 == 4) { return (20, false, "Razorback + Leaning jowler") }
        // 03+05 = 15
        if (p1 == 3 && p2 == 5) || (p1 == 5 && p2 == 3) { return (15, false, "Troter + Snouter") }
        // 03+06 = 20
        if (p1 == 3 && p2 == 6) || (p1 == 6 && p2 == 3) { return (20, false, "Troter + Leaning jowler") }
        // 05+06 = 25
        if (p1 == 5 && p2 == 6) || (p1 == 6 && p2 == 5) { return (25, false, "Snouter + Leaning jowler") }

        // Doubles
        if p1 == 3 && p2 == 3 { return (20, false, "Double Troter") }
        if p1 == 4 && p2 == 4 { return (20, false, "Double Razorback") }
        if p1 == 5 && p2 == 5 { return (40, false, "Double Snouter") }
        if p1 == 6 && p2 == 6 { return (60, false, "Double Leaning jowler") }

        return (0, false, "Unknown")
    }

    // 權重抽樣（01/02 由剩餘推導且相等；03>04>05>06）
    private func weightedPigPose() -> Int {
        let (q01, q02, q03, q04, q05, q06) = currentPoseProbabilities()
        let r = Double.random(in: 0..<1)
        let cuts = [q01, q01+q02, q01+q02+q03, q01+q02+q03+q04, q01+q02+q03+q04+q05]
        if r < cuts[0] { return 1 }
        if r < cuts[1] { return 2 }
        if r < cuts[2] { return 3 }
        if r < cuts[3] { return 4 }
        if r < cuts[4] { return 5 }
        return 6
    }

    private func currentPoseProbabilities() -> (Double, Double, Double, Double, Double, Double) {
        // 先確保 03>04>05>06，且四者總和 < 1
        var a = max(0, min(1, p03))
        var b = max(0, min(a - 0.0001, p04)) // b < a
        var c = max(0, min(b - 0.0001, p05)) // c < b
        var d = max(0, min(c - 0.0001, p06)) // d < c
        let sum3456 = a + b + c + d
        if sum3456 >= 0.9999 {
            // 若超出或接近 1，按比例縮小至 0.96，留 0.04 給 01/02
            let scale = 0.96 / sum3456
            a *= scale; b *= scale; c *= scale; d *= scale
        }
        let remain = max(0, 1 - (a + b + c + d))
        let q01 = remain / 2
        let q02 = remain / 2
        return (q01, q02, a, b, c, d)
    }

    private func poseName(_ pose: Int) -> String {
        switch pose {
        case 1: return "Sideways"
        case 2: return "Point Sideways"
        case 3: return "Standing (Troter)"
        case 4: return "Legs up (Razorback)"
        case 5: return "Head Down (Snouter)"
        case 6: return "Leaning jowler"
        default: return "Unknown"
        }
    }

    private func poseNameCN(_ pose: Int) -> String {
        switch pose {
        case 1: return "側躺 (Sideways)"
        case 2: return "尖頭側躺 (Point Sideways)"
        case 3: return "站立 (Troter)"
        case 4: return "四腳朝天 (Razorback)"
        case 5: return "頭朝下 (Snouter)"
        case 6: return "歪頭 (Leaning jowler)"
        default: return "未知"
        }
    }

    private func comboNameCN(_ english: String) -> String {
        switch english {
        case "Point sider": return "Point sider"
        case "Sider": return "Sider"
        case "Troter": return "Troter"
        case "Razorback": return "Razorback"
        case "Snouter": return "Snouter"
        case "Leaning jowler": return "Leaning jowler"
        case "Razorback + Troter": return "Razorback + Troter"
        case "Razorback + Snouter": return "Razorback + Snouter"
        case "Razorback + Leaning jowler": return "Razorback + Leaning jowler"
        case "Troter + Snouter": return "Troter + Snouter"
        case "Troter + Leaning jowler": return "Troter + Leaning jowler"
        case "Snouter + Leaning jowler": return "Snouter + Leaning jowler"
        case "Double Troter": return "Double Troter"
        case "Double Razorback": return "Double Razorback"
        case "Double Snouter": return "Double Snouter"
        case "Double Leaning jowler": return "Double Leaning jowler"
        default: return english
        }
    }

    private func textForCombo(_ code: Int, variant: String? = nil) -> String {
        if isChineseRules {
            switch code {
            case 10: return "10: Point sider (02+02) = 1"
            case 11: return "11: Sider (01+01) = 1"
            case 12: return "12: Troter (\(variant ?? "01/02+03")) = 5"
            case 13: return "13: Razorback (\(variant ?? "01/02+04")) = 5"
            case 14: return "14: Snouter (\(variant ?? "01/02+05")) = 10"
            case 15: return "15: Leaning jowler (\(variant ?? "01/02+06")) = 15"
            case 16: return "16: Razorback + Troter (03+04) = 10"
            case 17: return "17: Razorback + Snouter (04+5) = 15"
            case 18: return "18: Razorback + Leaning jowler (04+06) = 20"
            case 19: return "19: Troter + Snouter (03+05) = 15"
            case 20: return "20: Troter + Leaning jowler (03+06) = 20"
            case 21: return "21: Snouter + Leaning jowler (05+06) = 25"
            case 22: return "22: Double Troter (03+03) = 20"
            case 23: return "23: Double Razorback (04+04) = 20"
            case 24: return "24: Double Snouter (05+05) = 40"
            case 25: return "25: Double Leaning jowler (06+06) = 60"
            default: return ""
            }
        } else {
            switch code {
            case 10: return "10: Point sider (02+02) = 1"
            case 11: return "11: Sider (01+01) = 1"
            case 12: return "12: Troter (\(variant ?? "01/02+03")) = 5"
            case 13: return "13: Razorback (\(variant ?? "01/02+04")) = 5"
            case 14: return "14: Snouter (\(variant ?? "01/02+05")) = 10"
            case 15: return "15: Leaning jowler (\(variant ?? "01/02+06")) = 15"
            case 16: return "16: Razorback + Troter (03+04) = 10"
            case 17: return "17: Razorback + Snouter (04+05) = 15"
            case 18: return "18: Razorback + Leaning jowler (04+06) = 20"
            case 19: return "19: Troter + Snouter (03+05) = 15"
            case 20: return "20: Troter + Leaning jowler (03+06) = 20"
            case 21: return "21: Snouter + Leaning jowler (05+06) = 25"
            case 22: return "22: Double Troter (03+03) = 20"
            case 23: return "23: Double Razorback (04+04) = 20"
            case 24: return "24: Double Snouter (05+05) = 40"
            case 25: return "25: Double Leaning jowler (06+06) = 60"
            default: return ""
            }
        }
    }

    private func pigCombinationList() -> [String] {
        // 已由圖文清單取代，此函式仍保留（若文字版切換時使用）
        if isChineseRules {
            return [
                "Pig out (01+02 / 02+01) — 回合歸零",
                "Point sider (02+02) = 1",
                "Sider (01+01) = 1",
                "Troter (01/02+03) = 5",
                "Razorback (01/02+04) = 5",
                "Snouter (01/02+05) = 10",
                "Leaning jowler (01/02+06) = 15",
                "Razorback + Troter (03+04) = 10",
                "Razorback + Snouter (04+05) = 15",
                "Razorback + Leaning jowler (04+06) = 20",
                "Troter + Snouter (03+05) = 15",
                "Troter + Leaning jowler (03+06) = 20",
                "Snouter + Leaning jowler (05+06) = 25",
                "Double Troter (03+03) = 20",
                "Double Razorback (04+04) = 20",
                "Double Snouter (05+05) = 40",
                "Double Leaning jowler (06+06) = 60",
                "Special — Oinker (08): 總分歸零",
                "Special — Piggy back (09): 淘汰"
            ]
        } else {
            return [
                "Pig out (01 + 02 / 02 + 01) — reset round",
                "Point sider (02 + 02) = 1",
                "Sider (01 + 01) = 1",
                "Troter (01/02 + 03) = 5",
                "Razorback (01/02 + 04) = 5",
                "Snouter (01/02 + 05) = 10",
                "Leaning jowler (01/02 + 06) = 15",
                "Razorback + Troter (03 + 04) = 10",
                "Razorback + Snouter (04 + 05) = 15",
                "Razorback + Leaning jowler (04 + 06) = 20",
                "Troter + Snouter (03 + 05) = 15",
                "Troter + Leaning jowler (03 + 06) = 20",
                "Snouter + Leaning jowler (05 + 06) = 25",
                "Double Troter (03 + 03) = 20",
                "Double Razorback (04 + 04) = 20",
                "Double Snouter (05 + 05) = 40",
                "Double Leaning jowler (06 + 06) = 60",
                "Special — Oinker (08): total reset",
                "Special — Piggy back (09): eliminated"
            ]
        }
    }

    private func assetNameForPigPose(_ pose: Int) -> String {
        // 資源名稱即為 "01"..."06"
        let code = String(format: "%02d", max(1, min(6, pose)))
        return code
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

    // MARK: - 機率工具

    private func enforceProbabilityConstraintsAndClamp() {
        // 確保順序 03 > 04 > 05 > 06，並限制到 [0,1)
        var a = max(0, min(0.99, p03))
        var b = max(0, min(a - 0.0001, p04))
        var c = max(0, min(b - 0.0001, p05))
        var d = max(0, min(c - 0.0001, p06))
        let sum = a + b + c + d
        if sum >= 0.9999 {
            let scale = 0.96 / sum
            a *= scale; b *= scale; c *= scale; d *= scale
        }
        p03 = a; p04 = b; p05 = c; p06 = d

        // 特殊事件合理範圍
        p08 = max(0, min(0.5, p08))
        p09 = max(0, min(0.5, p09))
    }

    private func resetProbabilitiesToDefault() {
        p03 = 0.10
        p04 = 0.10
        p05 = 0.05
        p06 = 0.03
        p08 = 0.02
        p09 = 0.001
        enforceProbabilityConstraintsAndClamp()
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
                Section("Players") {
                    Picker("Players", selection: Binding(
                        get: { playerCount },
                        set: { newValue in
                            playerCount = min(max(newValue, 2), 4)
                        }
                    )) {
                        ForEach(2...4, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)

                    // 名稱編輯（顯示前 playerCount 位）
                    ForEach(0..<playerCount, id: \.self) { idx in
                        HStack {
                            Text("Player \(idx + 1)")
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
                        Text("In PvC, the last player is the computer.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Target score") {
                    HStack {
                        Text("Target Score")
                        Spacer()
                        Text("\(Int(targetScore))")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $targetScore, in: 10...300, step: 0.1)
                }

                Section("Animation & AI") {
                    HStack {
                        Text("AI reaction")
                        Spacer()
                        Text("\(aiReactionDelay, specifier: "%.1f") s")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $aiReactionDelay, in: 0.2...4.0, step: 0.1)

                    HStack {
                        Text("Player roll animation")
                        Spacer()
                        Text("\(playerRollDuration, specifier: "%.1f") s")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $playerRollDuration, in: 0.2...1.5, step: 0.1)

                    HStack {
                        Text("AI roll animation")
                        Spacer()
                        Text("\(aiRollDuration, specifier: "%.1f") s")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $aiRollDuration, in: 0.2...1.5, step: 0.1)
                }

                Section("Background") {
                    HStack {
                        Text("Background opacity")
                        Spacer()
                        Text("\(backgroundOpacity, specifier: "%.1f")")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $backgroundOpacity, in: 0.0...1.0, step: 0.1)
                }

                Section("Records (Top 3)") {
                    if top3Indices.isEmpty {
                        Text("No record yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(top3Indices, id: \.self) { idx in
                            HStack {
                                Text(playerNames[safe: idx] ?? "Player \(idx+1)")
                                Spacer()
                                Text("\(wins[safe: idx] ?? 0) W - \(losses[safe: idx] ?? 0) L")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button(role: .destructive) {
                        onResetRecords()
                    } label: {
                        Label("Reset records", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Apply") {
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
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Probability Sheet
private struct ProbabilitySheet: View {
    @Binding var isChineseRules: Bool

    @Binding var p03: Double
    @Binding var p04: Double
    @Binding var p05: Double
    @Binding var p06: Double
    @Binding var p08: Double
    @Binding var p09: Double

    var onReset: () -> Void
    var onApply: () -> Void
    var onClose: () -> Void

    // 預設方案
    enum Preset: String, CaseIterable, Identifiable {
        case lowRisk
        case balanced
        case highRisk
        var id: String { rawValue }

        func title(isCN: Bool) -> String {
            switch self {
            case .lowRisk: return isCN ? "低風險" : "Low risk"
            case .balanced: return isCN ? "平衡" : "Balanced"
            case .highRisk: return isCN ? "高風險" : "High risk"
            }
        }

        var values: (Double, Double, Double, Double, Double, Double) {
            switch self {
            case .lowRisk:   return (0.20, 0.15, 0.08, 0.04, 0.00, 0.000)
            case .balanced:  return (0.10, 0.08, 0.05, 0.03, 0.02, 0.001)
            case .highRisk:  return (0.08, 0.06, 0.05, 0.04, 0.05, 0.010)
            }
        }
    }

    @State private var selectedPreset: Preset? = nil

    // 原始值（用於驗證失敗時還原）
    @State private var originalP03: Double = 0
    @State private var originalP04: Double = 0
    @State private var originalP05: Double = 0
    @State private var originalP06: Double = 0
    @State private var originalP08: Double = 0
    @State private var originalP09: Double = 0

    @State private var showInvalidAlert: Bool = false

    // 動態顯示 p01/p02（由剩餘推導）
    private var derived01: Double {
        let sum = p03 + p04 + p05 + p06
        let remain = max(0, 1 - sum)
        return remain / 2
    }

    private func applyPreset(_ preset: Preset) {
        let v = preset.values
        p03 = v.0; p04 = v.1; p05 = v.2; p06 = v.3
        p08 = v.4; p09 = v.5
    }

    private func cacheOriginals() {
        originalP03 = p03
        originalP04 = p04
        originalP05 = p05
        originalP06 = p06
        originalP08 = p08
        originalP09 = p09
    }

    private func restoreOriginals() {
        p03 = originalP03
        p04 = originalP04
        p05 = originalP05
        p06 = originalP06
        p08 = originalP08
        p09 = originalP09
    }

    private func validateStrictOrder() -> Bool {
        // 嚴格 03 > 04 > 05 > 06
        return p03 > p04 && p04 > p05 && p05 > p06
    }

    var body: some View {
        NavigationStack {
            Form {
                // 置頂：Reset 與語言切換
                Section {
                    HStack {
                        Button(role: .destructive) {
                            onReset()
                            // 重置後更新原始值快取，避免立即 Apply 被視為變更
                            cacheOriginals()
                        } label: {
                            Label(isChineseRules ? "恢復預設" : "Reset to defaults", systemImage: "arrow.counterclockwise")
                        }
                        Spacer()
                        Toggle(isOn: $isChineseRules) {
                            Text("中文 / English")
                        }
                        .toggleStyle(.switch)
                    }
                }

                // 預設方案 Segmented Picker
                Section(isChineseRules ? "預設方案" : "Presets") {
                    Picker(isChineseRules ? "選擇方案" : "Choose preset", selection: Binding(
                        get: { selectedPreset ?? .balanced },
                        set: { newValue in
                            selectedPreset = newValue
                            applyPreset(newValue)
                        }
                    )) {
                        ForEach(Preset.allCases) { p in
                            Text(p.title(isCN: isChineseRules)).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(isChineseRules ? "單隻小豬機率（總和 = 1）" : "Single pig pose probabilities (sum = 1)") {
                    HStack {
                        Text("Pose 03 (Troter)")
                        Spacer()
                        Text("\(p03, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $p03, in: 0...0.9, step: 0.01)

                    HStack {
                        Text("Pose 04 (Razorback)")
                        Spacer()
                        Text("\(p04, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $p04, in: 0...0.9, step: 0.01)

                    HStack {
                        Text("Pose 05 (Snouter)")
                        Spacer()
                        Text("\(p05, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $p05, in: 0...0.9, step: 0.01)

                    HStack {
                        Text("Pose 06 (Leaning jowler)")
                        Spacer()
                        Text("\(p06, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $p06, in: 0...0.9, step: 0.01)

                    HStack {
                        Text("Pose 01 (Sideways)")
                        Spacer()
                        Text("\(derived01, specifier: "%.3f")")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Pose 02 (Point Sideways)")
                        Spacer()
                        Text("\(derived01, specifier: "%.3f")")
                            .foregroundStyle(.secondary)
                    }

                    Text(isChineseRules
                         ? "限制：03 > 04 > 05 > 06，且 01 = 02 = (1 - (03+04+05+06))/2"
                         : "Constraints: 03 > 04 > 05 > 06, and 01 = 02 = (1 - (03+04+05+06))/2")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(isChineseRules ? "特殊事件" : "Special events") {
                    HStack {
                        Text("08: Oinker")
                        Spacer()
                        Text("\(p08, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                    }
                    // 0...1，0.5 步進
                    Slider(value: $p08, in: 0...1.0, step: 0.5)

                    HStack {
                        Text("09: Piggy back")
                        Spacer()
                        Text("\(p09, specifier: "%.3f")")
                            .foregroundStyle(.secondary)
                    }
                    // 0...0.2，0.005 步進
                    Slider(value: $p09, in: 0...0.2, step: 0.005)

                    Text(isChineseRules
                         ? "特殊事件會在擲豬前先行檢查。"
                         : "Special events are checked before a pig roll.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Spacer()
                        Button {
                            // 驗證 03 > 04 > 05 > 06
                            if !validateStrictOrder() {
                                // 還原舊值並提示
                                restoreOriginals()
                                showInvalidAlert = true
                            } else {
                                onApply()
                            }
                        } label: {
                            Label(isChineseRules ? "套用" : "Apply", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Probability")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.large)
                    }
                    .accessibilityLabel(isChineseRules ? "關閉" : "Close")
                }
            }
        }
        .onAppear {
            cacheOriginals()
            // 預設選中 Balanced 以顯示當前值接近預設
            selectedPreset = .balanced
        }
        .alert(isPresented: $showInvalidAlert) {
            Alert(
                title: Text(isChineseRules ? "無效的機率設定" : "Invalid probabilities"),
                message: Text(isChineseRules ? "必須滿足 03 > 04 > 05 > 06，已還原為原本設定。" : "Must satisfy 03 > 04 > 05 > 06. Reverted to original values."),
                dismissButton: .default(Text("OK"))
            )
        }
        .presentationDetents([.large])
    }
}

// MARK: - Pig detail model and view

private struct PigDetail: Identifiable, Equatable {
    enum Kind: Equatable {
        case pose(code: Int)          // 01...06
        case combo(p1: Int, p2: Int)  // two poses
        case special(asset: String)   // "08" or "09"
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let images: [String]     // asset names, e.g. ["01","06"] or ["08"]
    let pointsText: String   // e.g. "+15", "reset round", "total reset", "eliminated"
    let description: String  // localized explanation
}

private struct PigDetailView: View {
    let detail: PigDetail
    let isChineseRules: Bool
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Images
                    if detail.images.count == 1 {
                        Image(detail.images[0])
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240, maxHeight: 240)
                            .accessibilityLabel(detail.title)
                    } else if detail.images.count == 2 {
                        HStack(spacing: 24) {
                            Image(detail.images[0])
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 160, maxHeight: 160)
                            Image(detail.images[1])
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 160, maxHeight: 160)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(detail.title)
                    }

                    // Title
                    Text(detail.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    // Points / Penalty
                    Text(detail.pointsText)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    // Description
                    Text(detail.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
            .navigationTitle(isChineseRules ? "詳細介紹" : "Detail")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.large)
                    }
                    .accessibilityLabel(isChineseRules ? "關閉" : "Close")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Detail builders

private extension ContentView {
    func openDetailForPose(_ pose: Int) {
        let code = max(1, min(6, pose))
        let title = isChineseRules ? poseNameCN(code) : poseName(code)
        let pointsText = isChineseRules
            ? "此為單隻小豬姿勢，需與另一隻組合才會得分。"
            : "Single-pig pose. Scores only as part of a two-pig combination."
        let desc = isChineseRules
            ? "代號 \(String(format: "%02d", code))。與另一隻小豬的姿勢組合後，依規則表計分。"
            : "Code \(String(format: "%02d", code)). Scores depend on the two-pig combination per rules."
        selectedPigDetail = PigDetail(
            kind: .pose(code: code),
            title: title,
            images: [String(format: "%02d", code)],
            pointsText: pointsText,
            description: desc
        )
    }

    func openDetailForSpecial(_ asset: String) {
        let title: String
        let pointsText: String
        let desc: String

        if asset == "08" {
            title = isChineseRules ? "Oinker（08）" : "Oinker (08)"
            pointsText = isChineseRules ? "懲罰：總分歸零" : "Penalty: total reset"
            desc = isChineseRules
                ? "兩隻小豬相碰，觸發 Oinker。你的總分歸零，回合結束。"
                : "Both pigs touch each other: Oinker. Your total score resets to 0 and your turn ends."
        } else { // "09"
            title = isChineseRules ? "Piggy back（09）" : "Piggy back (09)"
            pointsText = isChineseRules ? "懲罰：淘汰" : "Penalty: eliminated"
            desc = isChineseRules
                ? "其中一隻小豬未碰到桌面，觸發 Piggy back。你被淘汰。"
                : "One pig doesn’t touch the table: Piggy back. You are eliminated."
        }

        selectedPigDetail = PigDetail(
            kind: .special(asset: asset),
            title: title,
            images: [asset],
            pointsText: pointsText,
            description: desc
        )
    }

    func openDetailForCombo(p1: Int, p2: Int, code: Int) {
        // Use existing scoring to get name/points, then localize
        let result = pigScoreFor(p1: p1, p2: p2)
        let name = isChineseRules ? comboNameCN(result.name) : result.name

        let title: String
        let pointsText: String
        let desc: String

        if code == 7 || result.bust {
            title = isChineseRules ? "Pig out（07）" : "Pig out (07)"
            pointsText = isChineseRules ? "懲罰：回合分數歸零" : "Penalty: round reset"
            desc = isChineseRules
                ? "組合 01 + 02（或 02 + 01）。本回合累積分數歸零，並換人。"
                : "Combination 01 + 02 (or 02 + 01). Your round score resets to 0 and your turn ends."
        } else {
            title = "\(name)"
            pointsText = isChineseRules ? "得分：+\(result.points)" : "Points: +\(result.points)"
            desc = isChineseRules
                ? "由 \(String(format: "%02d", p1)) 與 \(String(format: "%02d", p2)) 組成。依規則表，此組合可獲得 \(result.points) 分。"
                : "Made by \(String(format: "%02d", p1)) and \(String(format: "%02d", p2)). According to the rules, this earns \(result.points) points."
        }

        selectedPigDetail = PigDetail(
            kind: .combo(p1: p1, p2: p2),
            title: title,
            images: [String(format: "%02d", p1), String(format: "%02d", p2)],
            pointsText: pointsText,
            description: desc
        )
    }
}

#Preview {
    ContentView()
}
