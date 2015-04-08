//
//  BNCServerInterface.m
//  Branch-SDK
//
//  Created by Alex Austin on 6/6/14.
//  Copyright (c) 2014 Branch Metrics. All rights reserved.
//

#import "BNCServerInterface.h"
#import "BNCPreferenceHelper.h"
#import "BNCConfig.h"
#import "BNCLinkData.h"
#import "BNCEncodingUtils.h"
#import "BNCError.h"

@interface BNCServerInterface ()

@property (strong, nonatomic) NSOperationQueue *operationQueue;

@end

@implementation BNCServerInterface

- (id)init {
    if (self = [super init]) {
        self.operationQueue = [[NSOperationQueue alloc] init];
    }
    
    return self;
}

#pragma mark - GET methods

- (void)getRequest:(NSDictionary *)params url:(NSString *)url andTag:(NSString *)requestTag callback:(BNCServerCallback)callback {
    [self getRequest:params url:url andTag:requestTag retryNumber:0 log:YES callback:callback];
}

- (void)getRequest:(NSDictionary *)params url:(NSString *)url andTag:(NSString *)requestTag log:(BOOL)log callback:(BNCServerCallback)callback {
    [self getRequest:params url:url andTag:requestTag retryNumber:0 log:log callback:callback];
}

- (void)getRequest:(NSDictionary *)params url:(NSString *)url andTag:(NSString *)requestTag retryNumber:(NSInteger)retryNumber log:(BOOL)log callback:(BNCServerCallback)callback {
    NSURLRequest *request = [self prepareGetRequest:params url:url retryNumber:retryNumber log:log];
    [self genericHTTPRequest:request withTag:requestTag andLinkData:nil retryNumber:retryNumber log:log callback:callback];
}

- (BNCServerResponse *)getRequest:(NSDictionary *)params url:(NSString *)url andTag:(NSString *)requestTag {
    return [self getRequest:params url:url andTag:requestTag log:YES];
}

- (BNCServerResponse *)getRequest:(NSDictionary *)params url:(NSString *)url andTag:(NSString *)requestTag log:(BOOL)log {
    NSURLRequest *request = [self prepareGetRequest:params url:url retryNumber:0 log:log];
    return [self genericHTTPRequest:request withTag:requestTag andLinkData:nil];
}


#pragma mark - POST methods

- (void)postRequest:(NSDictionary *)post url:(NSString *)url andTag:(NSString *)requestTag callback:(BNCServerCallback)callback {
    [self postRequest:post url:url andTag:requestTag andLinkData:nil retryNumber:0 log:YES callback:callback];
}

- (void)postRequest:(NSDictionary *)post url:(NSString *)url andTag:(NSString *)requestTag log:(BOOL)log callback:(BNCServerCallback)callback {
    [self postRequest:post url:url andTag:requestTag andLinkData:nil retryNumber:0 log:log callback:callback];
}

- (void)postRequest:(NSDictionary *)post url:(NSString *)url andTag:(NSString *)requestTag andLinkData:(BNCLinkData *)linkData callback:(BNCServerCallback)callback {
    [self postRequest:post url:url andTag:requestTag andLinkData:linkData retryNumber:0 log:YES callback:callback];
}

- (void)postRequest:(NSDictionary *)post url:(NSString *)url andTag:(NSString *)requestTag andLinkData:(BNCLinkData *)linkData log:(BOOL)log callback:(BNCServerCallback)callback {
    [self postRequest:post url:url andTag:requestTag andLinkData:linkData retryNumber:0 log:log callback:callback];
}

- (void)postRequest:(NSDictionary *)post url:(NSString *)url andTag:(NSString *)requestTag andLinkData:(BNCLinkData *)linkData retryNumber:(NSInteger)retryNumber log:(BOOL)log callback:(BNCServerCallback)callback {
    NSURLRequest *request = [self preparePostRequest:post url:url retryNumber:retryNumber log:log];
    [self genericHTTPRequest:request withTag:requestTag andLinkData:linkData retryNumber:retryNumber log:log callback:callback];
}

- (BNCServerResponse *)postRequest:(NSDictionary *)post url:(NSString *)url andTag:(NSString *)requestTag andLinkData:(BNCLinkData *)linkData log:(BOOL)log {
    NSURLRequest *request = [self preparePostRequest:post url:url retryNumber:0 log:log];
    return [self genericHTTPRequest:request withTag:requestTag andLinkData:linkData];
}


#pragma mark - Generic requests

- (void)genericHTTPRequest:(NSURLRequest *)request withTag:(NSString *)requestTag andLinkData:(BNCLinkData *)linkData callback:(BNCServerCallback)callback {
    [self genericHTTPRequest:request withTag:requestTag andLinkData:linkData retryNumber:0 log:YES callback:callback];
}

- (void)genericHTTPRequest:(NSURLRequest *)request withTag:(NSString *)requestTag andLinkData:(BNCLinkData *)linkData retryNumber:(NSInteger)retryNumber log:(BOOL)log callback:(BNCServerCallback)callback {
    [NSURLConnection sendAsynchronousRequest:request queue:self.operationQueue completionHandler:^(NSURLResponse *response, NSData *responseData, NSError *error) {
        BNCServerResponse *serverResponse = [self processServerResponse:response data:responseData error:error tag:requestTag andLinkData:linkData];
        NSInteger status = [serverResponse.statusCode integerValue];
        BOOL isRetryableStatusCode = status >= 500;
        
        // Retry the request if appropriate
        if (retryNumber < [BNCPreferenceHelper getRetryCount] && isRetryableStatusCode) {
            [NSThread sleepForTimeInterval:[BNCPreferenceHelper getRetryInterval]];
            
            if (log) {
                [BNCPreferenceHelper log:FILE_NAME line:LINE_NUM message:@"Replaying request with tag %@", requestTag];
            }
            
            [self genericHTTPRequest:request withTag:requestTag andLinkData:linkData retryNumber:(retryNumber + 1) log:log callback:callback];
        }
        else if (callback) {
            // Wrap bad statuses up as errors if one hasn't already been set
            if ((status < 200 || status > 399) && !error) {
                NSString *errorString = [serverResponse.data objectForKey:@"error"] ?: @"The request was unsuccessful.";

                error = [NSError errorWithDomain:BNCErrorDomain code:BNCRequestError userInfo:@{
                    NSLocalizedDescriptionKey: errorString
                }];
            }

            callback(serverResponse, error);
        }
    }];
}

- (BNCServerResponse *)genericHTTPRequest:(NSURLRequest *)request withTag:(NSString *)requestTag andLinkData:(BNCLinkData *)linkData {
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *POSTReply = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
    
    return [self processServerResponse:response data:POSTReply error:error tag:requestTag andLinkData:linkData];
}


#pragma mark - Internals

- (NSURLRequest *)prepareGetRequest:(NSDictionary *)params url:(NSString *)url retryNumber:(NSInteger)retryNumber log:(BOOL)log {
    NSMutableDictionary *fullParamDict = [[NSMutableDictionary alloc] init];
    [fullParamDict addEntriesFromDictionary:params];
    fullParamDict[@"sdk"] = [NSString stringWithFormat:@"ios%@", SDK_VERSION];
    fullParamDict[@"retryNumber"] = @(retryNumber);
    
    NSString *appId = [BNCPreferenceHelper getAppKey];
    // TODO re-add this
    //    NSString *branchKey = [BNCPreferenceHelper getBranchKey];
    //    if (![branchKey isEqualToString:NO_STRING_VALUE]) {
    //        fullParamDict[KEY_BRANCH_KEY] = branchKey;
    //    }
    //    else if (![appId isEqualToString:NO_STRING_VALUE]) {
    if (![appId isEqualToString:NO_STRING_VALUE]) {
        fullParamDict[@"app_id"] = appId;
    }
    
    NSString *requestUrlString = [NSString stringWithFormat:@"%@%@", url, [BNCEncodingUtils encodeDictionaryToQueryString:fullParamDict]];
    
    if (log) {
        [BNCPreferenceHelper log:FILE_NAME line:LINE_NUM message:@"using url = %@", url];
    }
    
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setURL:[NSURL URLWithString:requestUrlString]];
    [request setHTTPMethod:@"GET"];
    [request setValue:@"applications/json" forHTTPHeaderField:@"Content-Type"];
    
    return request;
}

- (NSURLRequest *)preparePostRequest:(NSDictionary *)params url:(NSString *)url retryNumber:(NSInteger)retryNumber log:(BOOL)log {
    NSMutableDictionary *fullParamDict = [[NSMutableDictionary alloc] init];
    [fullParamDict addEntriesFromDictionary:params];
    fullParamDict[@"sdk"] = [NSString stringWithFormat:@"ios%@", SDK_VERSION];
    fullParamDict[@"retryNumber"] = @(retryNumber);
    
    NSString *appId = [BNCPreferenceHelper getAppKey];
    // TODO re-add this
//    NSString *branchKey = [BNCPreferenceHelper getBranchKey];
//    if (![branchKey isEqualToString:NO_STRING_VALUE]) {
//        fullParamDict[KEY_BRANCH_KEY] = branchKey;
//    }
//    else if (![appId isEqualToString:NO_STRING_VALUE]) {
    if (![appId isEqualToString:NO_STRING_VALUE]) {
        fullParamDict[@"app_id"] = appId;
    }


    NSData *postData = [BNCEncodingUtils encodeDictionaryToJsonData:fullParamDict];
    NSString *postLength = [NSString stringWithFormat:@"%lu", (unsigned long)[postData length]];
    
    if (log) {
        [BNCPreferenceHelper log:FILE_NAME line:LINE_NUM message:@"using url = %@", url];
        [BNCPreferenceHelper log:FILE_NAME line:LINE_NUM message:@"body = %@", [fullParamDict description]];
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [request setTimeoutInterval:[BNCPreferenceHelper getTimeout]];
    [request setHTTPMethod:@"POST"];
    [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:postData];
    
    return request;
}

- (BNCServerResponse *)processServerResponse:(NSURLResponse *)response data:(NSData *)data error:(NSError *)error tag:(NSString *)requestTag andLinkData:(BNCLinkData *)linkData {
    BNCServerResponse *serverResponse = [[BNCServerResponse alloc] initWithTag:requestTag];
    serverResponse.linkData = linkData;

    if (!error) {
        serverResponse.statusCode = @([(NSHTTPURLResponse *)response statusCode]);
        serverResponse.data = [BNCEncodingUtils decodeJsonDataToDictionary:data];
    }
    else {
        serverResponse.statusCode = @(error.code);
        serverResponse.data = error.userInfo;
    }

    if ([BNCPreferenceHelper isDebug]  // for efficiency short-circuit purpose
        && ![requestTag isEqualToString:REQ_TAG_DEBUG_LOG]
        && ![requestTag isEqualToString:REQ_TAG_DEBUG_CONNECT]
        && [requestTag isEqualToString:REQ_TAG_DEBUG_DISCONNECT]
        && [requestTag isEqualToString:REQ_TAG_DEBUG_SCREEN])
    {
        [BNCPreferenceHelper log:FILE_NAME line:LINE_NUM message:@"returned = %@", [serverResponse description]];
    }
    
    return serverResponse;
}

@end
