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

+ (Class)layerClass
{
    return [CATiledLayer class];
}

const size_t kTileSize = 256;
const size_t kBitsPerComp = sizeof(uint8_t) * 8;
const size_t kCompPerPixel = 1;
const CGBitmapInfo kBitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaNone;

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self)
    {
        colorLock = coordLock = OS_SPINLOCK_INIT;
        colorSpace = nil;
        self.hue = .65;
        
        CATiledLayer* layer = (CATiledLayer*)self.layer;
        layer.levelsOfDetailBias = 19;//log2(CGFLOAT_MAX);// 18; //1 << 10;//layer.levelsOfDetail - 1;
        layer.tileSize = CGSizeMake(kTileSize, kTileSize);
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGAffineTransform coord = [self calculateCoordTransform];;
    OSSpinLockLock(&coordLock);
    coordTransform = coord;
    OSSpinLockUnlock(&coordLock);
}

- (void)setHue:(CGFloat)hue {
    _hue = hue;
    [self setHidden:YES];
    
    // do not block main queue with palette initialization
    dispatch_block_t initPalette = dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, ^{
        
        CGColorSpaceRef newColorSpace;
        if (isnan(hue)) {
            newColorSpace = CGColorSpaceCreateDeviceGray();
        } else {
        
            for (int p = 0, i = 0; i <= UINT8_MAX; i++)
            {
                CGFloat c = (double)i/UINT8_MAX;
                UIColor* color = [UIColor colorWithHue:fmod(c+hue, .95) saturation:.75 brightness:MIN(c*10, .75) alpha:1.];
                CGFloat comp[3];
                [color getRed:&(comp[0]) green:&(comp[1]) blue:&(comp[2]) alpha:NULL];
                
                colorPalette[p++] = comp[0] * UINT8_MAX;
                colorPalette[p++] = comp[1] * UINT8_MAX;
                colorPalette[p++] = comp[2] * UINT8_MAX;
            }
            
            newColorSpace = CGColorSpaceCreateIndexed(CGColorSpaceCreateDeviceRGB(), UINT8_MAX, colorPalette);
        }
        
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

- (void)dealloc
{
    CGColorSpaceRelease(colorSpace);
}


- (CGAffineTransform)calculateCoordTransform
{
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

- (void)drawRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    [self drawMandelbrot:context forRect:rect];
}

double square(double n) { return n*n; }
double complex csquare(double complex n) { return n*n; }

bool IsDefinitelyInMandelbrotSet(double complex z)
{
    double xMinusQuarter = creal(z) - .25;
    double ySquared = square(cimag(z));
    double q = square(xMinusQuarter) + ySquared;
    double xPlusOne = creal(z) + 1;
    
    return (q * (q + xMinusQuarter) < .25 * ySquared) // Cardioid
        || (square(xPlusOne) + ySquared < .0625);     // Period-1 bulb
}

- (void)drawMandelbrot:(CGContextRef)context forRect:(CGRect)rect
{
    OSSpinLockLock(&coordLock);
    CGAffineTransform coord = coordTransform;
    OSSpinLockUnlock(&coordLock);
    
    CGAffineTransform transform = CGAffineTransformConcat(CGAffineTransformInvert(CGContextGetCTM(context)), coord);
    
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
            CGPoint userPoint = CGPointApplyAffineTransform(CGPointMake(x, y), transform);
            double complex z_0 = CMPLX(userPoint.x, userPoint.y);
            
            const int kItMax = UINT8_MAX;
            uint8_t it = kItMax;
            
            // Only do escape analysis, when not definitely in set
            if (!IsDefinitelyInMandelbrotSet(z_0))
            {
                // escape time algorithm
                double complex z = CMPLX(0, 0);
                for (it = 0; it < kItMax; it++)
                {
                    z = csquare(z) + z_0;
                    
                    double zAbsSquared = square(creal(z)) + square(cimag(z));
                    if (zAbsSquared > 1<<16)
                    {
                        // Smoothing
                        double nu = log2(log2(zAbsSquared) / 2);
                        it = round(it + 1 - nu);
                        break;
                    }
                }
            }

            data[p++] = it;
        }
    }
    
    
    // draw stack buffer to layer
    
    OSSpinLockLock(&colorLock);
    CGColorSpaceRef cs = colorSpace;
    CGColorSpaceRetain(cs);
    OSSpinLockUnlock(&colorLock);
    
    CGDataProviderRef dataProvider = CGDataProviderCreateWithData(NULL, data, sizeof(data), NULL);
    CGImageRef image = CGImageCreate(width, height, kBitsPerComp, kBitsPerComp*kCompPerPixel, bytesPerRow, cs, kBitmapInfo, dataProvider, NULL, YES, kCGRenderingIntentDefault);
    
    CGContextDrawImage(context, rect, image);
    
    CGImageRelease(image);
    CGDataProviderRelease(dataProvider);
    CGColorSpaceRelease(cs);
}

@end
