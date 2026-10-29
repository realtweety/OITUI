#import <Foundation/Foundation.h>
#import "OITIBaseListController.h"
#import <OITCore/OITCore.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString * const kOITIPrefsDomain = @"com.wilburt.oiti.prefs";
static NSString * const kOITIPrefsChanged = @"com.wilburt.oiti/PrefsChanged";

#ifndef OITI_BUILD_VERSION
#define OITI_BUILD_VERSION ""
#endif

// The version of OITI that is installed, for the line at the bottom of the main page. The package database is read
// first: it holds the same version string as the installed .deb ("0.2.0", or "0.2.0-1+debug" for a debug build). The
// Settings process may not be allowed to read it, so the version baked into this bundle at build time (from the
// control file) is the fallback and is marked as built-in. Read once and kept.
// Keys for the two things a choice row keeps on its button. They must differ: with one shared key the second store
// replaced the first, and picking a value then sent setText: to the specifier instead of the label (a crash in
// Settings, present since the choice rows were added).
static const void *kOITIChoiceLabelKey = &kOITIChoiceLabelKey;
static const void *kOITIChoiceSpecifierKey = &kOITIChoiceSpecifierKey;

static NSString *OITIInstalledVersionText(void) {
    static NSString *text;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *found = nil;
        for (NSString *path in @[@"/var/jb/var/lib/dpkg/status", @"/var/lib/dpkg/status"]) {
            NSString *status = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            if (!status.length) continue;
            for (NSString *paragraph in [status componentsSeparatedByString:@"\n\n"]) {
                NSString *block = [paragraph stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (![block hasPrefix:@"Package: com.wilburt.oiti\n"]) continue;
                for (NSString *line in [block componentsSeparatedByString:@"\n"]) {
                    if ([line hasPrefix:@"Version: "]) {
                        found = [[line substringFromIndex:9] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                        break;
                    }
                }
                break;
            }
            if (found.length) break;
        }
        NSString *builtIn = @OITI_BUILD_VERSION;
        if (found.length) {
            text = [NSString stringWithFormat:@"Insula (OITI) version %@", found];
        } else if (builtIn.length) {
            text = [NSString stringWithFormat:@"Insula (OITI) version %@ (built-in)", builtIn];
        } else {
            text = @"Insula (OITI) version unknown";
        }
    });
    return text;
}

// Safe-mode files written by the tweak's respring-loop guard (OITI/Tweak.xm). Keep the paths in sync.
static NSString * const kOITISafeModePath = @"/var/mobile/Library/Preferences/OITISafeMode.plist";
static NSString * const kOITIBootLogPath = @"/var/mobile/Library/Preferences/OITIBootLog.plist";
// Left just before a respring this page asks for, so the guard does not count that launch as a possible crash.
static NSString * const kOITIRespringIntentPath = @"/var/mobile/Library/Preferences/OITIRespringIntent.plist";

// The safe-mode flag when OITI's hooks are switched off, nil otherwise.
static NSDictionary *OITISafeModeFlag(void) {
    NSDictionary *flag = [NSDictionary dictionaryWithContentsOfFile:kOITISafeModePath];
    return [flag[@"tripped"] boolValue] ? flag : nil;
}

// Apple Mode (key appleMode): the tweak forces every Island customization off while it is on. Read here only to show
// the banner. CFPreferences is read directly so a value just written by a switch on this page is seen.
static BOOL OITIAppleModeOn(void) {
    CFStringRef domain = (__bridge CFStringRef)kOITIPrefsDomain;
    CFPreferencesAppSynchronize(domain);
    Boolean valid = false;
    Boolean on = CFPreferencesGetAppBooleanValue(CFSTR("appleMode"), domain, &valid);
    return valid && on;
}

static void OITIMarkRespringIntent(void) {
    [@{ @"time": @([[NSDate date] timeIntervalSince1970]) } writeToFile:kOITIRespringIntentPath atomically:YES];
}

@interface OITIBaseListController () <UITextFieldDelegate>
@property (nonatomic, strong) UIScrollView *oiti_scrollView;
@property (nonatomic, strong) UIStackView *oiti_contentStack;
@property (nonatomic, assign) BOOL oiti_shownSafeMode;
@property (nonatomic, assign) BOOL oiti_shownAppleMode;
@end

@implementation OITIBaseListController

- (NSString *)oiti_plistName { return nil; }

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSString *name = [self oiti_plistName];
        if (name.length) _specifiers = [self loadSpecifiersFromPlistName:name target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    if ([self respondsToSelector:@selector(table)] && self.table) self.table.hidden = YES;

    UIBarButtonItem *respring = [[UIBarButtonItem alloc] initWithTitle:@"Respring"
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(respringAsk:)];
    self.navigationItem.rightBarButtonItem = respring;

    self.oiti_scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.oiti_scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.oiti_scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.oiti_scrollView];
    self.oiti_contentStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    self.oiti_contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.oiti_contentStack.axis = UILayoutConstraintAxisVertical;
    self.oiti_contentStack.spacing = 15.0;
    [self.oiti_scrollView addSubview:self.oiti_contentStack];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.oiti_scrollView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.oiti_scrollView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.oiti_scrollView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.oiti_scrollView.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [self.oiti_contentStack.topAnchor constraintEqualToAnchor:self.oiti_scrollView.contentLayoutGuide.topAnchor constant:18.0],
        [self.oiti_contentStack.leadingAnchor constraintEqualToAnchor:self.oiti_scrollView.frameLayoutGuide.leadingAnchor constant:18.0],
        [self.oiti_contentStack.trailingAnchor constraintEqualToAnchor:self.oiti_scrollView.frameLayoutGuide.trailingAnchor constant:-18.0],
        [self.oiti_contentStack.bottomAnchor constraintEqualToAnchor:self.oiti_scrollView.contentLayoutGuide.bottomAnchor constant:-26.0],
    ]];
    [self oiti_buildSettingsPage];
}

- (UIColor *)oitiCardColor {
    if (@available(iOS 13.0, *)) return [UIColor.secondarySystemGroupedBackgroundColor colorWithAlphaComponent:0.92];
    return [UIColor whiteColor];
}

- (UIView *)oitiSectionHeader:(NSString *)title subtitle:(NSString *)subtitle {
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 4.0;
    UILabel *heading = [[UILabel alloc] initWithFrame:CGRectZero];
    heading.text = title.length ? title : self.title;
    heading.font = [UIFont systemFontOfSize:25.0 weight:UIFontWeightBold];
    heading.numberOfLines = 0;
    [stack addArrangedSubview:heading];
    if (subtitle.length) {
        UILabel *detail = [[UILabel alloc] initWithFrame:CGRectZero];
        detail.text = subtitle;
        detail.numberOfLines = 0;
        detail.textColor = UIColor.secondaryLabelColor;
        detail.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightRegular];
        [stack addArrangedSubview:detail];
    }
    return stack;
}

- (UIView *)oitiCard {
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = [self oitiCardColor];
    card.layer.cornerRadius = 22.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.masksToBounds = YES;
    UIStackView *rows = [[UIStackView alloc] initWithFrame:CGRectZero];
    rows.translatesAutoresizingMaskIntoConstraints = NO;
    rows.axis = UILayoutConstraintAxisVertical;
    rows.spacing = 0.0;
    [card addSubview:rows];
    [NSLayoutConstraint activateConstraints:@[
        [rows.topAnchor constraintEqualToAnchor:card.topAnchor],
        [rows.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [rows.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [rows.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
    ]];
    objc_setAssociatedObject(card, @selector(oitiCard), rows, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return card;
}

- (UIStackView *)oiti_rowsInCard:(UIView *)card {
    return objc_getAssociatedObject(card, @selector(oitiCard));
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Safe mode can switch on or off while the settings are open (for example after a respring from here).
    if (self.oiti_contentStack &&
        ((OITISafeModeFlag() != nil) != self.oiti_shownSafeMode || OITIAppleModeOn() != self.oiti_shownAppleMode)) {
        [self oitiRefreshSettingsPage];
    }
}

// Banner shown at the top of every OITI settings page while Apple Mode is on, so it is clear why the customization
// settings below do nothing. The main page has the switch itself, so only the other pages get the button.
- (UIView *)oitiAppleModeBanner {
    if (!OITIAppleModeOn()) return nil;
    BOOL isRoot = [[self oiti_plistName] isEqualToString:@"Root"];

    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.16];
    card.layer.cornerRadius = 22.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.masksToBounds = YES;

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8.0;
    stack.layoutMargins = UIEdgeInsetsMake(15, 15, isRoot ? 15 : 8, 15);
    stack.layoutMarginsRelativeArrangement = YES;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
    ]];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"Apple Mode is on";
    title.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    title.numberOfLines = 0;
    [stack addArrangedSubview:title];

    UILabel *detail = [[UILabel alloc] initWithFrame:CGRectZero];
    detail.text = isRoot
        ? @"The Island is the stock iOS one. Your customization settings are saved but not applied."
        : @"The Island is the stock iOS one. The settings on this page are saved but not applied.";
    detail.font = [UIFont systemFontOfSize:13.0];
    detail.textColor = UIColor.secondaryLabelColor;
    detail.numberOfLines = 0;
    [stack addArrangedSubview:detail];

    if (!isRoot) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        [button setTitle:@"Turn Off Apple Mode" forState:UIControlStateNormal];
        [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
        [button addTarget:self action:@selector(oitiTurnOffAppleMode:) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:button];
    }
    return card;
}

- (void)oitiTurnOffAppleMode:(id)sender {
    CFStringRef domain = (__bridge CFStringRef)kOITIPrefsDomain;
    CFPreferencesSetAppValue(CFSTR("appleMode"), kCFBooleanFalse, domain);
    CFPreferencesAppSynchronize(domain);
    OITPostDarwinNotification(kOITIPrefsChanged);
    [self oitiRefreshSettingsPage];
}

// Banner shown at the top of every OITI settings page while the respring-loop guard has OITI's hooks switched off.
- (UIView *)oitiSafeModeBanner {
    NSDictionary *flag = OITISafeModeFlag();
    if (!flag) return nil;

    NSString *reason = [flag[@"reason"] isKindOfClass:[NSString class]] ? flag[@"reason"] : @"repeated SpringBoard restarts";
    NSString *when = @"";
    if ([flag[@"time"] isKindOfClass:[NSNumber class]]) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
        when = [NSString stringWithFormat:@" (%@)", [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:[flag[@"time"] doubleValue]]]];
    }

    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.backgroundColor = [UIColor.systemOrangeColor colorWithAlphaComponent:0.20];
    card.layer.cornerRadius = 22.0;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.layer.masksToBounds = YES;

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8.0;
    stack.layoutMargins = UIEdgeInsetsMake(15, 15, 8, 15);
    stack.layoutMarginsRelativeArrangement = YES;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
    ]];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"Insula safe mode is on";
    title.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
    title.numberOfLines = 0;
    [stack addArrangedSubview:title];

    UILabel *detail = [[UILabel alloc] initWithFrame:CGRectZero];
    detail.text = [NSString stringWithFormat:@"Insula switched its tweaks off after %@%@. Your changes below are saved but do nothing until safe mode is cleared and you respring. If SpringBoard keeps restarting after that, safe mode will switch on again.", reason, when];
    detail.font = [UIFont systemFontOfSize:13.0];
    detail.textColor = UIColor.secondaryLabelColor;
    detail.numberOfLines = 0;
    [stack addArrangedSubview:detail];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [button setTitle:@"Clear Safe Mode & Respring" forState:UIControlStateNormal];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [button addTarget:self action:@selector(oitiClearSafeModeAsk:) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:button];
    return card;
}

- (void)oitiClearSafeModeAsk:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear safe mode"
                                                                   message:@"Insula's tweaks switch back on after the respring."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear & Respring" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager removeItemAtPath:kOITISafeModePath error:nil];
        [fileManager removeItemAtPath:kOITIBootLogPath error:nil];
        OITIMarkRespringIntent();
        OITRequestRespring();
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)oiti_buildSettingsPage {
    [self.oiti_contentStack addArrangedSubview:[self oitiSectionHeader:self.title subtitle:nil]];
    UIView *safeModeBanner = [self oitiSafeModeBanner];
    self.oiti_shownSafeMode = safeModeBanner != nil;
    if (safeModeBanner) [self.oiti_contentStack addArrangedSubview:safeModeBanner];
    UIView *appleModeBanner = [self oitiAppleModeBanner];
    self.oiti_shownAppleMode = appleModeBanner != nil;
    if (appleModeBanner) [self.oiti_contentStack addArrangedSubview:appleModeBanner];
    UIView *card = nil;
    UIStackView *rows = nil;
    NSString *pendingFooter = nil;

    for (PSSpecifier *specifier in self.specifiers) {
        NSString *cell = [specifier propertyForKey:@"cell"];
        NSString *label = [specifier propertyForKey:@"label"];
        NSString *footer = [specifier propertyForKey:@"footerText"];
        if ([cell isEqualToString:@"PSGroupCell"]) {
            if (card) {
                if (pendingFooter.length) [rows addArrangedSubview:[self oitiFootnote:pendingFooter]];
                [self.oiti_contentStack addArrangedSubview:card];
            }
            card = nil; rows = nil;
            pendingFooter = footer;
            if (label.length) [self.oiti_contentStack addArrangedSubview:[self oitiSectionHeader:label subtitle:nil]];
            continue;
        }
        if (!card) { card = [self oitiCard]; rows = [self oiti_rowsInCard:card]; }
        UIView *row = nil;
        if ([cell isEqualToString:@"PSSwitchCell"]) row = [self oitiSwitchRow:specifier];
        else if ([cell isEqualToString:@"PSSliderCell"]) row = [self oitiSliderRow:specifier];
        else if ([cell isEqualToString:@"PSEditTextCell"]) row = [self oitiTextRow:specifier];
        else if ([cell isEqualToString:@"PSButtonCell"]) row = [self oitiButtonRow:specifier];
        else if ([cell isEqualToString:@"PSLinkCell"]) row = [self oitiLinkRow:specifier];
        else if ([cell isEqualToString:@"PSLinkListCell"]) row = [self oitiChoiceRow:specifier];
        if (row) {
            if (rows.arrangedSubviews.count) {
                UIView *dividerRow = [[UIView alloc] initWithFrame:CGRectZero];
                UIView *divider = [UIView new];
                divider.translatesAutoresizingMaskIntoConstraints = NO;
                divider.backgroundColor = [UIColor.separatorColor colorWithAlphaComponent:0.45];
                [dividerRow addSubview:divider];
                [NSLayoutConstraint activateConstraints:@[
                    [divider.leadingAnchor constraintEqualToAnchor:dividerRow.leadingAnchor constant:15],
                    [divider.trailingAnchor constraintEqualToAnchor:dividerRow.trailingAnchor constant:-15],
                    [divider.topAnchor constraintEqualToAnchor:dividerRow.topAnchor],
                    [divider.bottomAnchor constraintEqualToAnchor:dividerRow.bottomAnchor],
                    [divider.heightAnchor constraintEqualToConstant:0.5],
                ]];
                [rows addArrangedSubview:dividerRow];
            }
            [rows addArrangedSubview:row];
        }
    }
    if (card) {
        if (pendingFooter.length) [rows addArrangedSubview:[self oitiFootnote:pendingFooter]];
        [self.oiti_contentStack addArrangedSubview:card];
    }
    if ([[self oiti_plistName] isEqualToString:@"Root"]) {
        UILabel *credit = [[UILabel alloc] initWithFrame:CGRectZero];
        credit.text = @"Insula · Settings design adapted from Liquid (Gl)Ass";
        credit.textColor = UIColor.tertiaryLabelColor;
        credit.textAlignment = NSTextAlignmentCenter;
        credit.font = [UIFont systemFontOfSize:11.0];
        [self.oiti_contentStack addArrangedSubview:credit];

        UILabel *version = [[UILabel alloc] initWithFrame:CGRectZero];
        version.text = OITIInstalledVersionText();
        version.textColor = UIColor.tertiaryLabelColor;
        version.textAlignment = NSTextAlignmentCenter;
        version.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
        [self.oiti_contentStack addArrangedSubview:version];
    }
}

- (void)oitiRefreshSettingsPage {
    [self.view endEditing:YES];
    for (UIView *view in [self.oiti_contentStack.arrangedSubviews copy]) {
        [self.oiti_contentStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    [self oiti_buildSettingsPage];
}

- (UIView *)oitiFootnote:(NSString *)text {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text;
    label.numberOfLines = 0;
    label.font = [UIFont systemFontOfSize:12.0];
    label.textColor = UIColor.secondaryLabelColor;
    label.layoutMargins = UIEdgeInsetsMake(12, 15, 12, 15);
    label.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *wrapper = [UIView new];
    [wrapper addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.topAnchor constraintEqualToAnchor:wrapper.topAnchor constant:10],
        [label.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor constant:15],
        [label.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor constant:-15],
        [label.bottomAnchor constraintEqualToAnchor:wrapper.bottomAnchor constant:-12],
    ]];
    return wrapper;
}

- (UIView *)oitiRowWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 4;
    UILabel *heading = [[UILabel alloc] initWithFrame:CGRectZero];
    heading.text = title;
    heading.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
    heading.numberOfLines = 0;
    [stack addArrangedSubview:heading];
    if (subtitle.length) {
        UILabel *detail = [[UILabel alloc] initWithFrame:CGRectZero];
        detail.text = subtitle;
        detail.font = [UIFont systemFontOfSize:12.5];
        detail.textColor = UIColor.secondaryLabelColor;
        detail.numberOfLines = 0;
        [stack addArrangedSubview:detail];
    }
    return stack;
}

- (UIView *)oitiSwitchRow:(PSSpecifier *)specifier {
    UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectZero];
    row.axis = UILayoutConstraintAxisHorizontal; row.alignment = UIStackViewAlignmentCenter; row.spacing = 12;
    row.layoutMargins = UIEdgeInsetsMake(13, 15, 13, 15); row.layoutMarginsRelativeArrangement = YES;
    UIView *text = [self oitiRowWithTitle:[specifier propertyForKey:@"label"] subtitle:nil];
    [text setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [row addArrangedSubview:text];
    UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
    id savedValue = [self readPreferenceValue:specifier] ?: [specifier propertyForKey:@"default"] ?: @NO;
    toggle.on = [savedValue boolValue];
    toggle.accessibilityLabel = [specifier propertyForKey:@"label"];
    [toggle addTarget:self action:@selector(oitiSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    objc_setAssociatedObject(toggle, @selector(oitiSwitchChanged:), specifier, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(text, @selector(oitiSwitchChanged:), toggle, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    text.userInteractionEnabled = YES;
    [text addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(oitiSwitchLabelTapped:)]];
    [row addArrangedSubview:toggle];
    return row;
}

- (void)oitiSwitchLabelTapped:(UITapGestureRecognizer *)gesture {
    UISwitch *toggle = objc_getAssociatedObject(gesture.view, @selector(oitiSwitchChanged:));
    if (!toggle || !toggle.enabled) return;
    toggle.on = !toggle.on;
    [self oitiSwitchChanged:toggle];
}

- (void)oitiSwitchChanged:(UISwitch *)sender {
    PSSpecifier *specifier = objc_getAssociatedObject(sender, @selector(oitiSwitchChanged:));
    [self setPreferenceValue:@(sender.on) specifier:specifier];
    // Apple Mode shows a banner on every page, so rebuild this one to add or remove it.
    if ([[specifier propertyForKey:@"key"] isEqualToString:@"appleMode"]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self oitiRefreshSettingsPage]; });
    }
}

// Text for a slider's value. plist keys: valueFormat (a format taking one double, default "%.2f") and zeroText (shown
// instead when the value is below 0.5, for sliders where 0 means "never").
static NSString *OITISliderValueText(PSSpecifier *specifier, double value) {
    NSString *zeroText = [specifier propertyForKey:@"zeroText"];
    if ([zeroText isKindOfClass:[NSString class]] && zeroText.length && value < 0.5) return zeroText;
    NSString *format = [specifier propertyForKey:@"valueFormat"];
    if (![format isKindOfClass:[NSString class]] || !format.length) format = @"%.2f";
    return [NSString stringWithFormat:format, value];
}

- (UIView *)oitiSliderRow:(PSSpecifier *)specifier {
    UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectZero];
    row.axis = UILayoutConstraintAxisVertical; row.spacing = 9;
    row.layoutMargins = UIEdgeInsetsMake(12, 15, 13, 15); row.layoutMarginsRelativeArrangement = YES;
    NSNumber *min = [specifier propertyForKey:@"min"] ?: @0;
    NSNumber *max = [specifier propertyForKey:@"max"] ?: @1;
    NSNumber *value = [self readPreferenceValue:specifier] ?: [specifier propertyForKey:@"default"] ?: min;
    UIStackView *top = [[UIStackView alloc] initWithFrame:CGRectZero];
    UILabel *name = [[UILabel alloc] initWithFrame:CGRectZero]; name.text = [specifier propertyForKey:@"label"];
    name.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightMedium];
    UILabel *number = [[UILabel alloc] initWithFrame:CGRectZero];
    number.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
    number.textColor = UIColor.secondaryLabelColor; number.textAlignment = NSTextAlignmentRight;
    number.text = OITISliderValueText(specifier, value.doubleValue);
    [top addArrangedSubview:name]; [top addArrangedSubview:number];
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectZero];
    slider.minimumValue = min.floatValue; slider.maximumValue = max.floatValue; slider.value = value.floatValue;
    [slider addTarget:self action:@selector(oitiSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [slider addTarget:self action:@selector(oitiSliderFinished:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    objc_setAssociatedObject(slider, @selector(oitiSliderChanged:), specifier, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slider, @selector(oitiSliderValueLabel:), number, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [row addArrangedSubview:top]; [row addArrangedSubview:slider];
    return row;
}

- (void)oitiSliderChanged:(UISlider *)slider {
    UILabel *value = objc_getAssociatedObject(slider, @selector(oitiSliderValueLabel:));
    PSSpecifier *specifier = objc_getAssociatedObject(slider, @selector(oitiSliderChanged:));
    value.text = OITISliderValueText(specifier, slider.value);
    NSMutableDictionary *state = objc_getAssociatedObject(slider, @selector(oitiSliderState:));
    if (!state) {
        state = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(slider, @selector(oitiSliderState:), state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    dispatch_block_t pending = state[@"pending"];
    if (pending) return; // one trailing write will save the newest slider value
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    NSTimeInterval last = [state[@"lastWrite"] doubleValue];
    NSTimeInterval delay = MAX(0.0, 0.12 - (now - last));
    if (delay <= 0.0) {
        [self setPreferenceValue:@(slider.value) specifier:specifier];
        state[@"lastWrite"] = @(now);
        return;
    }
    __weak UISlider *weakSlider = slider;
    __weak OITIBaseListController *weakSelf = self;
    dispatch_block_t block = dispatch_block_create((dispatch_block_flags_t)0, ^{
        UISlider *strongSlider = weakSlider;
        OITIBaseListController *strongSelf = weakSelf;
        if (!strongSlider || !strongSelf) return;
        NSMutableDictionary *liveState = objc_getAssociatedObject(strongSlider, @selector(oitiSliderState:));
        if (liveState[@"pending"] != [NSNull null]) [liveState removeObjectForKey:@"pending"];
        PSSpecifier *liveSpecifier = objc_getAssociatedObject(strongSlider, @selector(oitiSliderChanged:));
        [strongSelf setPreferenceValue:@(strongSlider.value) specifier:liveSpecifier];
        liveState[@"lastWrite"] = @(NSProcessInfo.processInfo.systemUptime);
    });
    state[@"pending"] = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

- (void)oitiSliderFinished:(UISlider *)slider {
    NSMutableDictionary *state = objc_getAssociatedObject(slider, @selector(oitiSliderState:));
    dispatch_block_t pending = state[@"pending"];
    if (pending) dispatch_block_cancel(pending);
    [state removeObjectForKey:@"pending"];
    PSSpecifier *specifier = objc_getAssociatedObject(slider, @selector(oitiSliderChanged:));
    [self setPreferenceValue:@(slider.value) specifier:specifier];
    state[@"lastWrite"] = @(NSProcessInfo.processInfo.systemUptime);
}

- (UIView *)oitiTextRow:(PSSpecifier *)specifier {
    UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectZero]; row.axis = UILayoutConstraintAxisHorizontal; row.spacing = 12;
    row.alignment = UIStackViewAlignmentCenter; row.layoutMargins = UIEdgeInsetsMake(12, 15, 12, 15); row.layoutMarginsRelativeArrangement = YES;
    [row addArrangedSubview:[self oitiRowWithTitle:[specifier propertyForKey:@"label"] subtitle:nil]];
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
    field.text = [self readPreferenceValue:specifier] ?: [specifier propertyForKey:@"bestGuess"];
    field.placeholder = [specifier propertyForKey:@"placeholder"];
    field.textAlignment = NSTextAlignmentRight; field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    field.borderStyle = UITextBorderStyleRoundedRect; field.returnKeyType = UIReturnKeyDone;
    field.delegate = self;
    [field addTarget:self action:@selector(oitiTextChanged:) forControlEvents:UIControlEventEditingDidEnd];
    objc_setAssociatedObject(field, @selector(oitiTextChanged:), specifier, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [row addArrangedSubview:field];
    [field.widthAnchor constraintGreaterThanOrEqualToConstant:82].active = YES;
    return row;
}

- (void)oitiTextChanged:(UITextField *)field {
    PSSpecifier *specifier = objc_getAssociatedObject(field, @selector(oitiTextChanged:));
    if (field.text) [self setPreferenceValue:field.text specifier:specifier];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (UIView *)oitiButtonRow:(PSSpecifier *)specifier {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [button setTitle:[specifier propertyForKey:@"label"] forState:UIControlStateNormal];
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:52].active = YES;
    [button addTarget:self action:@selector(oitiButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(button, @selector(oitiButtonPressed:), specifier, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return button;
}

- (void)oitiButtonPressed:(UIButton *)sender {
    PSSpecifier *specifier = objc_getAssociatedObject(sender, @selector(oitiButtonPressed:));
    NSString *action = [specifier propertyForKey:@"action"];
    SEL selector = NSSelectorFromString(action);
    if (!action.length || ![self respondsToSelector:selector]) return;
    NSMethodSignature *signature = [self methodSignatureForSelector:selector];
    if (!signature) return;
    if (signature.numberOfArguments == 2) {
        ((void (*)(id, SEL))objc_msgSend)(self, selector);
    } else if (signature.numberOfArguments == 3) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, selector, sender);
    }
}

- (UIView *)oitiLinkRow:(PSSpecifier *)specifier {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectZero]; row.axis = UILayoutConstraintAxisHorizontal; row.alignment = UIStackViewAlignmentCenter; row.spacing = 10;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero]; label.text = [specifier propertyForKey:@"label"];
    label.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium]; label.textColor = UIColor.labelColor;
    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]]; chevron.tintColor = UIColor.tertiaryLabelColor;
    [row addArrangedSubview:label]; [row addArrangedSubview:chevron];
    // This stack is presentation only. Let touches reach the enclosing button.
    row.userInteractionEnabled = NO;
    row.translatesAutoresizingMaskIntoConstraints = NO; [button addSubview:row];
    [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:15], [row.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-15], [row.topAnchor constraintEqualToAnchor:button.topAnchor constant:15], [row.bottomAnchor constraintEqualToAnchor:button.bottomAnchor constant:-15]]];
    [button addTarget:self action:@selector(oitiOpenLink:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(button, @selector(oitiOpenLink:), specifier, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return button;
}

- (void)oitiOpenLink:(UIButton *)sender {
    PSSpecifier *specifier = objc_getAssociatedObject(sender, @selector(oitiOpenLink:));
    NSString *controllerName = [specifier propertyForKey:@"detail"];
    Class controllerClass = NSClassFromString(controllerName);
    if (controllerClass && [controllerClass isSubclassOfClass:[OITIBaseListController class]]) {
        OITIBaseListController *controller = [controllerClass new];
        controller.title = [specifier propertyForKey:@"label"];
        [self.navigationController pushViewController:controller animated:YES];
    }
}

- (UIView *)oitiChoiceRow:(PSSpecifier *)specifier {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectZero]; row.axis = UILayoutConstraintAxisHorizontal; row.spacing = 8;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero]; title.text = [specifier propertyForKey:@"label"]; title.textColor = UIColor.labelColor; title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    UILabel *current = [[UILabel alloc] initWithFrame:CGRectZero]; current.textColor = UIColor.secondaryLabelColor; current.textAlignment = NSTextAlignmentRight; current.font = [UIFont systemFontOfSize:13];
    objc_setAssociatedObject(button, kOITIChoiceLabelKey, current, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSArray *values = [specifier propertyForKey:@"validValues"] ?: @[]; NSArray *titles = [specifier propertyForKey:@"validTitles"] ?: values;
    id selected = [self readPreferenceValue:specifier] ?: [specifier propertyForKey:@"default"];
    NSUInteger index = [values indexOfObject:selected]; current.text = index < titles.count ? titles[index] : @"Choose";
    [row addArrangedSubview:title]; [row addArrangedSubview:current];
    // The selection sheet is presented by the button, not by this visual stack.
    row.userInteractionEnabled = NO;
    row.translatesAutoresizingMaskIntoConstraints = NO; [button addSubview:row];
    [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:button.leadingAnchor constant:15],[row.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-15],[row.topAnchor constraintEqualToAnchor:button.topAnchor constant:15],[row.bottomAnchor constraintEqualToAnchor:button.bottomAnchor constant:-15]]];
    [button addTarget:self action:@selector(oitiChooseValue:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(button, kOITIChoiceSpecifierKey, specifier, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return button;
}

- (void)oitiChooseValue:(UIButton *)sender {
    PSSpecifier *specifier = objc_getAssociatedObject(sender, kOITIChoiceSpecifierKey);
    NSArray *values = [specifier propertyForKey:@"validValues"] ?: @[]; NSArray *titles = [specifier propertyForKey:@"validTitles"] ?: values;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[specifier propertyForKey:@"label"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSUInteger i = 0; i < values.count; i++) {
        id value = values[i];
        [sheet addAction:[UIAlertAction actionWithTitle:(i < titles.count ? titles[i] : [value description]) style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [self setPreferenceValue:value specifier:specifier];
            UILabel *current = objc_getAssociatedObject(sender, kOITIChoiceLabelKey);
            current.text = i < titles.count ? titles[i] : [value description];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController; popover.sourceView = sender; popover.sourceRect = sender.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)respringAsk:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Respring" message:@"You are about to respring." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) { OITIMarkRespringIntent(); OITRequestRespring(); }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)savePos { [self.view endEditing:YES]; }

@end
