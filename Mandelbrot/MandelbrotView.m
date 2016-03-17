//
//  MandelbrotScrollView.m
//  Mandelbrot
//
//  Created by Florian Kistner on 15/03/16.
//  Copyright © 2016 Florian Kistner. All rights reserved.
//

#import "MandelbrotView.h"

#include <complex.h>

@import CoreGraphics;

@implementation MandelbrotView {
    CGColorSpaceRef colorSpace;
    uint8_t colorPalette[3*(UINT8_MAX+1)];
}

+ (Class)layerClass
{
    return [CATiledLayer class];
}

const int kTileSize = 256;

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self)
    {
        for (int p = 0, i = 0; i <= UINT8_MAX; i++)
        {
            CGFloat c = (double)i/UINT8_MAX;
            UIColor* color = [UIColor colorWithHue:fmod(c+.65, .95) saturation:.75 brightness:MIN(c*10, .75) alpha:1.];
            CGFloat comp[3];
            [color getRed:&(comp[0]) green:&(comp[1]) blue:&(comp[2]) alpha:NULL];
            
            colorPalette[p++] = comp[0] * UINT8_MAX;
            colorPalette[p++] = comp[1] * UINT8_MAX;
            colorPalette[p++] = comp[2] * UINT8_MAX;
        }
        colorSpace = CGColorSpaceCreateIndexed(CGColorSpaceCreateDeviceRGB(), UINT8_MAX, colorPalette);

        CATiledLayer* layer = (CATiledLayer*)self.layer;
        //layer.levelsOfDetail     = 1 << 18;
        layer.levelsOfDetailBias = 19;//log2(CGFLOAT_MAX);// 18; //1 << 10;//layer.levelsOfDetail - 1;
        layer.tileSize = CGSizeMake(kTileSize, kTileSize);
    }
    return self;
}

- (void)dealloc
{
    CGColorSpaceRelease(colorSpace);
}

- (void)layoutSubviews
{
    [self.layer setNeedsDisplayInRect:self.bounds];
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    [self drawMandelbrot:context forRect:rect];
}

bool IsDefinitelyInMandelbrotSet(double complex z)
{
    double xMinusQuarter = creal(z) - .25;
    double ySquared = cimag(z)*cimag(z);
    double q = xMinusQuarter*xMinusQuarter + ySquared;
    double xPlusOne = creal(z) + 1;
    
    return (q*(q+xMinusQuarter) < .25*ySquared)    // Cardioid
        || (xPlusOne*xPlusOne + ySquared < .0625); // Period-1 bulb
}

- (void)drawMandelbrot:(CGContextRef)context forRect:(CGRect)rect
{
    const int kBitsPerComp = sizeof(uint8_t) * 8;
    const int kCompPerPixel = 1;
    const CGBitmapInfo kBitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaNone;
    
    CGRect targetRect = CGContextConvertRectToDeviceSpace(context, rect);
    double scaleReal = 3. / self.bounds.size.width;
    double scaleImag = 2. / self.bounds.size.height;
    
    int bitmapSize = kCompPerPixel * targetRect.size.width * targetRect.size.height;
    int bytesPerRow = kBitsPerComp * kCompPerPixel * targetRect.size.width / 8;
    
    CGAffineTransform userTransform = CGAffineTransformInvert(CGContextGetCTM(context));
    CGAffineTransform viewTransform = CGAffineTransformScale(CGAffineTransformMakeTranslation(-2.25, -1.), scaleReal, scaleImag);
    CGAffineTransform transform = CGAffineTransformConcat(userTransform, viewTransform);
    
    uint8_t data[bitmapSize]; // maximum length kTileSize^2 -> fine for stack
    
    for (int p = 0, y = 0; y < targetRect.size.height; y++)
    {
        for (int x = 0; x < targetRect.size.width; x++)
        {
            CGPoint userPoint = CGPointApplyAffineTransform(CGPointMake(x, y), transform);
            double complex z = CMPLX(userPoint.x, userPoint.y);
            
            const int kItMax = UINT8_MAX;
            uint8_t it = UINT8_MAX;
            
            // Only do escape analysis, when not definitely in set
            if (!IsDefinitelyInMandelbrotSet(z))
            {
                // escape time algorithm
                double complex n = CMPLX(0, 0);
                for (it = 0; it < kItMax; it++)
                {
                    n = n*n + z;
                    double nAbsSquared = creal(n)*creal(n) + cimag(n)*cimag(n);
                    
                    if (nAbsSquared > 4)
                    {
                        // Smoothing?
                        /*double nu = log2(log2(nAbsSquared) / 2);
                        color = (it + 1) - nu;*/
                        break;
                    }
                }
            }

            data[p++] = it;
        }
    }
    
    CGDataProviderRef dataProvider = CGDataProviderCreateWithData(NULL, data, bitmapSize, NULL);
    CGImageRef image = CGImageCreate(targetRect.size.width, targetRect.size.height, kBitsPerComp, kBitsPerComp*kCompPerPixel, bytesPerRow, colorSpace, kBitmapInfo, dataProvider, NULL, YES, kCGRenderingIntentDefault);
    
    CGContextDrawImage(context, rect, image);
    
    CGImageRelease(image);
    CGDataProviderRelease(dataProvider);
}

@end
