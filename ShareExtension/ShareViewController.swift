import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private var sharedText: String = ""
    private var lists: [ItemList] = []
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        title = "Add to List"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancel)
        )

        // Load shared content
        extractSharedContent()

        // Load lists
        lists = loadLists()

        // Setup table
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func extractSharedContent() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] data, _ in
                        if let url = data as? URL {
                            self?.sharedText = url.absoluteString
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] data, _ in
                        if let text = data as? String {
                            self?.sharedText = text
                        }
                    }
                }
            }
        }
    }

    private func loadLists() -> [ItemList] {
        let dir = SharedContainer.listsDirectory
        SharedContainer.ensureDirectory()

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> ItemList? in
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return MarkdownParser.parse(content: content, filename: url.lastPathComponent)
            }
            .sorted { $0.title < $1.title }
    }

    private func addToList(_ list: ItemList) {
        var updated = list
        let text = sharedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            done()
            return
        }
        updated.items.insert(ListItem(text: text), at: 0)

        let content = MarkdownParser.write(updated)
        let url = SharedContainer.listsDirectory.appendingPathComponent(updated.filename)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        done()
    }

    @objc private func cancel() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func done() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

// MARK: - Table View

extension ShareViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        lists.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let list = lists[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = list.title
        config.secondaryText = "\(list.itemCount) items"
        config.image = UIImage(systemName: list.type == .checklist ? "checklist" : "list.bullet")
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        addToList(lists[indexPath.row])
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Choose a list"
    }
}
