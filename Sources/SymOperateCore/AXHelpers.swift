import ApplicationServices

func axCopyAttribute(_ element: AXUIElement, attribute: String) -> AnyObject? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success, let value else { return nil }
    return value
}

func axCopyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
    guard let value = axCopyAttribute(element, attribute: attribute) else { return nil }
    return (value as! AXUIElement)
}

func axCopyElements(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
    axCopyAttribute(element, attribute: attribute) as? [AXUIElement]
}

func axCopyString(_ element: AXUIElement, attribute: String) -> String? {
    axCopyAttribute(element, attribute: attribute) as? String
}

func axCopyFrame(_ element: AXUIElement) -> RectValue? {
    guard
        let positionValue = axCopyAttribute(element, attribute: kAXPositionAttribute),
        let sizeValue = axCopyAttribute(element, attribute: kAXSizeAttribute)
    else {
        return nil
    }

    var point = CGPoint.zero
    var size = CGSize.zero

    guard
        AXValueGetType(positionValue as! AXValue) == .cgPoint,
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
        AXValueGetType(sizeValue as! AXValue) == .cgSize,
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    else {
        return nil
    }

    return RectValue(x: point.x, y: point.y, width: size.width, height: size.height)
}

func axCopyActionNames(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    let result = AXUIElementCopyActionNames(element, &names)
    guard result == .success, let array = names as? [String] else { return [] }
    return array
}

func axStringify(_ value: AnyObject?) -> String? {
    switch value {
    case let string as String:
        return string
    case let number as NSNumber:
        return number.stringValue
    default:
        return nil
    }
}
