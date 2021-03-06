//
//  JEFScaleToFillImageView.m
//  Jeff
//
//  Created by Brandon Evans on 2014-07-16.
//  Copyright (c) 2014 Brandon Evans. All rights reserved.
//

#import "JEFScaleToFillImageView.h"

@implementation JEFScaleToFillImageView

- (id)init {
    self = [super init];
    if (self) {
        super.imageScaling = NSImageScaleAxesIndependently;
    }

    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        super.imageScaling = NSImageScaleAxesIndependently;
    }

    return self;
}

- (id)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        super.imageScaling = NSImageScaleAxesIndependently;
    }

    return self;
}

- (void)setImageScaling:(NSImageScaling)newScaling {
    super.imageScaling = NSImageScaleAxesIndependently;
}

- (void)setImage:(NSImage *)image {
    if (!image) {
        [super setImage:image];
        return;
    }

    NSImage *scaleToFillImage = [NSImage imageWithSize:self.bounds.size flipped:NO drawingHandler:^BOOL (NSRect dstRect) {
        NSSize imageSize = [image size];
        NSSize imageViewSize = self.bounds.size; // Yes, do not use dstRect.

        NSSize newImageSize = imageSize;

        CGFloat imageAspectRatio = imageSize.height / imageSize.width;
        CGFloat imageViewAspectRatio = imageViewSize.height / imageViewSize.width;

        if (imageAspectRatio < imageViewAspectRatio) {
            // Image is more horizontal than the view. Image left and right borders need to be cropped.
            newImageSize.width = imageSize.height / imageViewAspectRatio;
        }
        else {
            // Image is more vertical than the view. Image top and bottom borders need to be cropped.
            newImageSize.height = imageSize.width * imageViewAspectRatio;
        }

        NSRect srcRect = NSMakeRect(imageSize.width / 2.0 - newImageSize.width / 2.0,
                                    imageSize.height / 2.0 - newImageSize.height / 2.0,
                                    newImageSize.width,
                                    newImageSize.height);

        [NSGraphicsContext currentContext].imageInterpolation = NSImageInterpolationHigh;

        [image drawInRect:dstRect fromRect:srcRect operation:NSCompositeCopy fraction:1.0 respectFlipped:YES hints:@{ NSImageHintInterpolation : @(NSImageInterpolationHigh) }];

        return YES;
    }];

    // Automatically redraw with new frame size of the image view
    scaleToFillImage.cacheMode = NSImageCacheNever;

    [super setImage:scaleToFillImage];
}

@end
