@import Foundation;


@interface NSArray (TFPExtras)
- (NSArray*)tf_mapWithBlock:(id(^)(id object))function;
- (NSArray*)tf_selectWithBlock:(BOOL(^)(id object))function;
- (NSArray*)tf_rejectWithBlock:(BOOL(^)(id object))function;
- (NSSet*)tf_set;
@end


extern void TFLog(NSString *format, ...);
extern uint64_t TFNanosecondTime(void);
extern void TFAssertMainThread();
extern void TFMainThread(void(^block)());
