import AppKit
import ApplicationServices
import Foundation

enum SelectionProbe {
    private enum TextMarkerAttributes {
        static let selectedTextMarkerRange = "AXSelectedTextMarkerRange"
        static let selectedTextMarkerRanges = "AXSelectedTextMarkerRanges"
        static let stringForTextMarkerRange = "AXStringForTextMarkerRange"
    }

    private enum SelectionAvailability {
        case selected
        case notSelected
        case unsupported
    }

    static func selectedText() -> String? {
        for element in candidateElements() {
            if let selected = selectedText(from: element) {
                return selected
            }
        }

        return nil
    }

    static func hasSelectedText() -> Bool {
        selectionAvailability() == .selected
    }

    static func shouldShowReadButton() -> Bool {
        switch selectionAvailability() {
        case .selected, .unsupported:
            return true
        case .notSelected:
            return false
        }
    }

    private static func selectionAvailability() -> SelectionAvailability {
        var sawDefinitiveNoSelection = false

        for element in candidateElements() {
            if let selectedLength = selectedTextLength(from: element) {
                if selectedLength > 0 {
                    return .selected
                }
                sawDefinitiveNoSelection = true
            }

            if let selected = selectedText(from: element), !selected.isEmpty {
                return .selected
            }
        }

        if sawDefinitiveNoSelection {
            return .notSelected
        }

        return .unsupported
    }

    private static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func focusedElement() -> AXUIElement? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedResult == .success, let focusedValue else {
            return nil
        }
        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(focusedValue as AnyObject, to: AXUIElement.self)
    }

    private static func focusedApplication() -> AXUIElement? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        var appValue: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &appValue
        )
        guard appResult == .success, let appValue else {
            return nil
        }
        guard CFGetTypeID(appValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(appValue as AnyObject, to: AXUIElement.self)
    }

    private static func candidateElements() -> [AXUIElement] {
        var candidates: [AXUIElement] = []

        if let focusedElement = focusedElement() {
            appendIfUnique(focusedElement, to: &candidates)
            var current = focusedElement
            for _ in 0..<5 {
                guard let parent = parentElement(of: current) else {
                    break
                }
                appendIfUnique(parent, to: &candidates)
                current = parent
            }
        }

        if let appElement = focusedApplication() {
            appendIfUnique(appElement, to: &candidates)
        }

        return candidates
    }

    private static func appendIfUnique(_ element: AXUIElement, to elements: inout [AXUIElement]) {
        if elements.contains(where: { CFEqual($0, element) }) {
            return
        }
        elements.append(element)
    }

    private static func parentElement(of element: AXUIElement) -> AXUIElement? {
        var parentValue: CFTypeRef?
        let parentResult = AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &parentValue
        )
        guard parentResult == .success, let parentValue else {
            return nil
        }
        guard CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(parentValue as AnyObject, to: AXUIElement.self)
    }

    private static func selectedText(from element: AXUIElement) -> String? {
        if let selectedLength = selectedTextLength(from: element), selectedLength == 0 {
            return nil
        }

        if let fromTextMarkers = selectedTextFromTextMarkers(from: element) {
            return fromTextMarkers
        }

        if let direct = directSelectedText(from: element) {
            return direct
        }

        guard let selectedRange = firstSelectedRange(from: element),
              let fullValue = valueText(from: element)
        else {
            return nil
        }

        return substring(from: fullValue, in: selectedRange)
    }

    private static func selectedTextFromTextMarkers(from element: AXUIElement) -> String? {
        var markerRangeValue: CFTypeRef?
        let markerRangeResult = AXUIElementCopyAttributeValue(
            element,
            TextMarkerAttributes.selectedTextMarkerRange as CFString,
            &markerRangeValue
        )
        if markerRangeResult == .success,
           let markerRangeValue,
           let extracted = stringForTextMarkerRange(markerRangeValue, from: element)
        {
            return extracted
        }

        var markerRangesValue: CFTypeRef?
        let markerRangesResult = AXUIElementCopyAttributeValue(
            element,
            TextMarkerAttributes.selectedTextMarkerRanges as CFString,
            &markerRangesValue
        )
        guard markerRangesResult == .success,
              let markerRangesValue,
              let markerRanges = markerRangesValue as? [AnyObject]
        else {
            return nil
        }

        for markerRange in markerRanges {
            if let extracted = stringForTextMarkerRange(markerRange, from: element) {
                return extracted
            }
        }

        return nil
    }

    private static func stringForTextMarkerRange(_ markerRange: AnyObject, from element: AXUIElement) -> String? {
        var extractedValue: CFTypeRef?
        let extractedResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            TextMarkerAttributes.stringForTextMarkerRange as CFString,
            markerRange,
            &extractedValue
        )
        guard extractedResult == .success, let extractedValue else {
            return nil
        }

        if let extracted = extractedValue as? String {
            return normalized(extracted)
        }

        if let attributed = extractedValue as? NSAttributedString {
            return normalized(attributed.string)
        }

        return nil
    }

    private static func directSelectedText(from element: AXUIElement) -> String? {
        var selectedValue: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )
        guard selectedResult == .success, let selectedValue else {
            return nil
        }

        if let selected = selectedValue as? String {
            return normalized(selected)
        }

        if let attributed = selectedValue as? NSAttributedString {
            return normalized(attributed.string)
        }

        return nil
    }

    private static func firstSelectedRange(from element: AXUIElement) -> CFRange? {
        if let range = selectedRange(from: element),
           range.length > 0,
           range.location >= 0
        {
            return range
        }

        guard let ranges = selectedRanges(from: element) else {
            return nil
        }

        for range in ranges where range.length > 0 && range.location >= 0 {
            return range
        }

        return nil
    }

    private static func selectedTextLength(from element: AXUIElement) -> Int? {
        if let range = selectedRange(from: element) {
            return max(0, range.length)
        }

        guard let ranges = selectedRanges(from: element) else {
            return nil
        }

        for range in ranges where range.length > 0 && range.location >= 0 {
            return range.length
        }

        return 0
    }

    private static func selectedRange(from element: AXUIElement) -> CFRange? {
        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )
        guard rangeResult == .success,
              let rangeValue,
              CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = unsafeDowncast(rangeValue as AnyObject, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    private static func selectedRanges(from element: AXUIElement) -> [CFRange]? {
        var rangesValue: CFTypeRef?
        let rangesResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangesAttribute as CFString,
            &rangesValue
        )
        guard rangesResult == .success,
              let rangesValue,
              let ranges = rangesValue as? [AnyObject]
        else {
            return nil
        }

        var resolvedRanges: [CFRange] = []
        for candidate in ranges {
            guard CFGetTypeID(candidate) == AXValueGetTypeID()
            else {
                continue
            }
            let axValue = unsafeDowncast(candidate, to: AXValue.self)
            guard AXValueGetType(axValue) == .cfRange else {
                continue
            }

            var range = CFRange(location: 0, length: 0)
            if AXValueGetValue(axValue, .cfRange, &range) {
                resolvedRanges.append(range)
            }
        }

        return resolvedRanges
    }

    private static func valueText(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )
        guard result == .success, let value else {
            return nil
        }

        if let text = value as? String {
            return text
        }

        if let attributed = value as? NSAttributedString {
            return attributed.string
        }

        return nil
    }

    private static func substring(from text: String, in range: CFRange) -> String? {
        guard range.location >= 0, range.length > 0 else {
            return nil
        }

        let nsText = text as NSString
        let nsRange = NSRange(location: range.location, length: range.length)
        guard nsRange.location + nsRange.length <= nsText.length else {
            return nil
        }

        return normalized(nsText.substring(with: nsRange))
    }
}
