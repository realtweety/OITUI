// OITINoticeViews.xm -- the views inside a notification element (OITI Island notifications).
//
// Moved from Tweak.xm unchanged in the v0.3.0 module split (round 4, IslandNotifications).
// The stack view, the expanded and compact notice views, the newest-notice refresh and the corner-radius handling.

#import "Shared/OITIShared.h"
#import "IslandNotifications/OITIIslandNotifications.h"

NSString *OITIShortText(NSString *text, NSUInteger limit) {
    if (!text.length) return @"";
    NSString *flat = [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return flat.length > limit ? [[flat substringToIndex:limit] stringByAppendingString:@"…"] : flat;
}

// Pulls what we need out of an NCNotificationRequest without a header: every access is looked up at run time.
NSDictionary<NSString *, NSString *> *OITINoticeInfoFromRequest(id request) {
    id content = OITISafeObject(request, @"content");
    NSString *bundleID = OITISafeString(request, @"sectionIdentifier") ?: OITISafeString(request, @"bundleIdentifier") ?: @"";
    NSString *appName = OITISafeString(content, @"header") ?: @"";
    NSString *title = OITISafeString(content, @"title") ?: @"";
    NSString *subtitle = OITISafeString(content, @"subtitle") ?: @"";
    NSString *message = OITISafeString(content, @"message") ?: @"";
    return @{ @"bundleID": bundleID, @"appName": appName, @"title": title, @"subtitle": subtitle, @"message": message };
}

static UIImage *OITIRoundedIcon(UIImage *image, CGFloat side) {
    if (!image) return nil;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGRect bounds = CGRectMake(0, 0, side, side);
        [[UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:side * 0.225] addClip];
        [image drawInRect:bounds];
    }];
}

// The two views of the compact element, like the lock element's leading and trailing views: the app icon on the left
// and a short label on the right. Both are sized (frame = what they need) because Apple asks them sizeThatFits.

@implementation OITINoticeStackView
- (CGSize)sizeThatFits:(CGSize)size {
    CGFloat width = size.width > 0 ? MIN(size.width, 260.0) : 260.0;
    CGSize target = CGSizeMake(width, UILayoutFittingCompressedSize.height);
    CGSize fitted = [self systemLayoutSizeFittingSize:target
                       withHorizontalFittingPriority:UILayoutPriorityRequired
                             verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    return CGSizeMake(width, ceil(fitted.height));
}
@end

void OITIBuildNoticeViews(NSDictionary<NSString *, NSString *> *info, UIView **leadingOut, UIView **trailingOut,
                                 UIView **primaryOut, UIView **secondaryOut, UILabel **secondaryBodyOut) {
    NSString *bundleID = info[@"bundleID"] ?: @"";
    NSString *title = info[@"title"] ?: @"";
    NSString *subtitle = info[@"subtitle"] ?: @"";
    NSString *message = info[@"message"] ?: @"";
    NSString *appName = info[@"appName"] ?: @"";
    if (!appName.length && bundleID.length) appName = [bundleID componentsSeparatedByString:@"."].lastObject ?: @"";

    // Headline and body. No title: the app name becomes the headline, or the message itself if there is no app name either.
    NSString *headline = title.length ? title : (appName.length ? appName : message);
    NSString *body = message;
    if (subtitle.length) body = message.length ? [NSString stringWithFormat:@"%@: %@", subtitle, message] : subtitle;
    if (!title.length && !appName.length) body = @"";   // the message already is the headline

    UIImage *icon = nil;
    if (bundleID.length && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0 scale:[UIScreen mainScreen].scale];
    }
    UIImage *small = OITIRoundedIcon(icon, 22);
    UIView *leading;
    if (small) {
        UIImageView *iconView = [[UIImageView alloc] initWithImage:small];
        iconView.frame = CGRectMake(0, 0, 22, 22);
        leading = iconView;
    } else {
        UILabel *initial = [[UILabel alloc] init];
        initial.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        initial.textColor = [UIColor whiteColor];
        NSString *name = appName.length ? appName : headline;
        initial.text = name.length ? [name substringToIndex:1] : @"•";
        [initial sizeToFit];
        leading = initial;
    }

    UILabel *trailing = [[UILabel alloc] init];
    trailing.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    trailing.textColor = [UIColor whiteColor];
    trailing.text = OITIShortText(headline, 12);
    [trailing sizeToFit];

    // Expanded layouts (primary / secondary): the headline and the message, like Apple's own expanded alerts.
    UILabel *primary = [[UILabel alloc] init];
    primary.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    primary.textColor = [UIColor whiteColor];
    primary.lineBreakMode = NSLineBreakByTruncatingTail;
    primary.text = headline;
    CGSize primarySize = [primary sizeThatFits:CGSizeMake(260, CGFLOAT_MAX)];
    primary.frame = CGRectMake(0, 0, MIN(260, ceil(primarySize.width)), ceil(primarySize.height));

    NSInteger lines = MAX(1, MIN(4, lround([sOITIPreferences floatForKey:@"IslandNotificationsMessageLines" default:2])));
    UILabel *secondary = [[UILabel alloc] init];
    secondary.font = [UIFont systemFontOfSize:13];
    secondary.textColor = [UIColor colorWithWhite:1.0 alpha:0.8];
    secondary.numberOfLines = lines;
    secondary.lineBreakMode = NSLineBreakByTruncatingTail;
    secondary.text = body;
    secondary.preferredMaxLayoutWidth = 260;
    OITINoticeStackView *secondaryStack = [OITINoticeStackView new];
    secondaryStack.axis = UILayoutConstraintAxisVertical;
    secondaryStack.alignment = UIStackViewAlignmentFill;
    secondaryStack.distribution = UIStackViewDistributionFill;
    secondaryStack.spacing = 8;
    [secondaryStack addArrangedSubview:secondary];
    CGSize secondarySize = [secondaryStack sizeThatFits:CGSizeMake(260, CGFLOAT_MAX)];
    secondaryStack.frame = CGRectMake(0, 0, secondarySize.width, secondarySize.height);

    *leadingOut = leading;
    *trailingOut = trailing;
    *primaryOut = primary;
    *secondaryOut = secondaryStack;
    if (secondaryBodyOut) *secondaryBodyOut = secondary;
}

static UIView *OITIBuildCompactNoticeCard(NSDictionary<NSString *, NSString *> *info) {
    NSString *bundleID = info[@"bundleID"] ?: @"";
    NSString *appName = info[@"appName"] ?: @"";
    if (!appName.length && bundleID.length) appName = [bundleID componentsSeparatedByString:@"."].lastObject ?: @"";
    NSString *title = info[@"title"] ?: @"";
    NSString *message = info[@"message"] ?: @"";
    NSString *labelText = title.length ? title : (message.length ? message : appName);
    if (appName.length && title.length) labelText = [NSString stringWithFormat:@"%@ · %@", appName, title];

    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.distribution = UIStackViewDistributionFill;
    row.spacing = 6;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row.heightAnchor constraintEqualToConstant:24].active = YES;

    UIImage *icon = nil;
    if (bundleID.length && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
        icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0 scale:[UIScreen mainScreen].scale];
    }
    UIImage *smallIcon = OITIRoundedIcon(icon, 16);
    if (smallIcon) {
        UIImageView *iconView = [[UIImageView alloc] initWithImage:smallIcon];
        iconView.translatesAutoresizingMaskIntoConstraints = NO;
        [iconView.widthAnchor constraintEqualToConstant:18].active = YES;
        [iconView.heightAnchor constraintEqualToConstant:18].active = YES;
        [row addArrangedSubview:iconView];
    }

    UILabel *label = [UILabel new];
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    label.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.numberOfLines = 1;
    label.text = OITIShortText(labelText, 42);
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [row addArrangedSubview:label];
    UIView *card = [UIView new];
    card.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.13];
    card.layer.cornerRadius = 10;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:10],
        [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-10],
        [row.topAnchor constraintEqualToAnchor:card.topAnchor constant:5],
        [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-5],
        [card.heightAnchor constraintEqualToConstant:34],
    ]];
    return card;
}

// Present older notices as visually distinct, spaced compact cards beneath the current expanded notice.
void OITIRefreshNewestNoticeComposite(void) {
    NSDictionary *item = sIslandNoticeItems.lastObject;
    if (!item || OITINoticeStyle() == 0) return;
    OITINoticeStackView *stack = item[@"secondaryStack"];
    UIView *body = item[@"secondaryBody"];
    if (!stack || !body) return;

    for (UIView *view in [stack.arrangedSubviews copy]) {
        if (view == body) continue;
        [stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSUInteger olderCount = sIslandNoticeItems.count > 0 ? sIslandNoticeItems.count - 1 : 0;
    for (NSUInteger i = 0; i < olderCount; i++) {
        NSDictionary *older = sIslandNoticeItems[i];
        NSDictionary *info = older[@"info"];
        if (info) [stack addArrangedSubview:OITIBuildCompactNoticeCard(info)];
    }

    CGSize size = [stack sizeThatFits:CGSizeMake(260, CGFLOAT_MAX)];
    stack.frame = CGRectMake(stack.frame.origin.x, stack.frame.origin.y, size.width, size.height);
    [stack invalidateIntrinsicContentSize];
    for (UIView *view = stack.superview; view; view = view.superview) [view setNeedsLayout];
    [stack.superview layoutIfNeeded];
    [sLog logLevel:1 tag:@"ELEMENT" format:@"STACK separate-cards newest=%@ compactCards=%lu size=%.1fx%.1f",
     OITIKVCObject(item[@"element"], @"elementIdentifier"), (unsigned long)olderCount,
     (double)size.width, (double)size.height];
}

// ---- Corner radius adjustment (IslandNotificationsCornerExtra) -------------------------------
static NSMutableArray<NSDictionary *> *sCornerAdjusted;   // {view, original} for every layer we changed

NSString *OITICornerChain(UIView *view) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    UIView *up = view.superview;
    for (int i = 0; up && i < 9; i++, up = up.superview) {
        [parts addObject:[NSString stringWithFormat:@"%@(r=%.1f mask=%d curve=%@ size=%@)", NSStringFromClass([up class]),
                          up.layer.cornerRadius, up.layer.masksToBounds, up.layer.cornerCurve,
                          NSStringFromCGSize(up.bounds.size)]];
    }
    return [parts componentsJoinedByString:@" < "];
}

// Adds `extra` points to the corner radius of every rounded ancestor. The first time a layer is touched its original
// radius is remembered, so applying twice does not compound and OITIRestoreCorners puts everything back.
void OITIApplyCornerExtra(UIView *view, CGFloat extra) {
    if (extra == 0 || !view) return;
    if (!sCornerAdjusted) sCornerAdjusted = [NSMutableArray array];
    for (UIView *up = view.superview; up; up = up.superview) {
        if (up.layer.cornerRadius <= 0.5) continue;
        NSDictionary *existing = nil;
        for (NSDictionary *entry in sCornerAdjusted) {
            if (entry[@"view"] == up) { existing = entry; break; }
        }
        if (!existing) {
            existing = @{ @"view": up, @"original": @(up.layer.cornerRadius) };
            [sCornerAdjusted addObject:existing];
        }
        up.layer.cornerRadius = [existing[@"original"] doubleValue] + extra;
    }
}

void OITIRestoreCorners(void) {
    for (NSDictionary *entry in sCornerAdjusted) {
        UIView *view = entry[@"view"];
        view.layer.cornerRadius = [entry[@"original"] doubleValue];
    }
    [sCornerAdjusted removeAllObjects];
}

// Where a view ended up: class, frames, visibility, window and the first superviews. For the ELEMENT VIEWS line.
NSString *OITIViewDiag(UIView *view) {
    if (!view) return @"nil";
    NSMutableArray<NSString *> *chain = [NSMutableArray array];
    UIView *up = view.superview;
    for (int i = 0; up && i < 4; i++, up = up.superview) [chain addObject:NSStringFromClass([up class])];
    CGRect inWindow = view.window ? [view convertRect:view.bounds toView:nil] : CGRectZero;
    return [NSString stringWithFormat:@"%@ frame=%@ inWindow=%@ hidden=%d alpha=%.2f window=%@ chain=%@",
            NSStringFromClass([view class]), NSStringFromCGRect(view.frame), NSStringFromCGRect(inWindow), view.hidden, view.alpha,
            view.window ? NSStringFromClass([view.window class]) : @"nil", [chain componentsJoinedByString:@" < "]];
}
