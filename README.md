Promise by Triposo
==================

An implementation of futures/promises for Objective-C. Inspired by JQuery's Promise/Deferred.

Implement a long running background task:

```Objective-C
- (Promise *)longRunningOperation {
    return [Deferred background:^(Deferred *deferred) {
        id result;
        // ... do something that takes a long time ...
        [deferred resolve:result];
    }];
}


```

Or request a JSON document from a server using AFNetworking:

```Objective-C
- (Promise *)getUpcomingMovies {
    Deferred *result = [Deferred deferred];
    AFHTTPClient *client = [AFHTTPClient clientWithBaseURL:[NSURL URLWithString:@"http://api.rottentomatoes.com/api/public/v1.0"]];
    [client getPath:@"/lists/movies/upcoming.json" parameters:@{@"apikey" : @"[your_api_key]"}
            success:^(AFHTTPRequestOperation *operation, id responseObject) {
                [result resolve:responseObject];
            }
            failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                [result reject:error];
            }];
    return result;
}
```


Use it:

```Objective-C
- (void)viewDidLoad {
    [[self getUpcomingMovies] done:^(id upcomingMoviewJson) {
        // update the UI with the result, the done callback is automatically running on the main queue
        // (or whatever queue you're on when you call done:)
    }];
}
```

Chain two long running operations together:

```Objective-C
[[self getUpcomingMovies] then:^Promise *(id upcomingMovies) {
    return [self longRunningOperation:upcomingMovies];
}];
```

Transform the result of a promise (returns a new promise):

```Objective-C
[[self getUpcomingMovies] transform:^Promise *(id upcomingMovies) {
    // Transformation will run on the current queue (probably main) so make sure it's not too slow
    // If it's slow use then: instead.
    return [upcomingMovies objectForKey:@"total"];
}];
```





[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/triposo/promise/trend.png)](https://bitdeli.com/free "Bitdeli Badge")

