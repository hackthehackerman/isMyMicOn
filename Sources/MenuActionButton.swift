import AppKit

final class MenuActionButton: NSButton {
    var representedObject: Any?

    private static let rowHeight: CGFloat = 22
    private static let leftPadding: CGFloat = 8
    private static let baseCheckmarkImage: NSImage = {
        let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 10, height: 10))
        image.isTemplate = true
        return image
    }()
    private static let checkmarkImage: NSImage = {
        let base = baseCheckmarkImage
        let size = NSSize(width: base.size.width + leftPadding, height: base.size.height)
        let image = NSImage(size: size, flipped: false) { rect in
            let y = (rect.height - base.size.height) / 2
            let drawRect = NSRect(x: leftPadding, y: y, width: base.size.width, height: base.size.height)
            base.draw(in: drawRect)
            return true
        }
        image.isTemplate = true
        return image
    }()
    private static let placeholderImage: NSImage = {
        let image = NSImage(size: checkmarkImage.size)
        image.isTemplate = true
        return image
    }()

    init(title: String, isChecked: Bool) {
        super.init(frame: .zero)
        setButtonType(.momentaryChange)
        isBordered = false
        focusRingType = .none
        alignment = .left
        font = NSFont.menuFont(ofSize: 0)
        imagePosition = .imageLeading
        imageHugsTitle = true
        lineBreakMode = .byTruncatingTail
        setChecked(isChecked)
        self.title = title
        sizeToFit()
        frame.size.height = Self.rowHeight
        frame.size.width = max(240, frame.size.width + 12)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func setChecked(_ isChecked: Bool) {
        image = isChecked ? Self.checkmarkImage : Self.placeholderImage
    }
}
