import AppKit

final class StatusItemContentView: NSView {
    private let imageView = NSImageView()
    private let inputLabel = NSTextField(labelWithString: "")
    private let outputLabel = NSTextField(labelWithString: "")
    private let textStack = NSStackView()
    private let rootStack = NSStackView()

    private let horizontalPadding: CGFloat = 6
    private let verticalPadding: CGFloat = 2

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    func update(inputText: String, outputText: String) {
        inputLabel.stringValue = inputText
        outputLabel.stringValue = outputText
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        let stackSize = rootStack.fittingSize
        return NSSize(
            width: stackSize.width + horizontalPadding * 2,
            height: stackSize.height + verticalPadding * 2
        )
    }

    private func setupView() {
        wantsLayer = true

        imageView.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Mic")
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        imageView.contentTintColor = .labelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        inputLabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        inputLabel.textColor = .labelColor
        inputLabel.lineBreakMode = .byTruncatingTail
        inputLabel.usesSingleLineMode = true

        outputLabel.font = NSFont.systemFont(ofSize: 9, weight: .regular)
        outputLabel.textColor = .labelColor
        outputLabel.lineBreakMode = .byTruncatingTail
        outputLabel.usesSingleLineMode = true

        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 0
        textStack.addArrangedSubview(inputLabel)
        textStack.addArrangedSubview(outputLabel)

        rootStack.orientation = .horizontal
        rootStack.alignment = .centerY
        rootStack.spacing = 6
        rootStack.addArrangedSubview(imageView)
        rootStack.addArrangedSubview(textStack)

        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: verticalPadding),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalPadding)
        ])
    }
}
