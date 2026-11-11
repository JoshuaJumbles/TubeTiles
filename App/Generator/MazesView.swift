import SwiftUI
import TubeKit

/// The saved mazes: save the one being worked on, and open, rename or delete
/// earlier ones.
struct MazesView: View {
    var model: GeneratorModel
    var archive: MazeArchive

    @Environment(\.dismiss) private var dismiss
    @State private var renaming: SavedMaze?
    @State private var newName = ""
    @State private var deleting: SavedMaze?
    @State private var opening: SavedMaze?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    current

                    if archive.mazes.isEmpty {
                        Text("Saved mazes appear here.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else {
                        Text("Saved").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 14)], spacing: 14) {
                            ForEach(archive.mazes) { saved in
                                card(for: saved)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(TilePalette.paper.ignoresSafeArea())
            .navigationTitle("Mazes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename maze", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Rename") {
                    if let renaming { try? archive.rename(id: renaming.id, to: newName) }
                    renaming = nil
                }
            }
        }
    }

    /// The maze on the generator right now, and what can be done with it.
    private var current: some View {
        let saved = archive.maze(id: model.documentID)
        let isEmpty = model.maze.cells.isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                MazeThumbnail(maze: model.maze)
                    .frame(width: 96)
                VStack(alignment: .leading, spacing: 3) {
                    Text(saved?.name ?? "Not saved yet").font(.headline)
                    Text(status(saved: saved, isEmpty: isEmpty))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button { model.save() } label: {
                    Label(saved == nil ? "Save" : "Save changes", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isEmpty || (saved != nil && !model.hasUnsavedChanges))

                if saved != nil {
                    Button { model.saveAsNew() } label: {
                        Label("Save as new", systemImage: "plus.square.on.square").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isEmpty)
                }
            }

            Button {
                model.startNewMaze()
                dismiss()
            } label: {
                Label("Start a new maze", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isEmpty && saved == nil)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(TilePalette.face))
    }

    private func status(saved: SavedMaze?, isEmpty: Bool) -> String {
        if isEmpty { return "Nothing on the generator yet." }
        if saved == nil { return "\(model.maze.cells.count) tiles. It will still be here next time, but saving keeps it for good." }
        return model.hasUnsavedChanges ? "Changed since it was saved." : "Saved."
    }

    private func card(for saved: SavedMaze) -> some View {
        let isCurrent = saved.id == model.documentID
        return Button {
            if model.hasUnsavedChanges && !model.maze.cells.isEmpty && !isCurrent {
                opening = saved
            } else {
                model.open(saved)
                dismiss()
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                MazeThumbnail(maze: saved.maze)
                Text(saved.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(saved.maze.cells.count) tiles · \(saved.modified.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14).fill(TilePalette.face))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isCurrent ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                newName = saved.name
                renaming = saved
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) { deleting = saved } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        // Attached to the card so each prompt appears beside it.
        .confirmationDialog(
            "Delete \u{201C}\(saved.name)\u{201D}?",
            isPresented: Binding(get: { deleting?.id == saved.id }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                model.delete(saved)
                deleting = nil
            }
        } message: {
            Text("The saved maze will be removed. This cannot be undone.")
        }
        .confirmationDialog(
            "Open \u{201C}\(saved.name)\u{201D}?",
            isPresented: Binding(get: { opening?.id == saved.id }, set: { if !$0 { opening = nil } }),
            titleVisibility: .visible
        ) {
            Button("Open and discard changes", role: .destructive) {
                model.open(saved)
                opening = nil
                dismiss()
            }
        } message: {
            Text("The maze on the generator has changes that are not saved.")
        }
        .accessibilityLabel("\(saved.name), \(saved.maze.cells.count) tiles")
    }
}
