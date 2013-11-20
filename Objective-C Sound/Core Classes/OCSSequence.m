//
//  OCSSequence.m
//  Objective-C Sound
//
//
//  Created by Aurelius Prochazka on 7/1/12.
//  Copyright (c) 2012 Hear For Yourself. All rights reserved.
//

#import "OCSSequence.h"
#import "OCSManager.h"

@interface OCSSequence () {
    NSTimer *timer;
    BOOL isPlaying;
    unsigned int index;
}
@end

@implementation OCSSequence

// -----------------------------------------------------------------------------
#  pragma mark - Initialization
// -----------------------------------------------------------------------------

- (id) init {
    self = [super init];
    if (self) {
        _events = [[NSMutableArray alloc] init];
        _times  = [[NSMutableArray alloc] init];
        isPlaying = NO;
    }
    return self;
}

- (void)addEvent:(OCSEvent *)event 
{
    [self addEvent:event afterDuration:0.0f];
}

- (void)addEvent:(OCSEvent *)event 
          atTime:(float)timeSinceStart;
{
    NSNumber *time = [NSNumber numberWithFloat:timeSinceStart];
    
    int insertionIndex = 0;
    BOOL doInsertion = NO;
    for (NSNumber *t in _times) {
        if (t.floatValue > timeSinceStart) {
            doInsertion = YES;
            break;
        }
        insertionIndex++;
    }
    if (doInsertion) {
        [_events insertObject:event atIndex:insertionIndex];
        [_times  insertObject:time  atIndex:insertionIndex];
    } else {
        [_events addObject:event];
        [_times addObject:time];
    }
}

- (void)addEvent:(OCSEvent *)event 
   afterDuration:(float)timeSinceLastEventStarted;
{
    [_events addObject:event];
    NSNumber *time = @0.0F;
    if ([_times count] > 0) {
        //OCSEvent *lastEvent = [_events lastObject];
        time = [NSNumber numberWithFloat:([[_times lastObject] floatValue] + timeSinceLastEventStarted)];
    }
    [_times addObject:time];
}

// -----------------------------------------------------------------------------
#  pragma mark - Sequence Playback Control
// -----------------------------------------------------------------------------

- (void)play
{
    index = 0;
    isPlaying = YES;
    // Delay playback until first event is set to start.
    timer = [NSTimer scheduledTimerWithTimeInterval:[_times[0] floatValue]
                                             target:self
                                           selector:@selector(playNextEventInSequence:)
                                           userInfo:nil
                                            repeats:NO];
}

- (void)pause
{
    isPlaying = NO;
}

- (void)stop
{
    isPlaying = NO;
    for (OCSEvent *event in _events) {
        if (event.note) {
            [event.note stop];
            [timer invalidate];
            timer = nil;
        }
    }
}


// Cue up the next event to be triggered.
- (void)playNextEventInSequence:(NSTimer *)aTimer;
{
    OCSEvent *event = _events[index];
    [[OCSManager sharedOCSManager] triggerEvent:event];

    if (index < [_times count]-1 && isPlaying) {
        float timeUntilNextEvent = [_times[index+1] floatValue] -
                                   [_times[index]   floatValue];
        
        timer = [NSTimer scheduledTimerWithTimeInterval:timeUntilNextEvent
                                                 target:self 
                                               selector:@selector(playNextEventInSequence:) 
                                               userInfo:nil 
                                                repeats:NO];
        index++;

    } else {
        [timer invalidate];
        timer = nil;
    }
}


@end
