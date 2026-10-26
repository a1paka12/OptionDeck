// Native editor regression probe. Changes only unsaved drafts and restores the pointer.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
static id attr(AXUIElementRef node, CFStringRef key) {
    CFTypeRef value=NULL;
    if(AXUIElementCopyAttributeValue(node,key,&value)!=kAXErrorSuccess) return nil;
    return CFBridgingRelease(value);
}
static AXUIElementRef find(AXUIElementRef node, NSString *label, BOOL useLast, int depth) {
    if(depth>14) return NULL;
    AXUIElementRef result=NULL;
    if([attr(node,kAXValueAttribute) isEqual:label] || [attr(node,kAXDescriptionAttribute) isEqual:label] || [attr(node,kAXIdentifierAttribute) isEqual:label]) {
        result=(AXUIElementRef)CFRetain(node); if(!useLast) return result;
    }
    for(id child in attr(node,kAXChildrenAttribute)) {
        AXUIElementRef next=find((__bridge AXUIElementRef)child,label,useLast,depth+1);
        if(next) { if(!useLast) return next; if(result) CFRelease(result); result=next; }
    }
    return result;
}
static CGRect bounds(AXUIElementRef node) {
    CGPoint point=CGPointZero; CGSize size=CGSizeZero;
    id p=attr(node,kAXPositionAttribute), s=attr(node,kAXSizeAttribute);
    if(p) AXValueGetValue((__bridge AXValueRef)p,kAXValueCGPointType,&point);
    if(s) AXValueGetValue((__bridge AXValueRef)s,kAXValueCGSizeType,&size);
    return CGRectMake(point.x,point.y,size.width,size.height);
}
// Sidebar entries share these labels. Choose the actual resizable card, not its icon.
static AXUIElementRef findCard(AXUIElementRef node, NSString *label, int depth) {
    if(depth>14) return NULL;
    AXUIElementRef best=NULL; CGFloat area=0;
    if([attr(node,kAXValueAttribute) isEqual:label] || [attr(node,kAXDescriptionAttribute) isEqual:label]) {
        CGRect rect=bounds(node);
        if(rect.size.width>180 && rect.size.height>70) { best=(AXUIElementRef)CFRetain(node); area=rect.size.width*rect.size.height; }
    }
    for(id child in attr(node,kAXChildrenAttribute)) {
        AXUIElementRef candidate=findCard((__bridge AXUIElementRef)child,label,depth+1);
        if(candidate) {
            CGRect rect=bounds(candidate); CGFloat next=rect.size.width*rect.size.height;
            if(next>area) { if(best) CFRelease(best); best=candidate; area=next; }
            else CFRelease(candidate);
        }
    }
    return best;
}
static CGPoint center(AXUIElementRef node) { CGRect r=bounds(node); return CGPointMake(CGRectGetMidX(r),CGRectGetMidY(r)); }
static void pauseFor(double seconds) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]]; }
static void post(CGEventType type, CGPoint point) {
    CGEventRef event=CGEventCreateMouseEvent(NULL,type,point,kCGMouseButtonLeft);
    CGEventSetFlags(event,0); CGEventPost(kCGHIDEventTap,event); CFRelease(event);
}
static BOOL press(AXUIElementRef root, NSString *label) {
    AXUIElementRef node=find(root,label,NO,0); if(!node) return NO;
    AXError error=AXUIElementPerformAction(node,kAXPressAction); CFRelease(node); pauseFor(.3);
    return error==kAXErrorSuccess;
}
static void drag(CGPoint from, CGPoint to, AXUIElementRef root, BOOL checkPreview, BOOL *preview) {
    post(kCGEventMouseMoved,from); pauseFor(.1); post(kCGEventLeftMouseDown,from); pauseFor(.2);
    for(int i=1;i<=30;i++) {
        double t=i/30.0;
        post(kCGEventLeftMouseDragged,CGPointMake(from.x+(to.x-from.x)*t,from.y+(to.y-from.y)*t)); pauseFor(.025);
    }
    pauseFor(.2);
    if(checkPreview) {
        AXUIElementRef item=findCard(root,@"밝기",0);
        if(item) { *preview=fabs(center(item).x-to.x)<12; CFRelease(item); }
    }
    post(kCGEventLeftMouseUp,to); pauseFor(.5);
}
int main(void) { @autoreleasepool {
    if(!AXIsProcessTrusted() || !CGPreflightPostEventAccess()) { fprintf(stderr,"Accessibility and event posting permission required\n"); return 1; }
    NSRunningApplication *app=[NSRunningApplication runningApplicationsWithBundleIdentifier:@"io.github.a1paka12.OptionDeck"].firstObject;
    if(!app) return 2;
    AXUIElementRef root=AXUIElementCreateApplication(app.processIdentifier);
    if(!press(root,@"showSettings")) { CFRelease(root); return 3; }
    [app activateWithOptions:0]; pauseFor(.5);
    if(NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier!=app.processIdentifier) { CFRelease(root); return 4; }
    CGEventRef event=CGEventCreate(NULL); CGPoint original=CGEventGetLocation(event); CFRelease(event);
    BOOL moved=NO, preview=NO, resized=NO, reflow=NO, placed=NO, preserved=NO, removed=NO;
    @try {
        press(root,@"1페이지 · 시스템");
        AXUIElementRef source=findCard(root,@"밝기",0), target=findCard(root,@"볼륨",0);
        if(!source || !target) return 5;
        CGPoint from=center(source), to=center(target); CFRelease(source); CFRelease(target);
        drag(from,to,root,YES,&preview);
        source=findCard(root,@"밝기",0);
        moved=source && fabs(center(source).x-to.x)<12; if(source) CFRelease(source);
        printf("Live layout preview before release: %s; card move: %s\n",preview?"PASS":"FAIL",moved?"PASS":"FAIL");
        press(root,@"다시 불러오기");
        source=findCard(root,@"밝기",0); target=findCard(root,@"볼륨",0);
        if(!source || !target) return 6;
        CGRect before=bounds(source), neighbor=bounds(target); CFRelease(source); CFRelease(target);
        CGPoint handle=CGPointMake(CGRectGetMaxX(before)-10,CGRectGetMaxY(before)-10);
        drag(handle,CGPointMake(handle.x+110,handle.y+80),root,NO,NULL);
        source=findCard(root,@"밝기",0); target=findCard(root,@"볼륨",0);
        if(!source || !target) return 7;
        CGRect after=bounds(source); resized=after.size.width>before.size.width+40 || after.size.height>before.size.height+40;
        reflow=!CGRectEqualToRect(neighbor,bounds(target)); CFRelease(source); CFRelease(target);
        printf("Resize: %s (%.0fx%.0f -> %.0fx%.0f); neighbor reflow: %s\n",resized?"PASS":"FAIL",before.size.width,before.size.height,after.size.width,after.size.height,reflow?"PASS":"FAIL");
        press(root,@"다시 불러오기"); press(root,@"2페이지 · 기능");
        source=find(root,@"스크린샷 도구",NO,0); target=find(root,@"Chrome",NO,0);
        if(!source || !target) return 8;
        from=center(source); to=center(target); CFRelease(source); CFRelease(target);
        drag(from,to,root,NO,NULL);
        source=find(root,@"스크린샷 도구",YES,0);
        placed=source && hypot(center(source).x-to.x,center(source).y-to.y)<20; if(source) CFRelease(source);
        target=find(root,@"Chrome",NO,0);
        preserved=target && fabs(center(target).x-to.x)>40; if(target) CFRelease(target);
        printf("Page 2 feature insertion: %s; existing Chrome preserved: %s\n",placed?"PASS":"FAIL",preserved?"PASS":"FAIL");
        source=find(root,@"스크린샷 도구",YES,0);
        NSArray *windows=attr(root,kAXWindowsAttribute);
        AXUIElementRef settingsWindow=NULL;
        for(id window in windows) if([attr((__bridge AXUIElementRef)window,kAXTitleAttribute) isEqual:@"OptionDeck 설정"]) settingsWindow=(__bridge AXUIElementRef)window;
        if(source && settingsWindow) {
            CGPoint start=center(source); CGRect windowFrame=bounds(settingsWindow);
            drag(start,CGPointMake(windowFrame.origin.x+25,start.y),root,NO,NULL);
            target=find(root,@"Chrome",NO,0);
            AXUIElementRef leftover=find(root,@"스크린샷 도구",YES,0);
            removed=target && hypot(center(target).x-to.x,center(target).y-to.y)<20 && (!leftover || fabs(center(leftover).x-to.x)>80);
            if(target) CFRelease(target); if(leftover) CFRelease(leftover);
        }
        if(source) CFRelease(source);
        printf("Drag outside removes tile and closes space: %s\n",removed?"PASS":"FAIL");
    } @finally {
        press(root,@"다시 불러오기"); CGWarpMouseCursorPosition(original); CFRelease(root);
    }
    return moved && preview && resized && reflow && placed && preserved && removed ? 0:9;
} }
