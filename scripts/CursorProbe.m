#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>

static int received;
static int mode;
static CGPoint anchor;
static const int64_t tag = 0x4F445052;
static CGEventRef filter(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *context) {
    if (type != kCGEventMouseMoved || CGEventGetIntegerValueField(event, kCGEventSourceUserData) != tag) return event;
    received++;
    if (mode == 2) {
        CGEventSetLocation(event, anchor);
        CGEventSetIntegerValueField(event, kCGMouseEventDeltaX, 0);
        CGEventSetIntegerValueField(event, kCGMouseEventDeltaY, 0);
    }
    if (mode == 3 || mode == 4) CGWarpMouseCursorPosition(anchor);
    return NULL;
}
static CGPoint position(void) {
    CGEventRef event = CGEventCreate(NULL);
    CGPoint point = CGEventGetLocation(event);
    CFRelease(event); return point;
}
int main(void) {
    @autoreleasepool {
        CGPoint original = position();
        anchor = CGPointMake(round(original.x), round(original.y));
        @try {
            for (mode = 0; mode < 5; mode++) {
                received = 0;
                CGEventTapLocation location = (mode == 0 || mode == 4) ? kCGSessionEventTap : kCGHIDEventTap;
                CFMachPortRef tap = CGEventTapCreate(location, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                    CGEventMaskBit(kCGEventMouseMoved), filter, NULL);
                if (!tap) { printf("mode=%d tap-unavailable\n", mode); continue; }
                CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
                CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
                CGWarpMouseCursorPosition(anchor);
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
                CGEventRef move = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved,
                    CGPointMake(anchor.x + 40, anchor.y + 25), kCGMouseButtonLeft);
                CGEventSetIntegerValueField(move, kCGEventSourceUserData, tag);
                CGEventSetIntegerValueField(move, kCGMouseEventDeltaX, 40);
                CGEventSetIntegerValueField(move, kCGMouseEventDeltaY, 25);
                CGEventPost(kCGHIDEventTap, move); CFRelease(move);
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
                CGPoint after = position();
                printf("mode=%d callback=%d displacement=%.2f,%.2f\n", mode, received, after.x-anchor.x, after.y-anchor.y);
                CGEventTapEnable(tap, false); CFMachPortInvalidate(tap);
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
                CFRelease(source); CFRelease(tap);
            }
        } @finally { CGWarpMouseCursorPosition(original); }
    }
}
