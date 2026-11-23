import SwiftUI

@main
struct MiNaApplication: App {
    @StateObject private var model = MiNaAppModel()

    var body: some Scene {
        WindowGroup {
            MiNaRoot().environmentObject(model)
        }
    }
}
