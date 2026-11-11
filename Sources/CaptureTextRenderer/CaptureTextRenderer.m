#import "CaptureTextRenderer.h"

static NSError *FLRenderingError(NSString *domain, NSException *exception, NSString *stage, NSString *fontName) {
    return [NSError errorWithDomain:domain code:1 userInfo:@{
        NSLocalizedDescriptionKey: exception.reason ?: @"Text rendering failed",
        @"exception": exception.name, @"stage": stage, @"font": fontName,
        @"stack": [exception.callStackSymbols componentsJoinedByString:@"\n"]
    }];
}

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
            *error = FLRenderingError(@"Framelet.CaptureDimensions", exception, stage, fontName);
        }
        return NO;
    } @finally {
        [NSGraphicsContext restoreGraphicsState];
    }
}


BOOL FLDrawCaptureLoupeText(CGRect panel, NSString *coordinates, NSString *color,
                           NSString *message, NSString *hint, NSError **error) {
    [NSGraphicsContext saveGraphicsState];
    NSString *stage = @"font";
    NSString *fontName = @"unresolved";
    @try {
        NSFont *mono = [NSFont fontWithName:@"Menlo" size:11] ?: [NSFont systemFontOfSize:11];
        fontName = mono.fontName ?: @"unresolved";
        NSDictionary *values = @{ NSFontAttributeName: mono, NSForegroundColorAttributeName: NSColor.whiteColor };
        CGFloat x = CGRectGetMinX(panel) + 12;
        CGFloat y = CGRectGetMinY(panel);
        stage = @"coordinates";
#if FRAMELET_TEST_LOUPE_EXCEPTION
        [NSDictionary dictionaryWithObject:(id _Nonnull)nil forKey:@"font"];
#endif
        [coordinates drawAtPoint:NSMakePoint(x, y + 71) withAttributes:values];
        stage = @"color";
        [color drawAtPoint:NSMakePoint(x, y + 54) withAttributes:values];

        stage = @"hint font";
        NSFont *hintFont = [NSFont systemFontOfSize:10];
        fontName = hintFont.fontName ?: @"unresolved";
        stage = @"shortcut hint";
        [message drawAtPoint:NSMakePoint(x, y + 39) withAttributes:@{
            NSFontAttributeName: hintFont, NSForegroundColorAttributeName: NSColor.systemYellowColor
        }];
        stage = @"keyboard hint";
        [@"方向键微调 · 空格设起点" drawAtPoint:NSMakePoint(x, y + 23) withAttributes:@{
            NSFontAttributeName: hintFont, NSForegroundColorAttributeName: NSColor.whiteColor
        }];
        stage = @"selection hint";
        [hint drawAtPoint:NSMakePoint(x, y + 7) withAttributes:@{
            NSFontAttributeName: hintFont, NSForegroundColorAttributeName: [NSColor colorWithWhite:0.75 alpha:1]
        }];
        return YES;
    } @catch (NSException *exception) {
        if (error) *error = FLRenderingError(@"Framelet.CaptureLoupe", exception, stage, fontName);
        return NO;
    } @finally {
        [NSGraphicsContext restoreGraphicsState];
    }
}
