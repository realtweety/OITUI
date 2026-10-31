// OITIIslandHooks.xm -- the Island's position, size, scale and appearance (OITI).
//
// Moved from Tweak.xm unchanged in the v0.3.0 module split (round 3, IslandSize): the position helpers (Island and banner),
// Apple's canvas scale, the size multipliers and the OITIHooks group (SBSystemApertureWindow, the curtain, gain map and
// content view, the touch pass-through view, SBBannerWindow, SBUISystemApertureLayoutMetrics). The settings these read are
// still defined in Tweak.xm (declared in Shared/OITIShared.h); the preferences reload there writes them.
//
// A Logos group can only be initialised in the file that defines it, so OITIInstallIslandSizeHooks at the end of this
// file does the %init and the %ctor in Tweak.xm calls it where it used to say %init(OITIHooks).

#import "Shared/OITIShared.h"
#import "IslandSize/OITIIslandSize.h"
#import "Diagnostics/OITIDiagnostics.h"

static const void *kOITIAppliedScaleKey = &kOITIAppliedScaleKey;
static const void *kOITIHiddenByUsKey = &kOITIHiddenByUsKey;
static const void *kOITIColorAppliedKey = &kOITIColorAppliedKey;
// Island transparency and outline hiding: the alpha OITI last set on a view / a flag that OITI hid it, so a changed
// or switched-off setting applies live without fighting Apple's own changes to the same view.
static const void *kOITITransparencyAppliedKey = &kOITITransparencyAppliedKey;
static const void *kOITILineHiddenKey = &kOITILineHiddenKey;
static const void *kOITIPassThroughTouchedKey = &kOITIPassThroughTouchedKey;

static CGFloat OITISafeScaleValue(CGFloat value) {
    if (!isfinite(value)) return 1.0;
    if (value < 0.05) return 1.0;
    if (value > 3.0) return 3.0;
    return value;
}

// Apple's own scale for the Island window: its canvas (360 x 640 on the 8 Plus) is stretched to the screen width by a
// uniform transform (1.15 there). Setting a transform replaces Apple's, so a scale relative to stock multiplies this
// back in. The shorter sides are compared so it holds in either orientation. Falls back to 1.0 if the numbers are
// not sane.
static CGFloat OITIAppleCanvasScale(UIView *window) {
    CGSize canvas = window.bounds.size;
    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGFloat canvasSide = MIN(canvas.width, canvas.height);
    CGFloat screenSide = MIN(screen.width, screen.height);
    if (canvasSide < 1.0 || screenSide < 1.0) return 1.0;
    CGFloat factor = screenSide / canvasSide;
    return (isfinite(factor) && factor >= 0.5 && factor <= 3.0) ? factor : 1.0;
}

// =============================================================================================
// MARK: Island position (unchanged from Step 1)
// =============================================================================================

// Moves the Island window to the built-in (fixEnabled) or custom (posEnabled) position.
// The built-in table wins when both are on, as before. On a device with no table entry, "fixEnabled" falls back
// to the custom position.
static void OITIApplyIslandPosition(UIView *window) {
    CGFloat sx = scaleEnabled ? OITISafeScaleValue(scaleX) : 1.0;
    CGFloat sy = scaleEnabled ? OITISafeScaleValue(scaleY) : 1.0;
    CGRect frame = window.frame;
    const OITIDeviceProfile *profile = fixEnabled ? OITICurrentProfile() : NULL;

    if (profile) {
        frame.origin.y = profile->islandY / sy;
    } else if (posEnabled) {
        frame.origin.y = yPos / sy;
        // Original behavior: with scaling on, only override x when it is set; without scaling, always set it.
        if (!scaleEnabled || xPos > 0) frame.origin.x = xPos / sx;
    } else {
        return;
    }

    if (!CGRectEqualToRect(frame, window.frame)) window.frame = frame;
}

// Notification banner window position. Returns YES and fills `out` when an override applies.
//  - notificationFix: use the device's built-in banner position. Devices with no table entry are left untouched.
//  - notEnabled: custom origin (xNot, yNot); devices with no table entry keep the system's size.
static BOOL OITIBannerFrame(CGRect incoming, CGRect *out) {
    const OITIDeviceProfile *profile = OITICurrentProfile();
    if (notificationFix) {
        if (!profile) return NO;
        *out = CGRectMake(0, profile->bannerY, profile->bannerWidth, profile->bannerHeight);
        return YES;
    }
    if (notEnabled) {
        CGSize size = profile ? CGSizeMake(profile->bannerWidth, profile->bannerHeight) : incoming.size;
        *out = CGRectMake(xNot, yNot, size.width, size.height);
        return YES;
    }
    return NO;
}

// =============================================================================================
// MARK: Hooks
// =============================================================================================

// Experimental Island size multipliers: keep them in a range that cannot collapse or explode the layout.
CGFloat OITIClampMetricsFactor(CGFloat value) {
    if (!isfinite(value)) return 1.0;
    return MAX(0.3, MIN(2.0, value));
}

static CGSize OITIApplyMetricsFactor(CGSize size, CGFloat factorX, CGFloat factorY) {
    if (factorX == 1.0 && factorY == 1.0) return size;   // exact pass-through when unused
    return CGSizeMake(size.width * factorX, size.height * factorY);
}

%group OITIHooks

%hook SBSystemApertureWindow

- (void)layoutSubviews {
    CGRect before = self.frame;

    if (scaleEnabled) {
        CGFloat appleScale = OITIAppleCanvasScale(self);
        CGAffineTransform wanted = CGAffineTransformMakeScale(appleScale * OITISafeScaleValue(scaleX),
                                                              appleScale * OITISafeScaleValue(scaleY));
        if (!CGAffineTransformEqualToTransform(self.transform, wanted)) self.transform = wanted;
        objc_setAssociatedObject(self, kOITIAppliedScaleKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (objc_getAssociatedObject(self, kOITIAppliedScaleKey)) {
        // Turning scaling off resets the old transform live.
        self.transform = CGAffineTransformIdentity;
        objc_setAssociatedObject(self, kOITIAppliedScaleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    %orig;
    CGRect afterOrig = self.frame;
    OITIApplyIslandPosition(self);

    if (![sLiveApertureWindows containsObject:self]) [sLiveApertureWindows addObject:self];

    if ([sLog isLoggingAtLevel:1]) {
        [sApertureWindows addObject:self];
        OITIScheduleAutoDump();
        NSString *signature = [NSString stringWithFormat:@"frame=%@ bounds=%@ xf=%@ fix=%d pos=%d scale=%d sx=%.3f sy=%.3f",
                               NSStringFromCGRect(self.frame), NSStringFromCGRect(self.bounds),
                               NSStringFromCGAffineTransform(self.transform),
                               fixEnabled, posEnabled, scaleEnabled, scaleX, scaleY];
        if ([sLog noteSignature:signature forObject:self]) {
            [sLog logLevel:1 tag:@"ISLAND" format:@"%@@%p changed: %@ (profile=%d)",
             NSStringFromClass([self class]), self, signature, OITICurrentProfile() != NULL];
        }
    }
    OITLOGGER_LOG_RATED(sLog, 2, @"LAYOUT", @"island.layout", 5,
                        @"before=%@ afterOrig=%@ final=%@",
                        NSStringFromCGRect(before), NSStringFromCGRect(afterOrig), NSStringFromCGRect(self.frame));
}

%end

%hook _SBSystemApertureMagiciansCurtainView

- (void)didMoveToWindow {
    %orig;
    BOOL shouldHide = fixEnabled || posEnabled || scaleEnabled;
    if (shouldHide) {
        if (!self.hidden) self.hidden = YES;
        objc_setAssociatedObject(self, kOITIHiddenByUsKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (objc_getAssociatedObject(self, kOITIHiddenByUsKey)) {
        // Only undo our own hiding, instead of force-unhiding a view Apple may have hidden itself.
        self.hidden = NO;
        objc_setAssociatedObject(self, kOITIHiddenByUsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    OITLOGGER_LOG_RATED(sLog, 1, @"CURTAIN", @"curtain", 4,
                        @"%@@%p didMoveToWindow window=%@ shouldHide=%d hidden=%d ours=%d",
                        NSStringFromClass([self class]), self, self.window ? @"yes" : @"no", shouldHide,
                        self.hidden, objc_getAssociatedObject(self, kOITIHiddenByUsKey) != nil);
}

%end

%hook _SBGainMapView

- (void)didMoveToWindow {
    %orig;
    if (hideEnabled && self.superview) {
        OITLOGGER_LOG(sLog, 1, @"GAINMAP", @"%@@%p removed from %@",
                      NSStringFromClass([self class]), self, NSStringFromClass([self.superview class]));
        [self removeFromSuperview];
    }
}

%end

%hook _SBSystemApertureContainerViewContentView

- (void)layoutSubviews {
    UIColor *backgroundColor = [self backgroundColor];
    BOOL ours = objc_getAssociatedObject(self, kOITIColorAppliedKey) != nil;

    if (colorEnabled) {
        // Only touch the color when nothing set one, or when the color is the one we applied earlier
        // (so changing the color in prefs takes effect without a respring).
        if (!backgroundColor || ours) {
            UIColor *customColor = [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
            if (!backgroundColor || ![backgroundColor isEqual:customColor]) {
                [self setBackgroundColor:customColor];
                OITLOGGER_LOG_RATED(sLog, 1, @"COLOR", @"color.apply", 4,
                                    @"%@@%p background %@ -> %@", NSStringFromClass([self class]), self,
                                    OITIColorDesc(backgroundColor), OITIColorDesc(customColor));
            }
            objc_setAssociatedObject(self, kOITIColorAppliedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else {
            OITLOGGER_LOG_RATED(sLog, 2, @"COLOR", @"color.skip", 2,
                                @"%@@%p not overriding: something else set %@",
                                NSStringFromClass([self class]), self, OITIColorDesc(backgroundColor));
        }
    } else if (ours) {
        [self setBackgroundColor:nil];
        objc_setAssociatedObject(self, kOITIColorAppliedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        OITLOGGER_LOG(sLog, 1, @"COLOR", @"%@@%p color override removed", NSStringFromClass([self class]), self);
    }
    %orig;
}

%end

%hook SBFTouchPassThroughView

- (void)layoutSubviews {
    %orig;

    // An instance OITI changed earlier must still be visited when the setting is switched off, so it can be restored.
    if (!transEnabled && !lineDisabled && !objc_getAssociatedObject(self, kOITIPassThroughTouchedKey)) return;

    // SBFTouchPassThroughView is used pervasively throughout SpringBoard (Dock, folders, notification banners,
    // home screen icons, etc.), and the subviews.count == 4 heuristic below is NOT specific enough on its own.
    // Scoping to instances actually inside SBSystemApertureWindow avoids matching unrelated views.
    // KNOWN FRAGILE: the index-based subview picks may change between iOS versions.
    static Class apertureWindowClass;
    if (!apertureWindowClass) apertureWindowClass = NSClassFromString(@"SBSystemApertureWindow");
    if (!apertureWindowClass || !OITViewHasAncestorOfClass(self, apertureWindowClass)) return;

    NSUInteger subviewCount = self.subviews.count;
    if (subviewCount != 4) {
        // The heuristic did not match an Island-scoped instance. Log when the count changes, so a miss shows up.
        if ([sLog isLoggingAtLevel:1] &&
            [sLog noteSignature:[NSString stringWithFormat:@"miss:%lu", (unsigned long)subviewCount] forObject:self]) {
            [sLog logLevel:1 tag:@"TOUCHPASS" format:@"%@@%p inside the Island window has %lu subview(s), not 4: transparency/line hiding NOT applied",
             NSStringFromClass([self class]), self, (unsigned long)subviewCount];
        }
        return;
    }

    // Transparency. A view is OITI's to change when it is untouched (alpha 1.0, as before) or still carries the alpha
    // OITI set earlier (so a new opacity applies live). If something else changed the alpha since, it is left alone.
    UIView *targetSubview = self.subviews[2];
    NSNumber *appliedAlpha = objc_getAssociatedObject(targetSubview, kOITITransparencyAppliedKey);
    BOOL carriesOurAlpha = appliedAlpha && fabs(targetSubview.alpha - appliedAlpha.doubleValue) < 0.001;
    if (transEnabled) {
        BOOL untouched = targetSubview.alpha == 1.0 && targetSubview.userInteractionEnabled == 0;
        if (untouched || carriesOurAlpha) {
            if (fabs(targetSubview.alpha - alpha) > 0.001) {
                targetSubview.alpha = alpha;
                OITLOGGER_LOG_RATED(sLog, 2, @"TOUCHPASS", @"touchpass.trans", 4,
                                    @"transparency applied alpha=%.2f to %@", alpha, NSStringFromClass([targetSubview class]));
            }
            objc_setAssociatedObject(targetSubview, kOITITransparencyAppliedKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else if (appliedAlpha) {
        if (carriesOurAlpha) targetSubview.alpha = 1.0;
        objc_setAssociatedObject(targetSubview, kOITITransparencyAppliedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // Outline.
    UIView *lineView = self.subviews[1];
    BOOL lineIsOurs = objc_getAssociatedObject(lineView, kOITILineHiddenKey) != nil;
    if (lineDisabled) {
        if (lineIsOurs || (lineView.alpha == 1.0 && lineView.userInteractionEnabled == 0)) {
            if (!lineView.hidden) {
                lineView.hidden = YES;
                OITLOGGER_LOG_RATED(sLog, 2, @"TOUCHPASS", @"touchpass.line", 4,
                                    @"line hidden: %@", NSStringFromClass([lineView class]));
            }
            objc_setAssociatedObject(lineView, kOITILineHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else if (lineIsOurs) {
        lineView.hidden = NO;
        objc_setAssociatedObject(lineView, kOITILineHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    BOOL touched = objc_getAssociatedObject(targetSubview, kOITITransparencyAppliedKey) != nil ||
                   objc_getAssociatedObject(lineView, kOITILineHiddenKey) != nil;
    objc_setAssociatedObject(self, kOITIPassThroughTouchedKey, touched ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%end

%hook SBBannerWindow

- (CGRect)frame {
    CGRect original = %orig;
    CGRect overridden;
    return OITIBannerFrame(original, &overridden) ? overridden : original;
}

- (void)setFrame:(CGRect)frame {
    CGRect overridden;
    BOOL didOverride = OITIBannerFrame(frame, &overridden);
    CGRect used = didOverride ? overridden : frame;

    [sBannerWindows addObject:self];   // always kept (weak): the Island notification path needs the banner window
    if ([sLog isLoggingAtLevel:1]) {
        NSString *signature = [NSString stringWithFormat:@"in=%@ used=%@ ov=%d", NSStringFromCGRect(frame),
                               NSStringFromCGRect(used), didOverride];
        if ([sLog noteSignature:signature forObject:self]) {
            [sLog logLevel:1 tag:@"BANNER" format:@"%@@%p setFrame %@ (notificationFix=%d custom=%d profile=%d)",
             NSStringFromClass([self class]), self, signature, notificationFix, notEnabled, OITICurrentProfile() != NULL];
        }
    }
    %orig(used);
}

%end

// The root input Apple builds the Island from. Returns Apple's value times the Island Size multipliers (both 1.0 by
// default, which is an exact pass-through). The raw value is kept for the dump.
%hook SBUISystemApertureLayoutMetrics

- (CGSize)sensorRegionSize {
    CGSize size = %orig;
    sRawSensorRegionSize = size;
    return OITIApplyMetricsFactor(size, sMetricsSensorX, sMetricsSensorY);
}

%end

%end

void OITIInstallIslandSizeHooks(void) {
    %init(OITIHooks);
}
