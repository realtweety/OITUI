#pragma once
#import <UIKit/UIKit.h>

FOUNDATION_EXPORT void OITTraverseViewHierarchy(UIView *root, void (^block)(UIView *view));
FOUNDATION_EXPORT UIView *OITFirstDescendantOfClass(UIView *root, Class targetClass);
FOUNDATION_EXPORT BOOL OITViewHasAncestorOfClass(UIView *view, Class ancestorClass);
