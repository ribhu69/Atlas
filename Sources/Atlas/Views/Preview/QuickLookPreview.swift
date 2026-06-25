import SwiftUI
import QuickLook

struct QuickLookPreview: UIViewControllerRepresentable {
    let item: FileItem
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let ql = QLPreviewController()
        ql.dataSource = context.coordinator
        ql.delegate = context.coordinator
        context.coordinator.item = item

        let nav = UINavigationController(rootViewController: ql)
        nav.navigationBar.prefersLargeTitles = false
        return nav
    }

    func updateUIViewController(_ uiVC: UINavigationController, context: Context) {
        context.coordinator.item = item
        if let ql = uiVC.viewControllers.first as? QLPreviewController {
            ql.reloadData()
        }
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        var item: FileItem?
        let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            PreviewItem(url: item?.url ?? URL(fileURLWithPath: ""), title: item?.name ?? "")
        }

        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            dismiss()
        }
    }

    private final class PreviewItem: NSObject, QLPreviewItem {
        let previewItemURL: URL?
        let previewItemTitle: String?

        init(url: URL, title: String) {
            self.previewItemURL = url
            self.previewItemTitle = title
        }
    }
}
