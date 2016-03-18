//
//  ViewController.m
//  Mandelbrot
//
//  Created by Florian Kistner on 15/03/16.
//  Copyright © 2016 Florian Kistner. All rights reserved.
//

#import "ViewController.h"
#import "MandelbrotView.h"

@interface ViewController () <UIScrollViewDelegate>

@property (weak, nonatomic) IBOutlet UIScrollView *scrollView;
@property (weak, nonatomic) IBOutlet MandelbrotView *mandelbrotView;
@property (weak, nonatomic) IBOutlet UISlider *hueSlider;

@end

@implementation ViewController

#pragma mark - UIViewController

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.scrollView.maximumZoomScale = 1 << kMandelbrotViewLevelsOfDetail;
    self.hueSlider.value = self.mandelbrotView.baseHue;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    // redraw mandelbrot after rotation / view resize
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.mandelbrotView setNeedsDisplay];
    }];
}

#pragma mark - IBActions

- (IBAction)zoomOutGestureRecognized:(UIGestureRecognizer*)sender {
    CGFloat newZoomScale = exp2(ceil(log2(self.scrollView.zoomScale) - 1.));
    [self.scrollView setZoomScale:newZoomScale animated:YES];
}

- (IBAction)zoomInGestureRecognized:(UIGestureRecognizer*)sender {
    CGFloat newZoomScale = exp2(floor(log2(self.scrollView.zoomScale) + 1.));
    
    CGPoint newCenter = [sender locationInView:self.mandelbrotView];
    CGRect rect;
    rect.size = self.mandelbrotView.bounds.size;
    rect.size.width  /= newZoomScale;
    rect.size.height /= newZoomScale;
    rect.origin.x = newCenter.x - rect.size.width  / 2.;
    rect.origin.y = newCenter.y - rect.size.height / 2.;
    
    [self.scrollView zoomToRect:rect animated:YES];
}

- (IBAction)toggleHue:(UIBarButtonItem *)sender {
    if (isnan(self.mandelbrotView.baseHue))
    {
        sender.title = @"Hue";
        self.hueSlider.enabled = YES;
        self.mandelbrotView.baseHue = self.hueSlider.value;
    } else {
        sender.title = @"Gray";
        self.hueSlider.enabled = NO;
        self.mandelbrotView.baseHue = NAN;
    }
}

- (IBAction)hueChanged:(UISlider *)sender {
    self.mandelbrotView.baseHue = sender.value;
}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.mandelbrotView;
}

- (BOOL)scrollViewShouldScrollToTop:(UIScrollView *)scrollView {
    return NO;
}

@end
