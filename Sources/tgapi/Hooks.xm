#import "Headers.h"

#define kChannelsReadHistory -871347913

%hook MTRequest
%property (nonatomic, strong) NSData *fakeData;
%property (nonatomic, strong) NSNumber *functionID;

- (void)setPayload:(NSData *)payload metadata:(id)metadata shortMetadata:(id)shortMetadata responseParser:(id (^)(NSData *))responseParser {
	
	// Extract Function id 
	int32_t functionID;
	[payload getBytes:&functionID length:4];
	self.functionID = [NSNumber numberWithInt:functionID];
	
	//customLog(@"Function id: %d", functionID);
	
	id(^hooked_block)(NSData *) = ^(NSData *inputData) {
		NSNumber *functionIDNumber = [NSNumber numberWithUnsignedInt:functionID];
		NSData *fuck = [TLParser handleResponse:inputData functionID:functionIDNumber];
		id result;
		if (fuck) {
			result = responseParser(fuck);
		} else {
			result = responseParser(inputData);
		}
		return result;
	};
	
	switch (functionID) {
		case kAccountUpdateOnlineStatus:
		   handleOnlineStatus(self, payload);
		   break;
		case kMessagesSetTypingAction:
		   handleSetTyping(self, payload);
		   break;
		case kMessagesReadHistory:
		   handleMessageReadReceipt(self, payload);
		   break;
		case kStoriesReadStories:
		   handleStoriesReadReceipt(self, payload);
		   break;
		case kGetSponsoredMessages:
		   handleGetSponsoredMessages(self, payload);
		   break;
		case kChannelsReadHistory:
		   handleChannelsReadReceipt(self, payload);
		   break;
		default:
		   break;
		   
	}
	
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"disableForwardRestriction"]) {
		%orig(payload, metadata, shortMetadata, hooked_block);
	} else {
		%orig(payload, metadata, shortMetadata, responseParser);
	}
}

%end


// Manager which handles requests
%hook MTRequestMessageService

- (void)addRequest:(MTRequest *)request {
    if (request.fakeData) {
        @try {
             if (request.completed) {
                 NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];

                 MTRequestResponseInfo *info = [[%c(MTRequestResponseInfo) alloc] initWithNetworkType:1 
					     timestamp:currentTime 
						  duration:0.045
					   ];
						
						id result = request.responseParser(request.fakeData);
						request.completed(result, info, nil);
             }
         } @catch (NSException *exception) {
             customLog2(@"Exception in MTRequestMessageService hook: %@", exception);
         }
        return;
    }
    %orig;
}

%end

// ==========================================
// CUSTOM ENHANCEMENTS: CAMERA & PRIVACY
// ==========================================

#import <AVFoundation/AVFoundation.h>

// 1. Ultra-Wide (0.5x) Camera & High-Quality Video Messages (Circles)
%hook AVCaptureDeviceDiscoverySession

+ (instancetype)discoverySessionWithDeviceTypes:(NSArray<AVCaptureDeviceType> *)deviceTypes 
                                      mediaType:(AVMediaType)mediaType 
                                       position:(AVCaptureDevicePosition)position {
    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableUltraWideCamera];
    if (enabled && @available(iOS 13.0, *)) {
        NSMutableArray *newTypes = [deviceTypes mutableCopy];
        if (![newTypes containsObject:AVCaptureDeviceTypeBuiltInUltraWideCamera]) {
            [newTypes addObject:AVCaptureDeviceTypeBuiltInUltraWideCamera];
        }
        return %orig(newTypes, mediaType, position);
    }
    return %orig;
}

%end

// 2. Secret / View-Once Media Bypass (Block screenshot notification)
%hook UIApplication

- (void)userDidTakeScreenshotNotification:(NSNotification *)notification {
    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableViewOnceBypass];
    if (enabled) {
        return; // Suppress screenshot notification
    }
    %orig;
}

%end

// 3. Call Confirmation Prompt
%hook ChatController

- (void)startCall:(BOOL)isVideo {
    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableCallConfirmation];
    if (!enabled) {
        %orig(isVideo);
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Подтверждение звонка"
                                                                   message:@"Вы уверены, что хотите позвонить?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *callAction = [UIAlertAction actionWithTitle:@"Позвонить" 
                                                         style:UIAlertActionStyleDefault 
                                                       handler:^(UIAlertAction *action) {
        %orig(isVideo);
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Отмена" 
                                                           style:UIAlertActionStyleCancel 
                                                         handler:nil];
    
    [alert addAction:callAction];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

%end
