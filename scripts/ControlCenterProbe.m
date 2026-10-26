#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

static id attribute(AXUIElementRef element, CFStringRef key) {
    CFTypeRef value = NULL;
    if (AXUIElementCopyAttributeValue(element, key, &value) != kAXErrorSuccess) return nil;
    return CFBridgingRelease(value);
}
static void walk(AXUIElementRef element, int depth, int *budget, BOOL open) {
    if (depth > 14 || (*budget)-- <= 0) return;
    NSString *identifier = attribute(element, CFSTR("AXIdentifier"));
    NSString *role = attribute(element, kAXRoleAttribute);
    NSString *description = attribute(element, kAXDescriptionAttribute);
    id title = attribute(element, kAXTitleAttribute);
    id value = attribute(element, kAXValueAttribute);
    printf("%*s%s id=%s description=%s title=%s value=%s\n", depth * 2, "", role.UTF8String ?: "", identifier.UTF8String ?: "",
        description.UTF8String ?: "", [[title description] UTF8String] ?: "", [[value description] UTF8String] ?: "");
    if (open && [identifier isEqualToString:@"com.apple.menuextra.controlcenter"]) {
        printf("open=%d\n", AXUIElementPerformAction(element, kAXPressAction));
    }
    NSArray *children = attribute(element, kAXChildrenAttribute);
    for (id child in children) walk((__bridge AXUIElementRef)child, depth + 1, budget, open);
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL inspectDeck = argc > 1 && strcmp(argv[1], "--optiondeck") == 0;
        BOOL inspectSettings = argc > 1 && strcmp(argv[1], "--settings") == 0;
        NSString *bundle = inspectSettings ? @"com.apple.systempreferences" : inspectDeck ? @"io.github.a1paka12.OptionDeck" : @"com.apple.controlcenter";
        NSRunningApplication *app = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundle].firstObject;
        if (!app) return 1;
        AXUIElementRef root = AXUIElementCreateApplication(app.processIdentifier);
        BOOL open = argc > 1 && strcmp(argv[1], "--open") == 0;
        if (open) {
            NSArray *children = attribute(root, kAXChildrenAttribute);
            for (id child in children) {
                int budget = 70;
                walk((__bridge AXUIElementRef)child, 0, &budget, YES);
            }
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
        }
        int budget = 300;
        walk(root, 0, &budget, NO);
        CFRelease(root);
    }
}
