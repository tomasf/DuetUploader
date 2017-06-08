#import "TFDExtras.h"
@import MachO;


@implementation NSArray (TFPExtras)

- (NSArray*)tf_mapWithBlock:(id(^)(id object))function {
	NSMutableArray *array = [NSMutableArray new];
	for(id object in self) {
		id value = function(object);
		if(value) {
			[array addObject:value];
		}
	}
	return array;
}


- (NSArray*)tf_selectWithBlock:(BOOL(^)(id object))function {
	NSMutableArray *array = [NSMutableArray new];
	for(id object in self) {
		if(function(object)) {
			[array addObject:object];
		}
	}
	return array;
}


- (NSArray*)tf_rejectWithBlock:(BOOL(^)(id object))function {
	return [self tf_selectWithBlock:^BOOL(id object) {
		return !function(object);
	}];
}


- (NSSet*)tf_set {
	return [NSSet setWithArray:self];
}


@end


void TFLog(NSString *format, ...) {
	va_list list;
	va_start(list, format);
	NSString *string = [[NSString alloc] initWithFormat:format arguments:list];
	va_end(list);
	printf("%s\n", string.UTF8String);
}


uint64_t TFNanosecondTime(void) {
	mach_timebase_info_data_t info;
	mach_timebase_info(&info);
	return (mach_absolute_time() * info.numer) / info.denom;
}


void TFAssertMainThread() {
	NSCAssert([NSThread isMainThread], @"Whoa. This should be on the main thread but isn't!");
}


void TFMainThread(void(^block)()) {
	if([NSThread isMainThread]) {
		block();
	}else{
		dispatch_async(dispatch_get_main_queue(), block);
	}
}
