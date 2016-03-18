//
//  MandelbrotScrollView.m
//  Mandelbrot
//
//  Created by Florian Kistner on 15/03/16.
//  Copyright © 2016 Florian Kistner. All rights reserved.
//

#import "MandelbrotView.h"
#import <complex.h>
#import <libkern/OSAtomic.h>

@import CoreGraphics;

@implementation MandelbrotView {
    
    volatile OSSpinLock colorLock;
    CGColorSpaceRef colorSpace;
    uint8_t colorPalette[3*(UINT8_MAX+1)];
    
    volatile OSSpinLock coordLock;
    CGAffineTransform coordTransform;
}

#pragma mark - Constants

const size_t kMandelbrotViewLevelsOfDetail = 19;
const size_t kTileSize = 256;
const size_t kBitsPerComp = sizeof(uint8_t) * 8;
const size_t kCompPerPixel = 1;
const CGBitmapInfo kBitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaNone;

#pragma mark - Class

+ (Class)layerClass
{
    return [CATiledLayer class];
}

#pragma mark - Lifecycle

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self)
    {
        colorLock = coordLock = OS_SPINLOCK_INIT;
        colorSpace = nil;
        self.baseHue = .65;
        
        CATiledLayer* layer = (CATiledLayer*)self.layer;
        layer.levelsOfDetailBias = kMandelbrotViewLevelsOfDetail;
        layer.tileSize = CGSizeMake(kTileSize, kTileSize);
    }
    return self;
}

- (void)dealloc {
    if (colorSpace != nil) CGColorSpaceRelease(colorSpace);
}

#pragma mark - Custom Accessors

- (void)setBaseHue:(CGFloat)hue {
    _baseHue = hue;
    // hide view until new palette is available
    [self setHidden:YES];
    
    // do not block main queue with palette initialization
    dispatch_block_t initPalette = dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, ^{
        
        CGColorSpaceRef newColorSpace;
        if (isnan(hue)) {
            newColorSpace = CGColorSpaceCreateDeviceGray();
        } else {
            
            for (int p = 0, i = 0; i <= UINT8_MAX; i++)
            {
                CGFloat c = 1. - (double)i/UINT8_MAX;
                UIColor* color = [UIColor colorWithHue:fmod(c+hue, .95) saturation:.75 brightness:MIN(c*10, .75) alpha:1.];
                CGFloat comp[3];
                [color getRed:&(comp[0]) green:&(comp[1]) blue:&(comp[2]) alpha:NULL];
                
                colorPalette[p++] = comp[0] * UINT8_MAX;
                colorPalette[p++] = comp[1] * UINT8_MAX;
                colorPalette[p++] = comp[2] * UINT8_MAX;
            }
            
            newColorSpace = CGColorSpaceCreateIndexed(CGColorSpaceCreateDeviceRGB(), UINT8_MAX, colorPalette);
        }
        
        // safely switch color space -> drawRect might still be in the process of retaining the color space
        OSSpinLockLock(&colorLock);
        if (colorSpace != nil) CGColorSpaceRelease(colorSpace);
        colorSpace = newColorSpace;
        OSSpinLockUnlock(&colorLock);
    });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), initPalette);
    dispatch_block_notify(initPalette, dispatch_get_main_queue(), ^{
        // make mandelbrot visible, once the palette is generated
        [self setHidden:NO];
        [self setNeedsDisplay];
    });
}

#pragma mark - Public

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGAffineTransform coord = [self calculateCoordTransform];
    OSSpinLockLock(&coordLock);
    coordTransform = coord;
    OSSpinLockUnlock(&coordLock);
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    [self drawMandelbrot:context forRect:rect];
}

#pragma mark - Private

/**
 * Precomputes the required affine transformation matrix to map points with the bounds of the view to coordinates of the visualization.
 */
- (CGAffineTransform)calculateCoordTransform {
    CGRect coordRect;
    coordRect.size = CGSizeMake(3., 2.5);
    
    CGSize viewSize = self.bounds.size;
    CGFloat viewRatio = viewSize.height / viewSize.width;
    CGFloat coordRatio = coordRect.size.height / coordRect.size.width;

    CGFloat scale;
    if (viewRatio > coordRatio) {
        scale = coordRect.size.width / viewSize.width;
        coordRect.size.height = coordRect.size.width * viewRatio;
    } else {
        scale = coordRect.size.height / viewSize.height;
        coordRect.size.width = coordRect.size.height / viewRatio;
    }
    
    coordRect.origin.x = -coordRect.size.width  / 2. * 1.5;
    coordRect.origin.y = -coordRect.size.height / 2.;
    
    return CGAffineTransformScale(CGAffineTransformMakeTranslation(coordRect.origin.x, coordRect.origin.y), scale, scale);
}

/**
 * Draws the mandelbrot visualization for the given rect into the given context.
 * @param rect The rect inside the bounds of the MandelbrotView to draw
 */
- (void)drawMandelbrot:(CGContextRef)context forRect:(CGRect)rect {
    // safely get transform for current view size -> view might currently be changing size
    OSSpinLockLock(&coordLock);
    CGAffineTransform coord = coordTransform;
    OSSpinLockUnlock(&coordLock);
    
    // combine transforms to create final device pixels to coordinate transform
    CGAffineTransform transform = CGAffineTransformConcat(CGAffineTransformInvert(CGContextGetCTM(context)), coord);
    
    // calculate size of pixel buffer
    CGRect targetRect = CGContextConvertRectToDeviceSpace(context, rect);
    size_t width  = targetRect.size.width;
    size_t height = targetRect.size.height;
    size_t bitmapSize = kCompPerPixel * width * height;
    size_t bytesPerRow = kBitsPerComp / 8 * kCompPerPixel * width;
    
    uint8_t data[bitmapSize]; // maximum length should be fine for stack
    
    for (int p = 0, y = 0; y < height; y++)
    {
        for (int x = 0; x < width; x++)
        {
            // map device pixel to coordinates / complex number
            CGPoint coordPoint = CGPointApplyAffineTransform(CGPointMake(x, y), transform);
            double complex z_0 = CMPLX(coordPoint.x, coordPoint.y);
            
            const int kItensityStart = UINT8_MAX;
            uint8_t itensity = 0;
            
            // only do escape analysis, when not definitely in set
            if (!IsDefinitelyInMandelbrotSet(z_0))
            {
                // escape time algorithm
                double complex z = CMPLX(0, 0);
                for (itensity = kItensityStart; itensity > 0; itensity--)
                {
                    z = csquare(z) + z_0;
                    
                    double zAbsSquared = absSquared(z);
                    // continue iterating even when number is definitely not in mandelbrot to be able to smooth intensity gradients
                    if (zAbsSquared > 1<<16)
                    {
                        // smoothing
                        double nu = log2(log2(zAbsSquared) / 2);
                        itensity = round(itensity - 1 + nu);
                        break;
                    }
                }
            }

            // write intensity as an integer in the 0...255 interval
            data[p++] = itensity;
        }
    }
    
    
    // safely retain color space -> other thread might try to switch color space
    OSSpinLockLock(&colorLock);
    CGColorSpaceRef cs = colorSpace;
    CGColorSpaceRetain(cs);
    OSSpinLockUnlock(&colorLock);
    
    // create image with data of stack buffer
    CGDataProviderRef dataProvider = CGDataProviderCreateWithData(NULL, data, sizeof(data), NULL);
    CGImageRef image = CGImageCreate(width, height, kBitsPerComp, kBitsPerComp*kCompPerPixel, bytesPerRow, cs, kBitmapInfo, dataProvider, NULL, YES, kCGRenderingIntentDefault);
    
    // draw stack buffer to layer
    CGContextDrawImage(context, rect, image);
    
    CGImageRelease(image);
    CGDataProviderRelease(dataProvider);
    CGColorSpaceRelease(cs);
}

#pragma mark - Helper functions

/**
 * Calculates n^2 for n ∈ Q.
 */
double square(double n) { return n*n; }
/**
 * Calculates z^2 for n ∈ C.
 */
double complex csquare(double complex z) { return z*z; }
/**
 * Calculates |z|^2 for z ∈ C.
 */
double absSquared(double complex z) { return square(creal(z)) + square(cimag(z)); }

/**
 * Checks whether z ∈ C is in the Cardioid or period-1 bulb of the mandelbrot set.
 */
bool IsDefinitelyInMandelbrotSet(double complex z) {
    double xMinusQuarter = creal(z) - .25;
    double ySquared = square(cimag(z));
    double q = square(xMinusQuarter) + ySquared;
    double xPlusOne = creal(z) + 1;
    
    return (q * (q + xMinusQuarter) < .25 * ySquared) // Cardioid
        || (square(xPlusOne) + ySquared < .0625);     // Period-1 bulb
}

@end
