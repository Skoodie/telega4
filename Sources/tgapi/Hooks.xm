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
		case kMessagesReadMessageContents:
		   handleVoiceReadReceipt(self, payload);
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

// 4. View-Once Media Persistence (Freeze countdown timer & keep photo alive)
%hook TGSecretMediaViewer

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableViewOnceBypass];
    if (enabled) {
        @try {
            NSTimer *timer = [self valueForKey:@"destroyTimer"];
            if (timer) {
                [timer invalidate];
            }
            UIButton *saveBtn = [self valueForKey:@"saveButton"];
            if (saveBtn) {
                saveBtn.hidden = NO;
                saveBtn.enabled = YES;
            }
        } @catch (NSException *e) {}
    }
}

- (void)markMediaAsConsumed {
    BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableViewOnceBypass];
    if (enabled) {
        return; // Keep view-once photo alive so it can be re-opened
    }
    %orig;
}

%end

// 5. Hide Stories Bar Header in Chat List
%hook ChatListStoriesContainerNode

- (CGSize)calculateSizeThatFits:(CGSize)constrainedSize {
    BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:kHideStoriesBar];
    if (hide) {
        return CGSizeZero;
    }
    return %orig;
}

%end

// ==========================================
// BYPASS RESTRICTIONS & APPLE CENSORSHIP
// ==========================================

// 6. Bypass Apple Censorship & Restricted Channels
%hook TelegramChannel

- (NSArray *)restrictionInfo {
    BOOL bypass = [[NSUserDefaults standardUserDefaults] boolForKey:kBypassAppleCensorship];
    if (bypass) {
        return nil; // Strip all restriction reasons for iOS
    }
    return %orig;
}

- (BOOL)hasRestrictionReasons {
    BOOL bypass = [[NSUserDefaults standardUserDefaults] boolForKey:kBypassAppleCensorship];
    if (bypass) {
        return NO;
    }
    return %orig;
}

%end

// 7. Universal Copy & Forward Protection Unlocker
%hook ChatHistoryNode

- (BOOL)hasCopyProtection {
    BOOL unlock = [[NSUserDefaults standardUserDefaults] boolForKey:kUnlockCopyProtection];
    if (unlock) {
        return NO;
    }
    return %orig;
}

%end

%hook ChatMessageItem

- (BOOL)canForward {
    BOOL unlock = [[NSUserDefaults standardUserDefaults] boolForKey:kUnlockCopyProtection];
    if (unlock) {
        return YES;
    }
    return %orig;
}

- (BOOL)canSaveMedia {
    BOOL unlock = [[NSUserDefaults standardUserDefaults] boolForKey:kUnlockCopyProtection];
    if (unlock) {
        return YES;
    }
    return %orig;
}

%end

// 8. Unlimited Pinned Chats (Up to 100 pinned dialogs)
%hook ChatListController

- (NSInteger)maxPinnedChatCount {
    BOOL unlimited = [[NSUserDefaults standardUserDefaults] boolForKey:kUnlimitedPinnedChats];
    if (unlimited) {
        return 100;
    }
    return %orig;
}

%end

// ==========================================
// SAFETY & ACCIDENTAL ACTION PROTECTION
// ==========================================

#import <LocalAuthentication/LocalAuthentication.h>

// 9. Sticker Send Confirmation
%hook ChatController

- (void)sendSticker:(id)sticker {
    BOOL confirm = [[NSUserDefaults standardUserDefaults] boolForKey:kConfirmStickerSend];
    if (!confirm) {
        %orig(sticker);
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Отправка стикера"
                                                                   message:@"Вы действительно хотите отправить этот стикер?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *sendAction = [UIAlertAction actionWithTitle:@"Отправить" 
                                                         style:UIAlertActionStyleDefault 
                                                       handler:^(UIAlertAction *action) {
        %orig(sticker);
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Отмена" 
                                                           style:UIAlertActionStyleCancel 
                                                         handler:nil];
    
    [alert addAction:sendAction];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 10. Voice / Video Message Send Confirmation
- (void)sendVoiceMessage:(id)voiceMessage {
    BOOL confirm = [[NSUserDefaults standardUserDefaults] boolForKey:kConfirmVoiceSend];
    if (!confirm) {
        %orig(voiceMessage);
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Отправка аудио"
                                                                   message:@"Отправить записанное голосовое / видео сообщение?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *sendAction = [UIAlertAction actionWithTitle:@"Отправить" 
                                                         style:UIAlertActionStyleDefault 
                                                       handler:^(UIAlertAction *action) {
        %orig(voiceMessage);
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Отмена" 
                                                           style:UIAlertActionStyleCancel 
                                                         handler:nil];
    
    [alert addAction:sendAction];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 11. Send Messages Silently by Default
- (BOOL)shouldSendSilently {
    BOOL silent = [[NSUserDefaults standardUserDefaults] boolForKey:kSilentSendByDefault];
    if (silent) {
        return YES;
    }
    return %orig;
}

%end

// 12. Face ID Biometric Lock for Secret / Encrypted Chats
%hook SecretChatController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BOOL lockEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kLockChatWithFaceID];
    if (!lockEnabled) {
        return;
    }
    
    LAContext *context = [[LAContext alloc] init];
    NSError *authError = nil;
    NSString *reason = @"Подтвердите личность через Face ID для входа в защищенный чат";
    
    if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&authError]) {
        self.view.alpha = 0.0; // Hide chat contents until verified
        [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics 
                localizedReason:reason 
                          reply:^(BOOL success, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    [UIView animateWithDuration:0.25 animations:^{
                        self.view.alpha = 1.0;
                    }];
                } else {
                    [self.navigationController popViewControllerAnimated:YES];
                }
            });
        }];
    }
}

%end
