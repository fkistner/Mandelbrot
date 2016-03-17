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

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.scrollView.maximumZoomScale = 1 << 19;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)zoomOutGestureRecognized:(id)sender {

}
- (IBAction)zoomInGestureRecognized:(UIGestureRecognizer*)sender {
    
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return self.mandelbrotView;
}

- (BOOL)scrollViewShouldScrollToTop:(UIScrollView *)scrollView
{
    return NO;
}

@end
