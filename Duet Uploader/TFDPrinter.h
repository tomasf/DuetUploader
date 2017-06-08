//
//  TFDPrinter.h
//  DuetRemote
//
//  Created by Tomas Franzén on 05/04/16.
//  Copyright © 2016 Tomas Franzén. All rights reserved.
//

#import <Foundation/Foundation.h>

@class TFDPrinterDirectoryItem, TFDPrinterFileInfo, TFDPrinterStatus;


typedef NS_OPTIONS(NSUInteger, TFDPrinterHeaterMask) {
	TFDPrinterHeaterNone = 0,
	TFDPrinterHeaterBed = 1<<0,
	TFDPrinterHeaterHotend = 1<<1,
};

typedef NS_ENUM(NSUInteger) {
	TFDHeatingProgressStateOff,
	TFDHeatingProgressStateWarming,
	TFDHeatingProgressStateAtTarget,
	TFDHeatingProgressStateCooling,
} TFDHeatingProgressState;


@interface TFDPrinter : NSObject
- (instancetype)initWithHostname:(NSString*)hostname port:(uint16_t)port updatingAutomatically:(BOOL)autoUpdate;

@property (readonly) TFDPrinterStatus *status;
@property (readonly) TFDPrinterFileInfo *currentFileInfo;
@property (readonly, copy) NSString *name;

@property (readonly, copy) NSDate *lastSuccessfulUpdate;

@property (readonly) BOOL simulationMode;

- (void)refreshStatus;
- (void)fetchPrinterStatusWithCompletion:(void(^)(TFDPrinterStatus *status))block;

- (void)fetchDirectoryListingForPath:(NSString*)path resultHandler:(void(^)(NSArray <TFDPrinterDirectoryItem*> *))block;
- (void)deleteItemAtPath:(NSString*)path completion:(void(^)())block;
- (void)fetchInformationForFile:(NSString*)path completion:(void(^)(TFDPrinterFileInfo *info))block;

- (void)downloadFile:(NSString*)path progress:(void(^)(int64_t sent, int64_t total))progressBlock completion:(void(^)(NSData *data, NSError *error))block;
- (void)uploadFile:(NSData*)data toPath:(NSString*)path progress:(void(^)(int64_t sent, int64_t total))progressBlock completion:(void(^)(NSError *error))block;

- (void)createDirectory:(NSString*)path completion:(void(^)(NSError *error))block;
- (void)moveFile:(NSString*)source toPath:(NSString*)destination completion:(void(^)(NSError *error))block;

- (void)runMacroFile:(NSString*)path completion:(void(^)())block;
- (void)printFile:(NSString*)path completion:(void(^)())block;

- (void)homeWithCompletion:(void(^)())block;
- (void)probeWithCompletion:(void(^)())block;

- (void)cancelPrintWithCompletion:(void(^)())block;
- (void)pausePrintWithCompletion:(void(^)())block;
- (void)resumePrintWithCompletion:(void(^)())block;

- (void)setBedTemperature:(double )temperature completion:(void(^)())block;
- (void)setHotendTemperature:(double )temperature completion:(void(^)())block;

- (void)clearFaultForHeater:(NSUInteger)heaterIndex completion:(void(^)())block;

- (void)setSpeedFactor:(double)factor completion:(void(^)())block;
- (void)setExtrusionFactor:(double)factor completion:(void(^)())block;

- (void)setSimulationMode:(BOOL)simulationMode;
- (void)fetchSimulationDurationWithCompletion:(void(^)(NSTimeInterval duration))block;

- (void)babystepWithOffset:(double)offset;

- (void)setATXPower:(BOOL)power completion:(void(^)())block;

@property (readonly) TFDHeatingProgressState bedHeaterState;
@property (readonly) TFDHeatingProgressState hotendHeaterState;
@property (readonly) TFDPrinterHeaterMask pendingHeaters;
@property (readonly) double fractionOfBedHeaterProgress;
@property (readonly) double fractionOfHotendHeaterProgress;

@property (readonly) double nominalFilamentDiameter;
@property (nonatomic) double adjustedFilamentDiameter;
@end



@interface TFDPrinterDirectoryItem : NSObject
@property (copy, readonly) NSString *name;
@property (copy, readonly) NSString *path;
@property (readonly) BOOL isDirectory;
@property (readonly) uint64_t size;
@property (readonly) NSString *displayName;
@property (readonly, copy) NSDate *modificationDate;
@end


@interface TFDPrinterFileInfo : NSObject
@property (copy, readonly) NSString *path;
@property (copy, readonly) NSString *generator;
@property (readonly) uint64_t fileSize;
@property (readonly) NSString *displayName;


// Millimeters:
@property (readonly) double height;
@property (readonly) double layerHeight;
@property (readonly) double firstLayerHeight;
@property (readonly) double filamentLength;
@end



typedef NS_ENUM(NSUInteger) {
	TFDHeaterStateOff,
	TFDHeaterStateStandby,
	TFDHeaterStateActive,
	TFDHeaterStateFault,
	TFDHeaterStateTuning,
} TFDHeaterState;


@interface TFDHeaterStatus : NSObject
@property (readonly) TFDHeaterState state;
@property (readonly) double currentTemperature;
@property (readonly) double targetTemperature;
@end



typedef NS_ENUM(NSUInteger) {
	TFDPrinterStateIdle,
	TFDPrinterStateBusy,
	TFDPrinterStatePrinting,
	TFDPrinterStatePaused,
	TFDPrinterStatePausing,
	TFDPrinterStateResuming,
	TFDPrinterStateHalted,
	TFDPrinterStateReadingConfig,
	TFDPrinterStateFlashingFirmware,
} TFDPrinterState;


@interface TFDPrinterStatus : NSObject
- (instancetype)initWithJSON:(NSDictionary*)dict;

@property (readonly) TFDPrinterState state;

@property (readonly) BOOL ATXPower;

@property (readonly) double fractionPrinted;
@property (readonly) NSTimeInterval printDuration;
@property (readonly) NSTimeInterval timeRemaining;

@property (readonly) NSInteger currentLayer;

@property (readonly) TFDHeaterStatus *bedHeaterStatus;
@property (readonly) TFDHeaterStatus *primaryHotendStatus;
@property (readonly, copy) NSArray <TFDHeaterStatus*> *hotendStatuses;

@property (readonly) double speedFactor;
@property (readonly) double extrusionFactor;

@property (readonly) double babysteppingOffset;

@property (readonly) BOOL printing;
@end
