import func SwiftUI.__designTimeFloat
import func SwiftUI.__designTimeString
import func SwiftUI.__designTimeInteger
import func SwiftUI.__designTimeBoolean

#sourceLocation(file: "/Volumes/C/project/Pomodoro/Pomodoro/ContentView.swift", line: 1)
//
//  ContentView.swift
//  Pomodoro
//
//  Created by 정성원 on 8/1/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                    } label: {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationSplitViewColumnWidth(min: __designTimeInteger("#8345_0", fallback: 180), ideal: __designTimeInteger("#8345_1", fallback: 200))
            .toolbar {
                ToolbarItem {
                    Button(action: addItem) {
                        Label(__designTimeString("#8345_2", fallback: "Add Item"), systemImage: __designTimeString("#8345_3", fallback: "plus"))
                    }
                }
            }
        } detail: {
            Text(__designTimeString("#8345_4", fallback: "Select an item"))
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: __designTimeBoolean("#8345_5", fallback: true))
}
