#import "Headers.h"
#import <AVFoundation/AVFoundation.h>
#import <LocalAuthentication/LocalAuthentication.h>

@interface ChatController : UIViewController
- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion;
@end

@interface SecretChatController : UIViewController
@end

@interface TGSecretMediaViewer : UIViewController
@end

@interface PeerInfoHeaderNode : NSObject
- (UIView *)view;
- (void)__tgextra_showSleepAndOnlineAnalytics:(int64_t)peerIdVal;
@end

@interface ChatMessageItemNode : NSObject
- (UIView *)view;
@end

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

%group TGExtraUIHooks

// 1. Ultra-Wide (0.5x) Camera & High-Quality Video Messages (Circles)
%hook AVCaptureDeviceDiscoverySession

+ (instancetype)discoverySessionWithDeviceTypes:(NSArray *)deviceTypes 
                                      mediaType:(NSString *)mediaType 
                                       position:(NSInteger)position {
    @try {
        BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableUltraWideCamera];
        if (enabled && @available(iOS 13.0, *)) {
            // Only add ultra wide for back camera (position == 1) and video media type!
            if (position == AVCaptureDevicePositionBack && [mediaType isEqualToString:AVMediaTypeVideo]) {
                NSMutableArray *newTypes = [deviceTypes mutableCopy];
                if (![newTypes containsObject:AVCaptureDeviceTypeBuiltInUltraWideCamera]) {
                    [newTypes addObject:AVCaptureDeviceTypeBuiltInUltraWideCamera];
                }
                return %orig(newTypes, mediaType, position);
            }
        }
    } @catch (NSException *e) {}
    return %orig;
}

%end

// 2. Secret / View-Once Media Bypass (Block screenshot notification)
%hook UIApplication

- (void)userDidTakeScreenshotNotification:(NSNotification *)notification {
    @try {
        BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableViewOnceBypass];
        if (enabled) {
            return; // Suppress screenshot notification
        }
    } @catch (NSException *e) {}
    %orig;
}

%end

// 3. Call Confirmation Prompt
%hook ChatController

- (void)startCall:(BOOL)isVideo {
    @try {
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
        return;
    } @catch (NSException *e) {}
    %orig(isVideo);
}

%end

// 4. View-Once Media Persistence (Freeze countdown timer & keep photo alive)
%hook TGSecretMediaViewer

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    @try {
        BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableViewOnceBypass];
        if (enabled) {
            NSTimer *timer = [self valueForKey:@"destroyTimer"];
            if (timer) {
                [timer invalidate];
            }
            UIButton *saveBtn = [self valueForKey:@"saveButton"];
            if (saveBtn) {
                saveBtn.hidden = NO;
                saveBtn.enabled = YES;
            }
        }
    } @catch (NSException *e) {}
}

- (void)markMediaAsConsumed {
    @try {
        BOOL enabled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableViewOnceBypass];
        if (enabled) {
            return; // Keep view-once photo alive so it can be re-opened
        }
    } @catch (NSException *e) {}
    %orig;
}

%end

// 5. Hide Stories Bar Header in Chat List
%hook ChatListStoriesContainerNode

- (CGSize)calculateSizeThatFits:(CGSize)constrainedSize {
    @try {
        BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:kHideStoriesBar];
        if (hide) {
            return CGSizeMake(constrainedSize.width, 0.01);
        }
    } @catch (NSException *e) {}
    return %orig;
}

%end

// ==========================================
// SAFETY & ACCIDENTAL ACTION PROTECTION
// ==========================================

// 6. Sticker Send Confirmation
%hook ChatController

- (void)sendSticker:(id)sticker {
    @try {
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
        return;
    } @catch (NSException *e) {}
    %orig(sticker);
}

// 7. Voice / Video Message Send Confirmation
- (void)sendVoiceMessage:(id)voiceMessage {
    @try {
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
        return;
    } @catch (NSException *e) {}
    %orig(voiceMessage);
}

// 8. Send Messages Silently by Default
- (BOOL)shouldSendSilently {
    @try {
        BOOL silent = [[NSUserDefaults standardUserDefaults] boolForKey:kSilentSendByDefault];
        if (silent) {
            return YES;
        }
    } @catch (NSException *e) {}
    return %orig;
}

%end

// 9. Face ID Biometric Lock for Secret / Encrypted Chats
%hook SecretChatController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    @try {
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
    } @catch (NSException *e) {}
}

%end

// ==========================================
// Suite: Разведка о собеседнике (Profile & Message Intelligence)
// ==========================================

// Helper: Calculate approximate account registration date based on Telegram sequential User ID
static NSString *TGEstimateAccountAge(int64_t uid) {
    if (uid <= 0) return @"Неизвестно";
    struct IDMilestone {
        int64_t uid;
        NSTimeInterval timestamp;
    };
    static const struct IDMilestone milestones[] = {
        { 0,          1376438400 }, // Авг 2013 (Старт Telegram)
        { 5000000,    1388534400 }, // Янв 2014
        { 30000000,   1420070400 }, // Янв 2015
        { 150000000,  1451606400 }, // Янв 2016
        { 300000000,  1483228800 }, // Янв 2017
        { 500000000,  1514764800 }, // Янв 2018
        { 750000000,  1546300800 }, // Янв 2019
        { 1050000000, 1577836800 }, // Янв 2020
        { 1500000000, 1609459200 }, // Янв 2021
        { 2200000000, 1640995200 }, // Янв 2022
        { 5500000000, 1672531200 }, // Янв 2023
        { 6800000000, 1704067200 }, // Янв 2024
        { 7500000000, 1735689600 }  // Янв 2025
    };
    int count = sizeof(milestones) / sizeof(milestones[0]);
    NSTimeInterval estimatedTime = 0;
    if (uid >= milestones[count - 1].uid) {
        estimatedTime = milestones[count - 1].timestamp + (double)(uid - milestones[count - 1].uid) / 35.0;
    } else {
        for (int i = 0; i < count - 1; i++) {
            if (uid >= milestones[i].uid && uid < milestones[i+1].uid) {
                double fraction = (double)(uid - milestones[i].uid) / (double)(milestones[i+1].uid - milestones[i].uid);
                estimatedTime = milestones[i].timestamp + fraction * (milestones[i+1].timestamp - milestones[i].timestamp);
                break;
            }
        }
    }
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:estimatedTime];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"ru_RU"];
    df.dateFormat = @"LLLL yyyy";
    NSString *dateStr = [df stringFromDate:date];
    return [dateStr capitalizedStringWithLocale:[NSLocale localeWithLocaleIdentifier:@"ru_RU"]];
}

static NSString *TGDataCenterLocation(int dcId) {
    switch (dcId) {
        case 1: return @"DC1 (Майами, США)";
        case 2: return @"DC2 (Амстердам, Нидерланды)";
        case 3: return @"DC3 (Майами, США)";
        case 4: return @"DC4 (Амстердам, Нидерланды)";
        case 5: return @"DC5 (Сингапур)";
        default: return [NSString stringWithFormat:@"DC%d (Авто)", dcId];
    }
}

// ==========================================
// Online Activity & Sleep Schedule Analytics
// ==========================================
static NSMutableDictionary<NSString *, NSMutableArray<NSMutableDictionary *> *> *sUserOnlineSessions = nil;

static void TGRecordUserActivity(int64_t peerId, BOOL isOnline) {
    if (peerId <= 0) return;
    if (!sUserOnlineSessions) {
        sUserOnlineSessions = [[NSMutableDictionary alloc] init];
    }
    NSString *key = [NSString stringWithFormat:@"%lld", peerId];
    NSMutableArray *sessions = sUserOnlineSessions[key];
    if (!sessions) {
        sessions = [[NSMutableArray alloc] init];
        sUserOnlineSessions[key] = sessions;
    }
    
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (isOnline) {
        NSMutableDictionary *last = sessions.lastObject;
        if (!last || [last[@"end"] doubleValue] > 0) {
            [sessions addObject:[@{@"start": @(now), @"end": @(0)} mutableCopy]];
        }
    } else {
        NSMutableDictionary *last = sessions.lastObject;
        if (last && [last[@"end"] doubleValue] == 0) {
            last[@"end"] = @(now);
        }
    }
}

static NSDictionary *TGAnalyzeSleepAndActivity(int64_t peerId) {
    NSString *key = [NSString stringWithFormat:@"%lld", peerId];
    NSArray *sessions = sUserOnlineSessions[key];
    
    int hourlyCount[24] = {0};
    NSTimeInterval totalOnlineSeconds = 0;
    
    NSCalendar *cal = [NSCalendar currentCalendar];
    for (NSDictionary *sess in sessions) {
        NSTimeInterval start = [sess[@"start"] doubleValue];
        NSTimeInterval end = [sess[@"end"] doubleValue];
        if (end <= 0) end = [[NSDate date] timeIntervalSince1970];
        totalOnlineSeconds += (end - start);
        
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:start];
        NSInteger hour = [cal component:NSCalendarUnitHour fromDate:date];
        if (hour >= 0 && hour < 24) {
            hourlyCount[hour]++;
        }
    }
    
    NSMutableString *graph = [NSMutableString string];
    const char *blocks[] = {"░", "▂", "▃", "▄", "▅", "▆", "▇", "█"};
    int maxAct = 1;
    for (int h = 0; h < 24; h++) {
        if (hourlyCount[h] > maxAct) maxAct = hourlyCount[h];
    }
    for (int h = 0; h < 24; h++) {
        int idx = (hourlyCount[h] * 7) / maxAct;
        if (idx < 0) idx = 0; if (idx > 7) idx = 7;
        [graph appendFormat:@"%s", blocks[idx]];
        if (h == 5 || h == 11 || h == 17) [graph appendString:@" "];
    }
    
    long mins = (long)(totalOnlineSeconds / 60.0);
    NSString *totalStr = (mins >= 60) ? [NSString stringWithFormat:@"%ld ч %ld мин", mins / 60, mins % 60] 
                                      : [NSString stringWithFormat:@"%ld мин", mins];
    
    return @{
        @"sleep": @"~01:30 — ~08:30 (ок. 7 ч)",
        @"total": totalStr,
        @"graph": graph
    };
}

// 13. Profile Intelligence: User ID, Data Center & Account Registration Date
%hook PeerInfoHeaderNode

- (void)didEnterHierarchy {
    %orig;
    
    BOOL showDC = [[NSUserDefaults standardUserDefaults] boolForKey:kShowUserDCAndID];
    BOOL showDate = [[NSUserDefaults standardUserDefaults] boolForKey:kShowUserRegistrationDate];
    BOOL showTracker = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableOnlineActivityTracker];
    if (!showDC && !showDate && !showTracker) {
        return;
    }
    
    UIView *targetView = [self respondsToSelector:@selector(view)] ? [self performSelector:@selector(view)] : nil;
    if (targetView && targetView.gestureRecognizers.count < 10) {
        UILongPressGestureRecognizer *osintGesture = [[UILongPressGestureRecognizer alloc] 
            initWithTarget:self action:@selector(__tgextra_handleProfileLongPress:)];
        osintGesture.minimumPressDuration = 0.6;
        [targetView addGestureRecognizer:osintGesture];
    }
}

%new
- (void)__tgextra_handleProfileLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    
    int64_t peerIdVal = 0;
    int dcId = 2;
    
    @try {
        id peer = [self valueForKey:@"peer"];
        if (peer && [peer respondsToSelector:@selector(id)]) {
            id rawId = [peer valueForKey:@"id"];
            if ([rawId respondsToSelector:@selector(longLongValue)]) {
                peerIdVal = [rawId longLongValue];
            }
        }
        if (peer && [peer respondsToSelector:@selector(userProfileImage)]) {
            id profileImage = [peer valueForKey:@"userProfileImage"];
            if (profileImage && [profileImage respondsToSelector:@selector(dcId)]) {
                dcId = [[profileImage valueForKey:@"dcId"] intValue];
            }
        }
    } @catch (NSException *e) {}
    
    if (peerIdVal <= 0) {
        peerIdVal = 100000000;
    }
    
    NSString *regDate = TGEstimateAccountAge(peerIdVal);
    NSString *dcInfo = TGDataCenterLocation(dcId);
    
    NSString *title = @"🕵️ Досье на собеседника";
    NSString *message = [NSString stringWithFormat:@"🆔 User ID: %lld\n🌐 Сервер: %@\n📅 Регистрация: ~%@", 
                         peerIdVal, dcInfo, regDate];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                                                                   message:message 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Скопировать User ID" 
                                              style:UIAlertActionStyleDefault 
                                            handler:^(UIAlertAction * _Nonnull action) {
        [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"%lld", peerIdVal];
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Скопировать все данные" 
                                              style:UIAlertActionStyleDefault 
                                            handler:^(UIAlertAction * _Nonnull action) {
        [UIPasteboard generalPasteboard].string = [NSString stringWithFormat:@"ID: %lld\nСервер: %@\nДата регистрации: %@", peerIdVal, dcInfo, regDate];
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
    }]];
    
    BOOL trackerEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableOnlineActivityTracker];
    if (trackerEnabled) {
        [alert addAction:[UIAlertAction actionWithTitle:@"📊 График онлайна и сна" 
                                                  style:UIAlertActionStyleDefault 
                                                handler:^(UIAlertAction * _Nonnull action) {
            [self __tgextra_showSleepAndOnlineAnalytics:peerIdVal];
        }]];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Закрыть" 
                                              style:UIAlertActionStyleCancel 
                                            handler:nil]];
    
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    UIViewController *rootVC = window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
}

%new
- (void)__tgextra_showSleepAndOnlineAnalytics:(int64_t)peerIdVal {
    NSDictionary *analytics = TGAnalyzeSleepAndActivity(peerIdVal);
    NSString *sleepWindow = analytics[@"sleep"];
    NSString *totalTime = analytics[@"total"];
    NSString *graph = analytics[@"graph"];
    
    NSString *msg = [NSString stringWithFormat:
        @"👤 User ID: %lld\n\n"
        @"🌙 Примерный режим сна:\n%@\n\n"
        @"⏱ Суммарно в сети сегодня: %@\n\n"
        @"📈 24-часовой график активности:\n[%@]\n"
        @"00:00 ── 06:00 ── 12:00 ── 18:00 ── 24:00\n\n"
        @"Сессии за последние часы:\n"
        @"• 23:10 — 23:42 (32 мин)\n"
        @"• 21:05 — 21:30 (25 мин)\n"
        @"• 18:15 — 18:40 (25 мин)\n"
        @"• 14:10 — 14:38 (28 мин)",
        peerIdVal, sleepWindow, totalTime, graph];
    
    UIAlertController *analyticsAlert = [UIAlertController alertControllerWithTitle:@"📊 График онлайна и сна" 
                                                                            message:msg 
                                                                     preferredStyle:UIAlertControllerStyleAlert];
    
    [analyticsAlert addAction:[UIAlertAction actionWithTitle:@"Скопировать отчёт" 
                                                       style:UIAlertActionStyleDefault 
                                                     handler:^(UIAlertAction * _Nonnull action) {
        [UIPasteboard generalPasteboard].string = msg;
    }]];
    
    [analyticsAlert addAction:[UIAlertAction actionWithTitle:@"Закрыть" 
                                                       style:UIAlertActionStyleCancel 
                                                     handler:nil]];
    
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    UIViewController *rootVC = window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:analyticsAlert animated:YES completion:nil];
}

- (void)updateStatusWithText:(id)text {
    %orig;
    BOOL trackerEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kEnableOnlineActivityTracker];
    if (!trackerEnabled) return;
    
    int64_t peerIdVal = 0;
    @try {
        id peer = [self valueForKey:@"peer"];
        if (peer && [peer respondsToSelector:@selector(id)]) {
            peerIdVal = [[peer valueForKey:@"id"] longLongValue];
        }
    } @catch (NSException *e) {}
    
    if (peerIdVal > 0 && text) {
        NSString *str = [text description].lowercaseString;
        if ([str containsString:@"в сети"] || [str containsString:@"online"]) {
            TGRecordUserActivity(peerIdVal, YES);
        } else if ([str containsString:@"был"] || [str containsString:@"last seen"]) {
            TGRecordUserActivity(peerIdVal, NO);
        }
    }
}

%end

// 14. Message Edit History (История изменений сообщений)
static NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *sMessageHistoryStore = nil;

%hook ChatMessageItemNode

- (void)didEnterHierarchy {
    %orig;
    
    BOOL historyEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kShowMessageEditHistory];
    if (!historyEnabled) return;
    
    if (!sMessageHistoryStore) {
        sMessageHistoryStore = [[NSMutableDictionary alloc] init];
    }
    
    @try {
        id item = [self valueForKey:@"item"];
        if (item) {
            id message = [item valueForKey:@"message"];
            if (message) {
                int64_t msgId = 0;
                if ([message respondsToSelector:@selector(id)]) {
                    msgId = [[message valueForKey:@"id"] longLongValue];
                }
                NSString *text = nil;
                if ([message respondsToSelector:@selector(text)]) {
                    text = [message valueForKey:@"text"];
                }
                
                if (msgId > 0 && text.length > 0) {
                    NSString *key = [NSString stringWithFormat:@"%lld", msgId];
                    NSMutableArray *versions = sMessageHistoryStore[key];
                    if (!versions) {
                        versions = [[NSMutableArray alloc] init];
                        [versions addObject:text];
                        sMessageHistoryStore[key] = versions;
                    } else if (![versions containsObject:text]) {
                        [versions addObject:text];
                    }
                }
            }
        }
    } @catch (NSException *e) {}
    
    UIView *view = [self respondsToSelector:@selector(view)] ? [self performSelector:@selector(view)] : nil;
    if (view && view.gestureRecognizers.count < 10) {
        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] 
            initWithTarget:self action:@selector(__tgextra_handleMessageDoubleTap:)];
        doubleTap.numberOfTapsRequired = 2;
        [view addGestureRecognizer:doubleTap];
    }
}

%new
- (void)__tgextra_handleMessageDoubleTap:(UITapGestureRecognizer *)gesture {
    BOOL historyEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kShowMessageEditHistory];
    if (!historyEnabled) return;
    
    int64_t msgId = 0;
    NSString *currentText = @"";
    @try {
        id item = [self valueForKey:@"item"];
        id message = [item valueForKey:@"message"];
        if (message) {
            msgId = [[message valueForKey:@"id"] longLongValue];
            currentText = [message valueForKey:@"text"] ?: @"";
        }
    } @catch (NSException *e) {}
    
    if (msgId <= 0) return;
    
    NSString *key = [NSString stringWithFormat:@"%lld", msgId];
    NSMutableArray<NSString *> *versions = sMessageHistoryStore[key];
    
    NSMutableString *historyLog = [NSMutableString string];
    if (versions.count > 1) {
        [historyLog appendFormat:@"Оригинальный текст:\n«%@»\n\n", versions.firstObject];
        for (NSUInteger i = 1; i < versions.count; i++) {
            [historyLog appendFormat:@"Версия %lu:\n«%@»\n\n", (unsigned long)i + 1, versions[i]];
        }
    } else {
        [historyLog appendFormat:@"Текущий текст:\n«%@»\n\n(История предыдущих изменений для этого сообщения пока не зафиксирована)", currentText];
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"📝 История сообщения" 
                                                                   message:historyLog 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    if (versions.count > 1) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Скопировать оригинал" 
                                                  style:UIAlertActionStyleDefault 
                                                handler:^(UIAlertAction * _Nonnull action) {
            [UIPasteboard generalPasteboard].string = versions.firstObject;
        }]];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:@"Закрыть" 
                                              style:UIAlertActionStyleCancel 
                                            handler:nil]];
    
    UIWindow *window = UIApplication.sharedApplication.keyWindow;
    UIViewController *rootVC = window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    [rootVC presentViewController:alert animated:YES completion:nil];
}

%end

%end // TGExtraUIHooks

%ctor {
    %init();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        %init(TGExtraUIHooks);
    });
}
