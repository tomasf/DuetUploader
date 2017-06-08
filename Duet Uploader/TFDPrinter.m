//
//  TFDPrinter.m
//  DuetRemote
//
//  Created by Tomas Franzén on 05/04/16.
//  Copyright © 2016 Tomas Franzén. All rights reserved.
//

#import "TFDPrinter.h"
#import "MAKVONotificationCenter.h"
#import "TFDExtras.h"


const double acceptableTemperatureThreshold = 2.5;
const NSTimeInterval HTTPTimeout = 60;// 10;

static NSString *const duetServerErrorDomain = @"duetError";


@interface TFDPrinterDirectoryItem ()
@property (copy, readwrite) NSString *name;
@property (copy, readwrite) NSString *path;
@property (readwrite) uint64_t size;
@property (readwrite) BOOL isDirectory;
@property (readwrite, copy) NSDate *modificationDate;
@end

@implementation TFDPrinterDirectoryItem

- (NSString *)description {
	return [NSString stringWithFormat:@"%@ %@", self.isDirectory ? @"Directory" : @"File", self.path];
}


- (NSString*)displayName {
	if ([self.name.pathExtension isEqual:@"gcode"]) {
		return self.name.stringByDeletingPathExtension;
	} else {
		return self.name;
	}
}


@end



@interface TFDPrinterFileInfo ()
@property (copy, readwrite) NSString *path;
@property (copy, readwrite) NSString *generator;
@property (readwrite) uint64_t fileSize;

// Millimeters:
@property (readwrite) double height;
@property (readwrite) double layerHeight;
@property (readwrite) double firstLayerHeight;
@property (readwrite) double filamentLength;
@end

@implementation TFDPrinterFileInfo


- (NSString*)displayName {
	NSString *name = self.path.lastPathComponent;
	if ([name.pathExtension isEqual:@"gcode"]) {
		name = name.stringByDeletingPathExtension;
	}
	return name;
}


@end


@interface TFDHeaterStatus ()
@property (readwrite) TFDHeaterState state;
@property (readwrite) double currentTemperature;
@property (readwrite) double targetTemperature;
@end



@implementation TFDHeaterStatus


- (instancetype)initWithDictionary:(NSDictionary*)info {
	if(!(self = [super init])) return nil;
	
	self.state = [info[@"state"] integerValue];
	self.currentTemperature = [info[@"current"] doubleValue];
	self.targetTemperature = [info[@"active"] doubleValue];
	
	return self;
}


@end




@interface TFDPrinterStatus ()
@property (readwrite) TFDPrinterState state;

@property (readwrite) BOOL ATXPower;

@property (readwrite) double fractionPrinted;
@property (readwrite) NSTimeInterval printDuration;
@property (readwrite) NSTimeInterval timeRemaining;

@property (readwrite) NSInteger currentLayer;

@property (readwrite) double speedFactor;
@property (readwrite) double extrusionFactor;
@property (readwrite) double babysteppingOffset;

@property (readwrite) TFDHeaterStatus *bedHeaterStatus;
@property (readwrite) TFDHeaterStatus *primaryHotendStatus;
@property (readwrite, copy) NSArray <TFDHeaterStatus*> *hotendStatuses;
@end



@implementation TFDPrinterStatus


- (TFDPrinterState)stateFromString:(NSString*)statusString {
	switch ([statusString characterAtIndex:0]) {
		case 'I': return TFDPrinterStateIdle;
		case 'B': return TFDPrinterStateBusy;
		case 'P': return TFDPrinterStatePrinting;
		case 'S': return TFDPrinterStatePaused;
		case 'D': return TFDPrinterStatePausing;
		case 'R': return TFDPrinterStateResuming;
		case 'H': return TFDPrinterStateHalted;
		case 'C': return TFDPrinterStateReadingConfig;
		case 'F': return TFDPrinterStateFlashingFirmware;
		default: return TFDPrinterStateIdle;
	}
}


- (instancetype)initWithJSON:(NSDictionary*)dict {
	if(!(self = [super init])) return nil;
	
	self.state = [self stateFromString:dict[@"status"]];
	self.fractionPrinted = [dict[@"fractionPrinted"] doubleValue] / 100.0;
	self.printDuration = [dict[@"printDuration"] doubleValue];
	
	NSDictionary <NSString*, NSNumber*> *timesLeft = dict[@"timesLeft"];
	NSTimeInterval timeLeftFilament = timesLeft[@"filament"].doubleValue;
	NSTimeInterval timeLeftFile = timesLeft[@"file"].doubleValue;
	self.timeRemaining = timeLeftFilament > DBL_EPSILON ? timeLeftFilament : timeLeftFile;
	
	NSDictionary *bedTemperature = dict[@"temps"][@"bed"];
	self.bedHeaterStatus = [[TFDHeaterStatus alloc] initWithDictionary:bedTemperature];
	
	NSDictionary <NSString*,NSArray<NSNumber*>*> *heads = dict[@"temps"][@"heads"];

	NSUInteger headCount = heads[@"active"].count;
	NSMutableArray *hotends = [NSMutableArray new];
	for (NSUInteger i=0; i<headCount; i++) {
		NSDictionary *info = @{@"active": heads[@"active"][i], @"current": heads[@"current"][i], @"state": heads[@"state"][i]};
		[hotends addObject:[[TFDHeaterStatus alloc] initWithDictionary:info]];
	}
	
	self.hotendStatuses = hotends;
	self.primaryHotendStatus = hotends.firstObject;
	
	self.currentLayer = [dict[@"currentLayer"] integerValue];
	
	self.speedFactor = [dict[@"params"][@"speedFactor"] doubleValue] / 100.0;
	self.extrusionFactor = [dict[@"params"][@"extrFactors"][0] doubleValue] / 100.0;
    self.babysteppingOffset = [dict[@"params"][@"babystep"] doubleValue];
    
    self.ATXPower = [dict[@"params"][@"atxPower"] boolValue];
    
	return self;
}


- (BOOL)printing {
    return self.state == TFDPrinterStatePrinting || self.state == TFDPrinterStatePaused || self.state == TFDPrinterStatePausing || self.state == TFDPrinterStateResuming;
}


@end



@interface TFDPrinter () <NSURLSessionDelegate>
@property (copy) NSString *hostname;
@property uint16_t port;

@property BOOL autoUpdate;

@property NSURLSession *URLSession;

@property NSTimer *refreshTimer;
@property (readwrite) TFDPrinterStatus *status;
@property (readwrite) TFDPrinterFileInfo *currentFileInfo;
@property (readwrite, copy) NSString *name;
@property (readwrite, copy) NSDate *lastSuccessfulUpdate;

@property NSMutableDictionary *uploadProgressBlocks;
@property NSMutableDictionary *downloadProgressBlocks;
@end


@implementation TFDPrinter


- (instancetype)initWithHostname:(NSString*)hostname port:(uint16_t)port updatingAutomatically:(BOOL)autoUpdate {
	if(!(self = [super init])) return nil;
	
	self.hostname = hostname;
	self.port = port;
	
	NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
	config.timeoutIntervalForRequest = HTTPTimeout;
	self.URLSession = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:[NSOperationQueue mainQueue]];
	self.uploadProgressBlocks = [NSMutableDictionary new];
	self.downloadProgressBlocks = [NSMutableDictionary new];
	
    self.autoUpdate = autoUpdate;
    [self refreshPrinterInfo];
    [self refreshStatus];
	
	return self;
}


- (double)nominalFilamentDiameter {
	return 1.75;
}


- (void)refreshCurrentFileInfo {
	__weak __typeof__(self) weakSelf = self;
	
	[self fetchInformationForFile:nil completion:^(TFDPrinterFileInfo *info) {
		weakSelf.currentFileInfo = info;
	}];
}


- (void)refreshStatus {
	__weak __typeof__(self) weakSelf = self;
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshStatus) object:nil];
	
	[self fetchPrinterStatusWithCompletion:^(TFDPrinterStatus *status) {
		TFDPrinter *self = weakSelf;
		
		//NSLog(@"Got status");
		if (status) {
			TFDPrinterState previousState = weakSelf.status.state;
			weakSelf.status = status;
			[self willChangeValueForKey:@"adjustedFilamentDiameter"];
			self->_adjustedFilamentDiameter = sqrt(pow(weakSelf.nominalFilamentDiameter, 2) / status.extrusionFactor);
			[self didChangeValueForKey:@"adjustedFilamentDiameter"];
			
			if (previousState != TFDPrinterStatePrinting && status.state == TFDPrinterStatePrinting) {
				[weakSelf refreshCurrentFileInfo];
			}
			
			weakSelf.lastSuccessfulUpdate = [NSDate date];
		}
        if (self.autoUpdate)
            [weakSelf performSelector:@selector(refreshStatus) withObject:nil afterDelay:1];
	}];
}


- (void)setAdjustedFilamentDiameter:(double)adjustedFilamentDiameter {
	_adjustedFilamentDiameter = adjustedFilamentDiameter;
	double factor = pow(self.nominalFilamentDiameter/2, 2) / pow(self.adjustedFilamentDiameter/2, 2);
	[self setExtrusionFactor:factor completion:nil];
}


- (NSURL*)URLWithPath:(NSString*)path query:(NSDictionary <NSString*, NSString*>*)query {
	NSURLComponents *components = [NSURLComponents new];
	components.scheme = @"http";
	components.host = self.hostname;
	components.port = @(self.port);
	components.path = path;
	
	components.queryItems = [query.allKeys tf_mapWithBlock:^NSURLQueryItem*(NSString *key) {
		NSString *value = query[key];
		return [NSURLQueryItem queryItemWithName:key value:value];
	}];
	/*
	components.percentEncodedQuery = [[query.allKeys tf_mapWithBlock:^NSString*(NSString *key) {
		NSString *value = [query[key] stringByReplacingOccurrencesOfString:@"/" withString:@"%2F"];
		return [NSString stringWithFormat:@"%@=%@", key, value];
	}] componentsJoinedByString:@"&"];
	*/
	
	//NSString *URLString = [NSString stringWithFormat:@"%@://%@:%ld%@?%@", components.scheme, components.host, components.port.longValue, components.percentEncodedPath, components.percentEncodedQuery];
	//return [NSURL URLWithString:URLString];
	
	return components.URL;
}


- (void)GETJSONFromPath:(NSString*)path query:(NSDictionary <NSString*, NSString*>*)query handler:(void(^)(NSError *error, id result))block {
	[[self.URLSession dataTaskWithURL:[self URLWithPath:path query:query] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		if (!data) {
			block(error, nil);
			return;
		}
		
		id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
		block(error, result);
	}] resume];
}


- (NSError*)errorFromJSONResponse:(NSDictionary*)dictionary {
	NSInteger code = [dictionary[@"err"] integerValue];
	if (code != 0) {
		return [NSError errorWithDomain:duetServerErrorDomain code:code userInfo:nil];
	} else {
		return nil;
	}
}


- (void)uploadFile:(NSData*)data toPath:(NSString*)path progress:(void(^)(int64_t sent, int64_t total))progressBlock completion:(void(^)(NSError *error))block {
    NSDate *date = [NSDate date];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"%Y-%m-%dT%HH:%mm:%ss";
    
	NSURL *URL = [self URLWithPath:@"/rr_upload" query:@{@"name": path, @"time": [formatter stringFromDate:date]}];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
	request.HTTPMethod = @"POST";
	request.HTTPBody = data;
	[request setValue:@"Basic dG9tYXNmOm1hcm9ja28y" forHTTPHeaderField:@"Authorization"];
	
	NSURLSessionDataTask *task = [self.URLSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		block(error ?: [self errorFromJSONResponse:json]);
	}];
	
	if (progressBlock) {
		self.uploadProgressBlocks[@(task.taskIdentifier)] = [progressBlock copy];
	}
	
	[task resume];
}



- (void)createDirectory:(NSString*)path completion:(void(^)(NSError *error))block {
	[self GETJSONFromPath:@"/rr_mkdir" query:@{@"dir": path} handler:^(NSError *error, NSDictionary *result) {
		if (error) {
			block(error);
		}
		NSInteger errorCode = [result[@"err"] integerValue];
		if (errorCode != 0) {
			block([NSError errorWithDomain:duetServerErrorDomain code:errorCode userInfo:nil]);
		} else {
			block(nil);
		}
	}];
}



- (void)moveFile:(NSString*)source toPath:(NSString*)destination completion:(void(^)(NSError *error))block {
	[self GETJSONFromPath:@"/rr_move" query:@{@"old": source, @"new": destination} handler:^(NSError *error, NSDictionary *result) {
		if (error) {
			block(error);
		}
		NSInteger errorCode = [result[@"err"] integerValue];
		if (errorCode != 0) {
			block([NSError errorWithDomain:duetServerErrorDomain code:errorCode userInfo:nil]);
		} else {
			block(nil);
		}
	}];
}



- (void)downloadFile:(NSString*)path progress:(void(^)(int64_t sent, int64_t total))progressBlock completion:(void(^)(NSData *data, NSError *error))block {
	NSURL *URL = [self URLWithPath:@"/rr_download" query:@{@"name": path}];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
	request.HTTPMethod = @"GET";
	
	NSURLSessionDataTask *task = [self.URLSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
		block(data, error);
	}];
	
	if (progressBlock) {
		// TBI
		self.downloadProgressBlocks[@(task.taskIdentifier)] = [progressBlock copy];
	}
	
	[task resume];
}



- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend {
	
	void(^progressBlock)(int64_t sent, int64_t total) = self.uploadProgressBlocks[@(task.taskIdentifier)];
	if (progressBlock) {
		progressBlock(totalBytesSent, totalBytesExpectedToSend);
	}
}



- (void)fetchPrinterStatusWithCompletion:(void(^)(TFDPrinterStatus *status))block {
	[self GETJSONFromPath:@"/rr_status" query:@{@"type": @"3"} handler:^(NSError *error, id root) {
		TFDPrinterStatus *status = root ? [[TFDPrinterStatus alloc] initWithJSON:root] : nil;
		block(status);
	}];
}


- (void)refreshPrinterInfo {
	__weak __typeof__(self) weakSelf = self;

	[self GETJSONFromPath:@"/rr_status" query:@{@"type": @"2"} handler:^(NSError *error, id root) {
		if (!root) {
			return;
		}
		weakSelf.name = root[@"name"];
	}];
}


- (TFDHeatingProgressState)heaterStateForHeater:(TFDHeaterStatus*)heater {
	double delta = heater.currentTemperature - heater.targetTemperature;
	
	if (heater.state == TFDHeaterStateOff || heater.targetTemperature <= FLT_EPSILON) {
		return TFDHeatingProgressStateOff;
	} else if (delta < -acceptableTemperatureThreshold) {
		return TFDHeatingProgressStateWarming;
	} else if (delta > acceptableTemperatureThreshold) {
		return TFDHeatingProgressStateCooling;
	} else {
		return TFDHeatingProgressStateAtTarget;
	}
}


- (double)fractionOfHeatingProgressForHeater:(TFDHeaterStatus*)heater {
	const double roomTemperature = 20;
	double current = heater.currentTemperature - roomTemperature;
	double target = heater.targetTemperature - roomTemperature;
	
	if (current < target) {
		return MIN(current / (target-acceptableTemperatureThreshold), 1);
	} else {
		return MIN((target+acceptableTemperatureThreshold) / current, 1);
	}
}


- (double)fractionOfBedHeaterProgress {
	return [self fractionOfHeatingProgressForHeater:self.status.bedHeaterStatus];
}


- (double)fractionOfHotendHeaterProgress {
	return [self fractionOfHeatingProgressForHeater:self.status.primaryHotendStatus];
}


- (TFDHeatingProgressState)bedHeaterProgressState {
	return [self heaterStateForHeater:self.status.bedHeaterStatus];
}


- (TFDHeatingProgressState)hotendHeaterProgressState {
	return [self heaterStateForHeater:self.status.primaryHotendStatus];
}


- (TFDPrinterHeaterMask)pendingHeaters {
	if (self.status.fractionPrinted > FLT_EPSILON) {
		return 0;
	}
	
	TFDPrinterHeaterMask mask = 0;
	if (self.bedHeaterState != TFDHeatingProgressStateAtTarget && self.bedHeaterState != TFDHeatingProgressStateOff) {
		mask |= TFDPrinterHeaterBed;
	}
	if (self.hotendHeaterState != TFDHeatingProgressStateAtTarget && self.hotendHeaterState != TFDHeatingProgressStateOff) {
		mask |= TFDPrinterHeaterHotend;
	}
	return mask;
}


- (NSDateFormatter*)duetDateFormatter {
	static NSDateFormatter *formatter;
	if (!formatter) {
		formatter = [NSDateFormatter new];
		formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss";
		formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	}
	return formatter;
}


- (void)fetchDirectoryListingForPath:(NSString*)path resultHandler:(void(^)(NSArray <TFDPrinterDirectoryItem*> *items))block {
	NSLog(@"List %@", path);
	
	[self GETJSONFromPath:@"/rr_filelist" query:@{@"dir": path} handler:^(NSError *error, id result) {
		NSArray <NSDictionary*> *list = result[@"files"];
		NSArray <TFDPrinterDirectoryItem*> *items = [list tf_mapWithBlock:^TFDPrinterDirectoryItem*(NSDictionary *dict) {
			TFDPrinterDirectoryItem *item = [TFDPrinterDirectoryItem new];
			
			item.name = dict[@"name"];
			item.path = [path stringByAppendingPathComponent:dict[@"name"]];
			item.isDirectory = [dict[@"type"] isEqual:@"d"];
			item.size = [dict[@"size"] unsignedLongLongValue];
			item.modificationDate = [[self duetDateFormatter] dateFromString:dict[@"date"]];
			
			return item;
		}];

		items = [items sortedArrayUsingDescriptors:@[
													 [NSSortDescriptor sortDescriptorWithKey:@"isDirectory" ascending:NO],
													 [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)]
													 ]];
		block(items);
	}];
}


- (void)performGCode:(NSString*)code completionHandler:(void(^)(NSError *error))block {
	[self GETJSONFromPath:@"/rr_gcode" query:@{@"gcode": code} handler:^(NSError *error, id result) {
		if (block) {
			block(error);
		}
	}];
}


- (void)performGCode:(NSString*)code {
	[self performGCode:code completionHandler:nil];
}

- (void)performGCodeFormat:(NSString*)format completionHandler:(void(^)(NSError *error))block, ... {
	va_list list;
	va_start(list, block);
	NSString *code = [[NSString alloc] initWithFormat:format arguments:list];
	va_end(list);
	[self performGCode:code completionHandler:block];
}


- (void)performGCodeFormat:(NSString*)format, ... {
	va_list list;
	va_start(list, format);
	NSString *code = [[NSString alloc] initWithFormat:format arguments:list];
	va_end(list);
	[self performGCode:code completionHandler:nil];
}



- (void)deleteItemAtPath:(NSString*)path completion:(void(^)())block {
	[self performGCodeFormat:@"M30 %@" completionHandler:block, path];
}


- (void)runMacroFile:(NSString*)path completion:(void(^)())block {
	[self performGCodeFormat:@"M98 P%@" completionHandler:block, path];
}


- (void)printFile:(NSString*)path completion:(void(^)())block {
	__weak __typeof__(self) weakSelf = self;
	
	[self performGCodeFormat:@"M32 %@" completionHandler:^(NSError *error) {
		[weakSelf refreshStatus];
		if (block) {
			block();
		}
	}, path];
}


- (void)homeWithCompletion:(void(^)())block {
	[self performGCodeFormat:@"G28" completionHandler:block];
}


- (void)probeWithCompletion:(void(^)())block {
	[self performGCodeFormat:@"G32" completionHandler:block];
}



- (void)cancelPrintWithCompletion:(void(^)())block {
	__weak __typeof__(self) weakSelf = self;
	[self performGCodeFormat:@"M0 H1" completionHandler:^(NSError *error){
		[weakSelf refreshStatus];
		[weakSelf homeWithCompletion:^{
			if (block) {
				block();
			}
		}];
	}];
}


- (void)pausePrintWithCompletion:(void(^)())block {
	__weak __typeof__(self) weakSelf = self;
	[self performGCodeFormat:@"M25" completionHandler:^(NSError *error){
		[weakSelf refreshStatus];
		if (block) {
			block();
		}
	}];
}


- (void)resumePrintWithCompletion:(void(^)())block {
	__weak __typeof__(self) weakSelf = self;
	[self performGCodeFormat:@"M24" completionHandler:^(NSError *error){
		[weakSelf refreshStatus];
		if (block) {
			block();
		}
	}];
}


- (void)setBedTemperature:(double)temperature completion:(void(^)())block {
	[self performGCodeFormat:@"M140 S%.0f" completionHandler:block, temperature];
}


- (void)clearFaultForHeater:(NSUInteger)heaterIndex completion:(void(^)())block {
	[self performGCodeFormat:@"M562 P%ld" completionHandler:block, (long)heaterIndex];
}


- (void)setHotendTemperature:(double)temperature completion:(void(^)())block {
	[self performGCodeFormat:@"M104 S%.0f" completionHandler:block, temperature];
}


- (void)setSpeedFactor:(double)factor completion:(void(^)())block {
	[self performGCodeFormat:@"M220 S%.02f" completionHandler:block, factor*100];
}


- (void)setExtrusionFactor:(double)factor completion:(void(^)())block {
	//NSLog(@"Set ex factor %.03f", factor);
	[self performGCodeFormat:@"M221 S%.02f" completionHandler:block, factor*100];
}


- (void)fetchInformationForFile:(NSString*)path completion:(void(^)(TFDPrinterFileInfo *info))block {
	[self GETJSONFromPath:@"/rr_fileinfo" query:(path ? @{@"name": path} : nil) handler:^(NSError *error, id json) {
		TFDPrinterFileInfo *info = [TFDPrinterFileInfo new];
		if (json[@"fileName"]) {
			info.path = json[@"fileName"];
		} else {
			info.path = path;
		}
		info.generator = json[@"generatedBy"];
		info.fileSize = [json[@"size"] unsignedLongLongValue];
		
		info.height = [json[@"height"] doubleValue];
		info.layerHeight = [json[@"layerHeight"] doubleValue];
		info.firstLayerHeight = [json[@"firstLayerHeight"] doubleValue];
		info.filamentLength = [[json[@"filament"] firstObject] doubleValue];
		
		block(info);
	}];
}


- (void)setSimulationMode:(BOOL)simulationMode {
	_simulationMode = simulationMode;
	[self performGCodeFormat:@"M37 S%d", simulationMode ? 1 : 0];
}


- (void)fetchSimulationDurationWithCompletion:(void(^)(NSTimeInterval duration))block {
	/*
	[self sendGCodeFormat:@"M37" response:^(NSString *response) {
		NSArray <NSString*> *pairs = [response componentsSeparatedByString:@", "];
		NSTimeInterval duration = 0;
		for (NSString *pairString in pairs) {
			NSArray <NSString*> *item = [pairString componentsSeparatedByString:@": "];
			if (item.count != 2) {
				continue;
			}
			NSString *key = item[0];
			NSString *value = item[1];
			
			if ([@[@"move time", @"other time"] containsObject:key]) {
				NSArray <NSString*> *words = [value componentsSeparatedByString:@" "];
				NSTimeInterval time = [words.firstObject doubleValue];
				duration += time;
			}
		}
		
		block(duration);
	}];
	 */
}



- (void)babystepWithOffset:(double)offset {
    [self performGCodeFormat:@"M290 S%.03f", offset];
}


- (void)setATXPower:(BOOL)power completion:(void(^)())block {
    if (power) {
        [self performGCodeFormat:@"M80" completionHandler:block];
    } else {
        [self performGCodeFormat:@"M81" completionHandler:block];
    }
}


@end
