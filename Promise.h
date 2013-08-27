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

#import <Foundation/Foundation.h>

/// Vaguely inspired by JQuery's Promise/Deferred.
/// Extends traditional "Haskell monads" to handle partial results and failures.
/// Much more similar to Rx, see: http://msdn.microsoft.com/en-us/data/gg577609.aspx or https://rx.codeplex.com/


@interface Subscription : NSObject

/// Create a subscription with callbacks which will run on the queue.
- (id)initWithQueue:(NSOperationQueue *)queue done:(void (^)(id))done fail:(void (^)(id))fail progress:(void (^)(id))progress;

/// Has this subscription been cancelled.
- (BOOL)isCancelled;

/// Cancel the subscription. The callbacks are de-allocated and never run after the return of this method.
- (void)cancel;

/// The last partial or completed result or error sent to this subscription.
- (id)poll;
@end

/// A promise of a future calculation which progress and result can be observed.
///
/// subscribe is the central method for subscribing but there is also a handful of convenience methods.
/// What the convenience methods all have in comming is that the callback will always run in the same NSOperationQueue
/// that adds it, if you want to run in a background queue you need to use [promise then:] in combination with
/// [Deferred background:] or [Deferred on:queue run:]. This means you never have to think about moving / the callback
/// to the main thread, you only have to think about it when you do really want to execute / the callback on a separate
/// thread. Default to safe, unsafe is the exception.
///
/// Look out for retain circularities! If you hold a reference to a Promise instance and one of the callbacks holds a
/// reference to "self" then none of those will ever get reclaimed in ARC. In that case use a __weak reference to self.
@interface Promise : NSObject

- (Subscription *)progress:(void(^)(id))callback;

/// Subscribe to a callback.
///
/// If this promise is already resolved or rejected the respective callback are executed before the return of
/// the call to subscribe. If there is a partial result then the progress callback is executed before the return
/// of subscribe.
- (Subscription *)subscribe:(Subscription *)subscription;

/// Convenience method for subscribe with only a done callback running on the current queue.
- (Subscription *)done:(void(^)(id))callback;

/// Convenience method for subscribe with only a fail callback.
- (Subscription *)fail:(void(^)(id))callback;

- (Subscription *)done:(void (^)(id))done fail:(void (^)(id))fail;

- (Subscription *)progress:(void (^)(id))progress done:(void (^)(id))done fail:(void (^)(id))fail;

- (Subscription *)progress:(void (^)(id))progress done:(void (^)(id))done;

- (Subscription *)progressAndDone:(void (^)(id))progress;

/// Did the operation complete (either with an error or with a success).
- (BOOL)isCompleted;

/// Did the operation fail.
- (BOOL)isRejected;

/// Did the operation complete successfully.
- (BOOL)isResolved;

/// The most recent partial or completed result.
- (id)poll;

/// Create a new Promise which transforms the result before passing it to the callback.
/// Runs the transform on the specified NSOperationQueue.
/// Equivalent to monad bind+return.
- (Promise *)transform:(id(^)(id))transformation;

/// Runs the transform on the current queue.
/// Equivalent to monad bind.
- (Promise *)then:(Promise *(^)(id))follower;

/// Wraps the promise in a promise which fails if it hasn't completed before the specified seconds have passed.
- (Promise *)timeout:(int)seconds;
@end

/// A deferred is used by calculations to notify of progress and either resolve or reject it.
@interface Deferred : Promise
+ (instancetype)deferred;

+ (instancetype)rejected:(id)error;

- (id)initWithSubscriptionCallback:(void (^)())callback;

/// Run on a background queue.
+ (Deferred *)background:(void (^)(Deferred *))run;

/// We already have this data so lift it into the Promise monad.
/// Equivalent to monad return.
+ (Deferred *)value:(id)value;

/// Callback is called when the first listener is added.
/// Look out for circularities here! Often needs a __weak reference to self!
+ (instancetype)deferredWithSubscribedCallback:(void (^)())callback;

/// Resolve the Deferred on the given NSOperationQueue.
- (Deferred *)on:(NSOperationQueue *)queue run:(void (^)(Deferred *))run;

/// Report progress.
- (Deferred *)notify:(id)partialResult;

/// Report done.
- (Deferred *)resolve:(id)result;

/// Report error with NSException or NSError (or anything really).
- (Deferred *)reject:(id)error;

/// Return a view of this Deferred that can only be observed, not completed.
- (Promise *)promise;

/// Does this Promise currently have any subscriptions. This method will always return before any subscribed callbacks
/// are executed.
- (BOOL)isSubscribed;
@end
