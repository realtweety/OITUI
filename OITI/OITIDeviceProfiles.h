// OITIDeviceProfiles.h
//
// Single source of truth for per-device Island and banner offsets. Used by the tweak (Tweak.xm) and the
// prefs bundle (OITIRootListController.m), so the "supported devices" check can never drift from the offsets.
//
// Generated from the six hand-copied if/else chains that Tweak.xm used to contain; a script verified that all
// six agreed for every device before they were replaced. `verified = NO` marks offsets that the original
// comments flagged as "FAKE OFFSETS??" or "FIND OFFSETS - USING ESTIMATED".
//
// To add a device: append one row. Nothing else needs to change.

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <string.h>

typedef struct {
    const char *model;     // machine identifier, e.g. "iPhone14,2"
    const char *name;      // marketing name (for logs and UI)
    CGFloat islandY;       // SBSystemApertureWindow origin.y at scale 1.0 ("fixEnabled")
    CGFloat bannerY;       // SBBannerWindow origin.y ("notificationFix")
    CGFloat bannerWidth;   // SBBannerWindow size
    CGFloat bannerHeight;
    BOOL verified;         // NO = estimated offsets
} OITIDeviceProfile;

static const OITIDeviceProfile kOITIDeviceProfiles[] = {
    { "iPhone10,3", "iPhone X", 20.5, 35, 375, 812, YES },
    { "iPhone10,6", "iPhone X", 20.5, 35, 375, 812, YES },
    { "iPhone11,2", "iPhone XS", 20.5, 35, 375, 812, YES },
    { "iPhone11,6", "iPhone XS Max", 22.5, 37, 414, 896, NO },
    { "iPhone11,8", "iPhone XR", 22.5, 37, 414, 896, NO },
    { "iPhone12,1", "iPhone 11", 22.5, 37, 414, 896, NO },
    { "iPhone12,3", "iPhone 11 Pro", 20.5, 35, 375, 812, YES },
    { "iPhone12,5", "iPhone 11 Pro Max", 22.5, 37, 414, 896, NO },
    { "iPhone13,1", "iPhone 12 mini", 19.5, 33, 360, 780, NO },
    { "iPhone13,2", "iPhone 12", 21.5, 35, 390, 844, NO },
    { "iPhone13,3", "iPhone 12 Pro", 21.5, 35, 390, 844, NO },
    { "iPhone13,4", "iPhone 12 Pro Max", 22.3, 38, 428, 926, NO },
    { "iPhone14,2", "iPhone 13 Pro", 24, 40, 390, 844, YES },
    { "iPhone14,3", "iPhone 13 Pro Max", 26, 42, 428, 926, NO },
    { "iPhone14,4", "iPhone 13 mini", 22.5, 38, 360, 780, NO },
    { "iPhone14,5", "iPhone 13", 24, 40, 390, 844, YES },
    { "iPhone14,7", "iPhone 14", 24, 40, 390, 844, YES },
};

static inline const OITIDeviceProfile *OITIProfileForModel(NSString *model) {
    if (!model.length) return NULL;
    const char *needle = model.UTF8String;
    for (size_t i = 0; i < sizeof(kOITIDeviceProfiles) / sizeof(kOITIDeviceProfiles[0]); i++) {
        if (strcmp(kOITIDeviceProfiles[i].model, needle) == 0) return &kOITIDeviceProfiles[i];
    }
    return NULL;
}
