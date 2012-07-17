//
//  Helper.h
//  Objective-Csound Example
//
//  Created by Aurelius Prochazka on 7/3/12.
//  Copyright (c) 2012 Hear For Yourself. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "OCSManager.h"

@interface Helper : NSObject

+ (void)setSlider:(UISlider *)slider 
        withValue:(float)value 
          minimum:(float)minimum 
          maximum:(float)maximum;

+ (void)setSlider:(UISlider *)slider 
    usingProperty:(OCSProperty *)property;

+ (float)scaleValueFromSlider:(UISlider *)slider 
                      minimum:(float)minimum 
                      maximum:(float)maximum;



+ (float)randomFloatFrom:(float)minimum to:(float)maximum; 


@end
