#import "CaptureTextRenderer.h"

BOOL FLDrawCaptureDimensions(CGSize pixels, CGRect selection, CGRect bounds, NSError **error) {
    [NSGraphicsContext saveGraphicsState];
    NSString *stage = @"font";
    NSString *fontName = @"unresolved";
    @try {
        // Use a named font instead of the original dynamic system-monospaced font.
        // Keep creation, measurement AND draw
        // inside this boundary: all three can raise Objective-C exceptions.
        NSFont *font = [NSFont fontWithName:@"Menlo" size:12] ?: [NSFont systemFontOfSize:12];
        fontName = font.fontName;
        stage = @"attributes";
        NSString *text = [NSString stringWithFormat:@"%.0f × %.0f", round(pixels.width), round(pixels.height)];
        NSAttributedString *label = [[NSAttributedString alloc] initWithString:text attributes:@{
            NSFontAttributeName: font, NSForegroundColorAttributeName: NSColor.whiteColor
        }];
        stage = @"measurement";
#if FRAMELET_TEST_LABEL_EXCEPTION
        // Reproduce the exact nil-dictionary exception from the crash report.
        [NSDictionary dictionaryWithObject:(id _Nonnull)nil forKey:@"font"];
#endif
        NSSize size = label.size;
        CGFloat x = MIN(MAX(10, CGRectGetMinX(selection) + 6), MAX(10, CGRectGetMaxX(bounds) - size.width - 18));
        CGFloat proposedY = CGRectGetMaxY(selection) + 10;
        CGFloat y = proposedY + size.height + 8 <= CGRectGetMaxY(bounds)
            ? proposedY : MAX(10, CGRectGetMaxY(selection) - size.height - 12);
        [[NSColor.blackColor colorWithAlphaComponent:0.85] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x - 6, y - 4, size.width + 12, size.height + 8)
                                        xRadius:5 yRadius:5] fill];
        stage = @"drawing";
        [label drawAtPoint:NSMakePoint(x, y)];
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"Framelet.CaptureDimensions" code:1 userInfo:@{
                NSLocalizedDescriptionKey: exception.reason ?: @"Text rendering failed",
                @"exception": exception.name,
                @"stage": stage, @"font": fontName, @"pixels": NSStringFromSize(pixels),
                @"stack": [exception.callStackSymbols componentsJoinedByString:@"\n"]
            }];
        }
        return NO;
    } @finally {
        [NSGraphicsContext restoreGraphicsState];
    }
}
