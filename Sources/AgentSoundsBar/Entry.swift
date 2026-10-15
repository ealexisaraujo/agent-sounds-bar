import SwiftUI

@main
enum Entry {
    static func main() {
        if CLI.runIfRequested() { return }
        AgentSoundsBarApp.main()
    }
}
