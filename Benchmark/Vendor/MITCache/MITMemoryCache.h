//
//  MITMemoryCache.h
//  MITCache
//
//  Created by MENGCHEN on 2017/2/27.
//  Copyright © 2017年 MENGCHEN. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MITMemoryCache;

typedef void (^MITCacheMemoryBlock)(MITMemoryCache*);

typedef void (^MITCacheBackGroudBlock)(MITMemoryCache*);

@interface MITMemoryCache : NSObject


/** 数量限制 */
@property(nonatomic, assign)NSUInteger countLimit;
/** 消耗限制 */
@property(nonatomic, assign)NSUInteger  costLimit;
/** 时间限制 */
@property(nonatomic, assign)NSTimeInterval ageLimit;

/** 内存警告回调 */
@property(nonatomic, copy)MITCacheMemoryBlock memoryCallBack;
/** 当收到内存警告时是否清除所有数据 */
@property(nonatomic, assign)BOOL deleteAllWhieMemoryWarning;

/** 进入后台回调 */
@property(nonatomic, copy)MITCacheBackGroudBlock backgroudCallBack;
/** 进入后台删除所有 */
@property(nonatomic, assign)BOOL deleteAllWhileBackGroud;

/** 主线程释放 */
@property(nonatomic, assign)BOOL * releaseOnMainThread;
/** 是否异步释放 */
@property(nonatomic, assign)BOOL * releaseAsynchronously;


/** 缓存名称 */
@property(nonatomic, strong)NSString * name;

- (void)setObject:(id)object forKey:(id)key;
- (id)objectForKey:(id)key;
- (void)removeObjectForKey:(id)key;
- (void)removeAllObjects;
@end
