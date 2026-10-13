import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct FrankApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @StateObject private var link = MacLink()
    @StateObject private var library: ModelLibrary
    @StateObject private var live: LiveVoice
    @StateObject private var store = SessionStore()
    @State private var showApp = false
    @State private var showEarsSetup = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var animator = FaceAnimator()
    @State private var showPairing = true
    @State private var holdStart: DispatchWorkItem?
    @State private var holdingToAsk = false

    init() {
        let library = ModelLibrary()
        _library = StateObject(wrappedValue: library)
        _live = StateObject(wrappedValue: LiveVoice(ears: Ears(library: library)))
    }

    var body: some View {
        ZStack {
            FaceView(animator: animator)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { live.toggle() }  // double tap: wake up / back to follow mode
                .simultaneousGesture(holdToAsk)

            ModeIndicator(state: live.state)

            SoundButton(link: link, live: live)

            // Frank's app: sessions, transcripts and settings.
            Button { showApp = true } label: {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.06)).frame(width: 34, height: 34))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Frank")
            .padding(.top, 10)
            .padding(.trailing, 62)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if showPairing && !link.connected {
                PairingView { withAnimation(.easeOut(duration: 0.3)) { showPairing = false } }
                    .transition(.opacity)
            }

        }
        .background(Color.black)
        .ignoresSafeArea()
        .phoneChrome()
        .sheet(isPresented: $showEarsSetup) {
            EarsSetupView(library: library) {
                showEarsSetup = false
                live.wake()
            } onClose: {
                showEarsSetup = false
            }
        }
        .fullScreenCover(isPresented: $showApp) {
            FrankAppView(store: store, live: live, link: link, library: library) { showApp = false }
        }
        .onAppear {
            link.onFace = { [animator] face in animator.receive(face, at: Date().timeIntervalSinceReferenceDate) }
            animator.localTalk = { [live] in live.level }
            wireLiveVoice()
            link.start()
            #if DEBUG
            // For screenshots: launch with `-FrankScreen app|ears|setup` to open a screen directly.
            switch UserDefaults.standard.string(forKey: "FrankScreen") {
            case "app", "ears": showPairing = false; showApp = true
            case "setup": showPairing = false; showEarsSetup = true
            default: break
            }
            #endif
        }
        .onChange(of: link.connected) { _, connected in
            if connected { withAnimation(.easeOut(duration: 0.4)) { showPairing = false } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { link.start() } else if phase == .background { link.stop() }
        }
    }

    /// Press and hold the screen to ask him something; let go and he answers.
    private var holdToAsk: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard holdStart == nil, !holdingToAsk else { return }
                let work = DispatchWorkItem {
                    holdingToAsk = true
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    #endif
                    live.beginAsk()
                }
                holdStart = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)  // a quick tap isn't a hold
            }
            .onEnded { _ in
                holdStart?.cancel()
                holdStart = nil
                if holdingToAsk {
                    holdingToAsk = false
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    live.endAsk()
                }
            }
    }

    /// Connects the live voice to the Mac: keys, tools, captions and wake/sleep.
    private func wireLiveVoice() {
        live.requestToken = { [link] done in
            link.request(Packet(command: "realtimeToken")) { reply in done(reply?.text) }
        }
        live.runTool = { [link] name, arguments, done in
            link.request(Packet(command: "tool", tool: name, text: arguments)) { reply in
                done(reply?.text ?? "The Mac didn't answer.", reply?.image)
            }
        }
        live.onSessionStart = { [store] in store.start() }
        live.resumeContext = { [store] in store.recentText() }
        live.onNeedsEars = { showEarsSetup = true }
        live.onSessionEnd = { [store] in store.end() }
        live.onUserTurn = { [store] item, asked in store.placeholder(itemID: item, asked: asked) }
        live.onUserWords = { [store] item, text, asked in store.heard(itemID: item, text: text, asked: asked) }
        live.onReply = { [store] text in store.reply(text) }
        live.onReport = { [store] text in store.report(text) }
        live.onCaption = { [link] text, finished in
            link.send(Packet(command: finished ? "captionDone" : "caption", text: text))
        }
        live.onStateChange = { [link, animator] state in
            switch state {
            case .asleep:
                animator.awake = false
                animator.localMood = nil
                link.send(Packet(command: "asleep"))
            case .waking:
                animator.awake = true
                animator.localMood = .happy
            case .listening:
                animator.awake = true
                animator.localMood = nil
                link.send(Packet(command: "awake"))
            case .asking:
                animator.awake = true
                animator.localMood = .listening  // all ears while you hold
                link.send(Packet(command: "awake"))
            case .thinking:
                animator.localMood = .thinking
            case .speaking:
                animator.localMood = .talking
            }
        }
        link.onCommand = { [live] command in
            switch command {
            case "wake": live.wake()
            case "sleep": live.sleep()
            default: break
            }
        }
    }
}

private extension View {
    /// Hides the status bar and home indicator and keeps the screen awake.
    func phoneChrome() -> some View {
        #if os(iOS)
        return self
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        #else
        return self
        #endif
    }
}
