#import <OITCore/OITViewUtilities.h>

void OITTraverseViewHierarchy(UIView *root, void (^block)(UIView *view)) {
    if (!root || !block) return;
    block(root);
    for (UIView *subview in root.subviews) {
        OITTraverseViewHierarchy(subview, block);
    }
}

UIView *OITFirstDescendantOfClass(UIView *root, Class targetClass) {
    if (!root || !targetClass) return nil;
    if ([root isKindOfClass:targetClass]) return root;
    for (UIView *subview in root.subviews) {
        UIView *match = OITFirstDescendantOfClass(subview, targetClass);
        if (match) return match;
    }
    return nil;
}

BOOL OITViewHasAncestorOfClass(UIView *view, Class ancestorClass) {
    UIView *ancestor = view.superview;
    while (ancestor) {
        if ([ancestor isKindOfClass:ancestorClass]) return YES;
        ancestor = ancestor.superview;
    }
    return NO;
}
