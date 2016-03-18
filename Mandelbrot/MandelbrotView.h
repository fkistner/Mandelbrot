//
//  MandelbrotScrollView.h
//  Mandelbrot
//
//  Created by Florian Kistner on 15/03/16.
//  Copyright © 2016 Florian Kistner. All rights reserved.
//

#import <UIKit/UIKit.h>

/**
 * The levels of detail supported.
 */
extern const size_t kMandelbrotViewLevelsOfDetail;

@interface MandelbrotView : UIView

/**
 * Sets the base hue for the color palette of the visualization.
 * @param hue Base hue for palette generation, or NAN for monochrome.
 */
@property (nonatomic) CGFloat baseHue;

@end
