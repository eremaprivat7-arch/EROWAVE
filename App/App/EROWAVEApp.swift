import SwiftUI
import SwiftData

@main @MainActor struct EROWAVEApp: App {
    let container: ModelContainer?
    @StateObject private var player=PlayerStore()
    init() {
        container=try? ModelContainer(for:CollectionRecord.self,configurations:ModelConfiguration(isStoredInMemoryOnly: ProcessInfo.processInfo.arguments.contains("-uiTest")))
    }
    var body: some Scene {
        WindowGroup {
            if let container { AppHost(context:container.mainContext).environmentObject(player).modelContainer(container).preferredColorScheme(.dark).tint(.white) }
            else { ContentUnavailableView("Library unavailable",systemImage:"externaldrive.badge.exclamationmark",description:Text("Check available storage, then reopen ERØWAVE.")) }
        }
    }
}
@MainActor struct AppHost: View {
    @StateObject var shelf:Shelf
    @EnvironmentObject var player:PlayerStore
    @Environment(\.scenePhase) var phase
    init(context:ModelContext) { _shelf=StateObject(wrappedValue:Shelf(context)) }
    var body:some View {
        RootView().environmentObject(shelf).onAppear { player.onHeard = { shelf.heard($0) } }
            .onChange(of:phase) { _,new in if new != .active { player.checkpoint() } }
            .alert("Library error",isPresented:Binding(get:{ shelf.error != nil },set:{ if !$0 { shelf.error=nil } })) { Button("OK",role:.cancel) {} } message:{ Text(shelf.error ?? "") }
    }
}
