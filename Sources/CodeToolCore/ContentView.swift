import SwiftUI

public struct ContentView: View {
    @State private var selectedTool: Tool?
    private let tools = ToolRegistry.defaults

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(tools: tools, selectedTool: $selectedTool)
        } detail: {
            if let tool = selectedTool {
                ToolDetailView(tool: tool)
            } else {
                WelcomeView()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    let tools: [Tool]
    @Binding var selectedTool: Tool?

    var body: some View {
        List(tools, selection: $selectedTool) { tool in
            Label(tool.name, systemImage: tool.systemImage)
                .tag(tool)
        }
        .listStyle(.sidebar)
        .navigationTitle("CodeTool")
    }
}

// MARK: - Tool Detail

private struct ToolDetailView: View {
    let tool: Tool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: tool.systemImage)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundStyle(.tint)

            Text(tool.name)
                .font(.title)
                .fontWeight(.semibold)

            Text(tool.description)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(tool.name)
    }
}

// MARK: - Welcome

private struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hammer.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundStyle(.tint)

            Text("Welcome to CodeTool")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("A macOS developer toolkit for everyday coding tasks.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Text("Select a tool from the sidebar to get started.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
