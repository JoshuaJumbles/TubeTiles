import CoreTransferable
import PDFKit
import SwiftUI
import TubeKit
import UniformTypeIdentifiers

/// A finished build sheet, ready to share or print.
struct BuildSheetFile: Transferable {
    var data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }
            .suggestedFileName("TubeTiles build sheet.pdf")
    }
}

/// Shows a maze's build sheet with its few settings, and shares it.
struct BuildSheetView: View {
    let maze: Maze

    @Environment(\.dismiss) private var dismiss
    @State private var options = BuildSheetPDF.Options()
    @State private var data = Data()

    private var pageCount: Int {
        PDFDocument(data: data)?.pageCount ?? 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PDFPreview(data: data)
                    .ignoresSafeArea(edges: .horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    Stepper(
                        value: $options.tileInches, in: BuildSheetPDF.Options.sizeRange, step: 0.25
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tiles \(BuildSheetPDF.inches(options.tileInches)) flat to flat")
                            Text(String(format: "%.1f cm · US Letter, ", options.tileInches * 2.54)
                                + (pageCount == 1 ? "1 page" : "\(pageCount) pages"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $options.flippedIsSame) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("A flipped tile is the same tile")
                            Text("For stencils you can turn over. Leave off for painted tiles.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .background(.background)
            }
            .navigationTitle("Build sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: BuildSheetFile(data: data), preview: SharePreview("TubeTiles build sheet.pdf")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(data.isEmpty)
                }
            }
            .task(id: options) {
                data = BuildSheetPDF.render(maze: maze, options: options)
            }
        }
    }
}

private struct PDFPreview: UIViewRepresentable {
    var data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        // Only when the sheet itself changed, so scrolling is not reset by
        // unrelated updates.
        guard view.document?.dataRepresentation() != data else { return }
        view.document = PDFDocument(data: data)
    }
}
