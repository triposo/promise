//  Copyright 2013 Triposo Inc. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
// documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
// Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
// WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
// OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


#import "Promise.h"
#import "PSYBlockTimer.h"

@implementation Subscription {
    id _result;
    void (^_done)(id);
    void (^_fail)(id);
    void (^_progress)(id);

    NSOperationQueue *_queue;
}

+ (instancetype)subscriptionWithDone:(void (^)(id))done fail:(void (^)(id))fail progress:(void (^)(id))progress {
    return [[self alloc] initWithQueue:[NSOperationQueue currentQueue] done:done fail:fail progress:progress];
}

- (id)initWithQueue:(NSOperationQueue *)queue done:(void (^)(id))done fail:(void (^)(id))fail progress:(void (^)(id))progress {
    self = [super init];
    if (self) {
        _queue = queue;
        _done = [done copy];
        _fail = [fail copy];
        _progress = [progress copy];
    }
    return self;
}

- (BOOL)isCancelled {
    @synchronized (self) {
        return _done == nil && _fail == nil && _progress == nil;
    }
}

- (void)cancel {
    @synchronized (self) {
        _done = nil;
        _fail = nil;
        _progress = nil;
        // The subscription object is deleted from the Promise list at the next notification.
    }
}

- (void)resolve:(id)result {
    void (^done)(id);
    @synchronized (self) {
        _result = result;
        done = _done;
    }
    // Callback has to run outside of the lock, otherwise we deadlock.
    if (done) {
        if ([NSOperationQueue currentQueue] == _queue) {
            done(result);
        } else {
            [_queue addOperationWithBlock:^{
                done(result);
            }];
        }
    }
}

- (void)reject:(id)result {
    void (^fail)(id);
    @synchronized (self) {
        _result = result;
        fail = _fail;
    }
    if (fail) {
        // Callback has to be run outside of the lock, otherwise we deadlock.
        if ([NSOperationQueue currentQueue] == _queue) {
            fail(result);
        } else {
            [_queue addOperationWithBlock:^{
                fail(result);
            }];
        }
    }
}

- (void)notify:(id)result {
    void (^progress)(id);
    @synchronized (self) {
        _result = result;
        progress = _progress;
    }
    if (progress) {
        // Callback has to be run outside of the lock, otherwise we deadlock.
        if ([NSOperationQueue currentQueue] == _queue) {
            progress(result);
        } else {
            [_queue addOperationWithBlock:^{
                progress(result);
            }];
        }
    }
}

- (id)poll {
    @synchronized (self) {
        return _result;
    }
}

@end

// TODO: Something to think about: Signals are Promises without done: callbacks, split up Promise in a base-class Signal and a sub-class Promise with the done: callback.

@implementation Promise

+ (NSArray *)arrayByRepeatingObject:(id)obj times:(NSUInteger)t {
    id arr[t];
    for (NSUInteger i = 0; i < t; ++i) {
        arr[i] = obj;
    }
    return [NSArray arrayWithObjects:arr count:t];
}

+ (Promise *)successfulAsList:(NSArray *)promises deadline:(NSTimeInterval)deadlineSeconds {
    Deferred *result = [Deferred deferred];
    NSMutableArray *results =
            [NSMutableArray arrayWithArray:[self arrayByRepeatingObject:[NSNull null] times:[promises count]]];
    NSMutableSet *stillRunning = [NSMutableSet setWithArray:promises];
    for (NSUInteger index = 0; index < [promises count]; index++) {
        Promise *promise = [promises objectAtIndex:index];
        [promise done:^(id o) {
            @synchronized (stillRunning) {
                [stillRunning removeObject:promise];
                [results setObject:o atIndexedSubscript:index];
            }
            if ([stillRunning count] == 0) {
                [result resolve:results];
            }
        }];
        [promise fail:^(id error) {
            @synchronized (stillRunning) {
                [stillRunning removeObject:promise];
                [results setObject:error atIndexedSubscript:index];
            }
            if ([stillRunning count] == 0) {
                [result resolve:results];
            }
        }];
    }
    if (deadlineSeconds > 0) {
        [NSTimer timerWithTimeInterval:deadlineSeconds repeats:NO usingBlock:^(NSTimer *timer) {
            @synchronized (stillRunning) {
                [stillRunning removeAllObjects];
            }
            [result resolve:results];
        }];
    }
    return result;
}

- (BOOL)isCompleted {
    @synchronized (self) {
        return self.isResolved || self.isRejected;
    }
}

- (Subscription *)done:(void (^)(id))done fail:(void (^)(id))fail {
    return [self subscribe:[Subscription subscriptionWithDone:done fail:fail progress:nil]];
}

- (Subscription *)progress:(void (^)(id))progress done:(void (^)(id))done fail:(void (^)(id))fail {
    return [self subscribe:[Subscription subscriptionWithDone:done fail:fail progress:progress]];
}

- (Subscription *)progress:(void (^)(id))progress done:(void (^)(id))done{
    return [self subscribe:[Subscription subscriptionWithDone:done fail:nil progress:progress]];
}

- (Subscription *)progressAndDone:(void (^)(id))progress {
    return [self subscribe:[Subscription subscriptionWithDone:progress fail:nil progress:progress]];
}

- (Subscription *)any:(void (^)(id))callback {
    return [self subscribe:[Subscription subscriptionWithDone:callback fail:callback progress:callback]];
}

- (Subscription *)done:(void (^)(id))callback {
    return [self subscribe:[Subscription subscriptionWithDone:callback fail:nil progress:nil]];
}

- (Subscription *)fail:(void (^)(id))callback {
    return [self subscribe:[Subscription subscriptionWithDone:nil fail:callback progress:nil]];
}

- (Subscription *)progress:(void (^)(id))callback {
    return [self subscribe:[Subscription subscriptionWithDone:nil fail:nil progress:callback]];
}

- (Subscription *)subscribe:(Subscription *)subscription {
    [NSException raise:NSInternalInconsistencyException format:@"You must override this method."];
    return subscription;
}

- (BOOL)isRejected {
    [NSException raise:NSInternalInconsistencyException format:@"You must override this method."];
    return FALSE;
}

- (BOOL)isResolved {
    [NSException raise:NSInternalInconsistencyException format:@"You must override this method."];
    return FALSE;
}

- (Promise *)transform:(id(^)(id))transformation {
    Deferred *deferred = [Deferred deferred];

    // Pass failures through untransformed.
    [self fail:^(id o) {
        [deferred reject:o];
    }];

    // Transform both partial and full result.
    [self progress:^(id o) {
        [deferred notify:transformation(o)];
    }];
    [self done:^(id o) {
        [deferred resolve:transformation(o)];
    }];
    return deferred;
}

- (Promise *)then:(Promise*(^)(id))follower {
    Deferred *piped = [Deferred deferred];

    // TODO(tirsen): Progress notifications are currently not passed through. Think about how we want to do that, I've no idea.

    [self fail:^(id error) {
        [piped reject:error];
    }];
    [self done:^(id o) {
        Promise *followed = follower(o);
        [followed done:^(id result) {
            [piped resolve:result];
        }];
    }];
    return piped;
}

- (Promise *)on:(NSOperationQueue *)queue then:(Promise*(^)(id))follower {
    Deferred *piped = [Deferred deferred];
    [self progress:^(id o) {
        [queue addOperationWithBlock:^{
            [piped notify:o];
        }];
    }];
    [self fail:^(id error) {
        [queue addOperationWithBlock:^{
            [piped reject:error];
        }];
    }];
    [self done:^(id o) {
        [queue addOperationWithBlock:^{
            Promise *followed = follower(o);
            [followed done:^(id result) {
                [piped resolve:result];
            }];
        }];
    }];
    return piped;
}

- (id)poll {
    [NSException raise:NSInternalInconsistencyException format:@"You must override this method."];
    return nil;
}

- (Promise *)timeout:(int)seconds {
    Deferred *timedout = [Deferred deferred];
    [NSTimer timerWithTimeInterval:seconds repeats:NO usingBlock:^(NSTimer *timer) {
        if (![timedout isCompleted]) {
            [timedout reject:[NSException exceptionWithName:NSPortTimeoutException reason:[NSString stringWithFormat:@"Promise did not complete within %d seconds", seconds] userInfo:nil]];
        }
    }];
    [self done:^(id o) {
        [timedout resolve:o];
    }];
    [self progress:^(id o) {
        [timedout notify:o];
    }];
    [self fail:^(id error) {
        [timedout reject:error];
    }];
    return timedout;
}
@end

@implementation Deferred {
    NSArray *_subscriptions;

    BOOL _isResolved;
    id _result;

    BOOL _isRejected;
    id _error;

    void (^_subscribedCallback)(Deferred *deferred1);
}

static NSOperationQueue *_backgroundQueue;

+ (void)initialize {
    _backgroundQueue = [[NSOperationQueue alloc] init];
    _backgroundQueue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
}


- (id)initWithSubscriptionCallback:(void (^)(Deferred *))callback {
    self = [super init];
    if (self) {
        if (callback) {
            _subscribedCallback = [callback copy];
        }
    }

    return self;
}

- (Subscription *)subscribe:(Subscription *)subscription {
    BOOL isResolved;
    id result;
    BOOL isRejected;
    id error;
    void (^subscribedCallback)(Deferred *deferred1);

    @synchronized (self) {
        if (_subscriptions) {
            _subscriptions = [_subscriptions arrayByAddingObject:subscription];
        } else {
            _subscriptions = [NSArray arrayWithObject:subscription];
        }
        [self removeCancelledSubscriptions];

        // Save current state in local result so we don't have to lock while calling subscriptions.
        isResolved = _isResolved;
        result = _result;
        isRejected = _isRejected;
        error = _error;

        if (_subscribedCallback) {
            subscribedCallback = [_subscribedCallback copy];
            _subscribedCallback = nil;
        }
    }

    if (subscribedCallback) {
        subscribedCallback(self);
    }

    if (isResolved) {
        [subscription resolve:result];
    } else if (isRejected) {
        [subscription reject:error];
    } else if (result) {
        [subscription notify:result];
    }

    return subscription;
}

- (void)removeCancelledSubscriptions {
    // Clean out cancelled subscription.
    @synchronized (self) {
        _subscriptions = [_subscriptions filteredArrayUsingPredicate:
                [NSPredicate predicateWithBlock:^BOOL(Subscription *subscription, NSDictionary *bindings) {
                    return !subscription.isCancelled;
                }]];
    }
}

- (BOOL)isCompleted {
    @synchronized (self) {
        return _isResolved || _isRejected;
    }
}

+ (instancetype)deferred {
    return [[self alloc] initWithSubscriptionCallback:nil];
}

+ (instancetype)rejected:(id)error {
    Deferred *deferred = [[self alloc] initWithSubscriptionCallback:nil];
    [deferred reject:error];
    return deferred;
}

+ (instancetype)runWhenSubscribed:(void (^)(Deferred *))callback {
    return [[self alloc] initWithSubscriptionCallback:callback];
}

- (Deferred *)notify:(id)partialResult {
    NSArray *subscriptions;
    @synchronized (self) {
        _result = partialResult;
        subscriptions = _subscriptions;
    }
    // Listeners are always called without the lock to avoid deadlock.
    for (Subscription *s in subscriptions) {
        [s notify:partialResult];
    }
    return self;
}

+ (Deferred *)value:(id)value {
    Deferred *deferred = [Deferred deferred];
    [deferred resolve:value];
    return deferred;
}

- (Deferred *)reject:(id)error {
    NSArray *subscriptions;
    @synchronized (self) {
        _isRejected = TRUE;
        _error = error;
        subscriptions = _subscriptions;

        // Completed, remove all existing subscriptions.
        _subscriptions = nil;
    }
    // Listeners are always called without the lock to avoid deadlocks etc.
    for (Subscription *s in subscriptions) {
        [s reject:error];
    }
    return self;
}

- (Deferred *)resolve:(id)result {
    NSArray *subscriptions;
    @synchronized (self) {
        _isResolved = TRUE;
        _result = result;
        subscriptions = _subscriptions;

        // Completed, remove all subscriptions.
        _subscriptions = nil;
    }
    // Listeners are always called without the lock to avoid deadlock.
    for (Subscription *s in subscriptions) {
        [s resolve:result];
    }
    return self;
}

- (Deferred *)on:(NSOperationQueue *)queue run:(void (^)(Deferred *))run {
    [queue addOperationWithBlock:^{
        @autoreleasepool {
            run(self);
        }
    }];
    return self;
}

+ (Deferred *)on:(NSOperationQueue *)queue runWhenSubscribed:(void (^)(Deferred *))run {
    return [Deferred runWhenSubscribed:^(Deferred *deferred) {
        [queue addOperationWithBlock:^{
            @autoreleasepool {
                run(deferred);
            }
        }];
    }];
}

+ (Deferred *)background:(void (^)(Deferred *))run {
    return [[Deferred deferred] on:_backgroundQueue run:run];
}

- (Promise *)promise {
    return self;
}

- (id)poll {
    // Double checked locking is broken in Objective-C too but we don't always need the *latest* result here so we can
    // live with the race condition. If we have no result at all then we do lock and see if any other thread has
    // published a result.

    if (_result) {
        return _result;
    } else {
        @synchronized (self) {
            return _result;
        }
    }
}

- (BOOL)isRejected {
    @synchronized (self) {
        return _isRejected;
    }
}

- (BOOL)isResolved {
    @synchronized (self) {
        return _isResolved;
    }
}

- (BOOL)isSubscribed {
    // That would make it possible to do FRP without the "subscription starting" race condition.
    // Something to think about.
    @synchronized (self) {
        [self removeCancelledSubscriptions];
        return (BOOL) [_subscriptions count];
    }
}

- (void)removeAllSubscribers {
    @synchronized (self) {
        _subscriptions = nil;
    }
}
@end