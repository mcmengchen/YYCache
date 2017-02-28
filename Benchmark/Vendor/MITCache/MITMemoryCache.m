//
//  MITMemoryCache.m
//  MITCache
//
//  Created by MENGCHEN on 2017/2/27.
//  Copyright © 2017年 MENGCHEN. All rights reserved.
//

#import "MITMemoryCache.h"
#import <QuartzCore/QuartzCore.h>
#import <pthread.h>
#import <UIKit/UIKit.h>



static inline dispatch_queue_t MitMemoryCacheGetReleaseQueue() {
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
}

#define UNEXPECT(A) __builtin_expect((A),0)
#define EXPECT(A) __builtin_expect((A),1)


@interface MITMapNode: NSObject{
    @package
    //前向指针
    __unsafe_unretained MITMapNode * preNode;
    //后向指针
    __unsafe_unretained MITMapNode * nextNode;
    id _key;
    id _value;
    NSTimeInterval _time;
    NSUInteger _cost;
}

@end
@implementation MITMapNode


-(NSString *)description{
    return [NSString stringWithFormat:@" %@",_value];
}
@end


//hash 表
@interface MITHashMap :NSObject{
    @package
    CFMutableDictionaryRef _dic;
    NSUInteger _totalCost;
    NSUInteger _totalNum;
    MITMapNode * _head;
    MITMapNode * _tail;
}
//增加
- (void)insertToFirst:(MITMapNode *)node;
//删除
- (void)deleteNode:(MITMapNode *)node;
//移到首位
- (void)moveToFirst:(MITMapNode *)node;
//移除末尾
- (MITMapNode *)deleteLast;
//移除所有
- (void)deleteAll;


@end
@implementation MITHashMap
{
    @package
    BOOL _releaseAsynchronously;
    BOOL _releaseOnMainThread;
    
}

-(instancetype)init{
    if (self = [super init]) {
        //创建字典
        _dic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        _releaseAsynchronously = true;
        _releaseOnMainThread = false;
    }
    return self;
    
}

#pragma mark action 增
- (void)insertToFirst:(MITMapNode *)node {
    CFDictionarySetValue(_dic, (const void *)(node->_key),  (const void *)(node));
    _totalCost += node->_cost;
    _totalNum++;
    if (_head) {
        node->nextNode = _head;
        _head->preNode = node;
        _head = node;
    }else{
        _head = _tail = node;
    }
}

#pragma mark action 移到首位
- (void)moveToFirst:(MITMapNode *)node{
    //如果头部就是 node，直接返回
    if (_head == node) {
        return;
    }
    
    if (_tail == node) {
        _tail = node->preNode;
        _tail->nextNode = nil;
    }else{
        node->preNode->nextNode = node->nextNode;
        node->nextNode->preNode = node->preNode;
    }
    node->preNode = nil;
    node->nextNode = _head;
    _head->preNode = node;
    _head = node;
}


#pragma mark action 删
- (void)deleteNode:(MITMapNode *)node {
    CFDictionaryRemoveValue(_dic, (__bridge const void*)node->_key);
    _totalCost -=node->_cost;
    _totalNum --;
    if (node->nextNode) {
        node->nextNode->preNode = node->preNode;
    }
    if (node->preNode) {
        node->preNode->nextNode = node->nextNode;
    }
    if (_head == node) {
        _head = node->nextNode;
    }
    if (_tail == node) {
        _tail = node->preNode;
    }
}



#pragma mark action 删所有
- (void)deleteAll{
    _totalCost = 0;
    _totalNum = 0;
    _head = nil;
    _tail = nil;
    if (CFDictionaryGetCount(_dic) > 0) {
        CFMutableDictionaryRef holder = _dic;
        _dic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        if (_releaseAsynchronously) {
            dispatch_queue_t queue = _releaseOnMainThread ? dispatch_get_main_queue() : MitMemoryCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                CFRelease(holder);
            });
        } else if (_releaseOnMainThread && !pthread_main_np()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                CFRelease(holder);
            });
        } else {
            CFRelease(holder);
        }
    }
}

#pragma mark action 删除末尾
- (MITMapNode *)deleteLast{
    if (_tail) {
        [self deleteNode:_tail];
        _totalCost -= _tail->_cost;
        _totalNum--;
        return _tail;
    }else{
        return nil;
    }
}

-(void)dealloc{
    CFRelease(_dic);
}



@end





@implementation MITMemoryCache
{
    //    pthread_mutex_t _lock;
    dispatch_semaphore_t _lock;
    MITHashMap * _hashMap;
    dispatch_queue_t _queue;
}

#pragma mark action init
-(instancetype)init{
    if (self = [super init]) {
        [self initLock];
        _hashMap = [[MITHashMap alloc]init];
        _queue = dispatch_queue_create("com.mithcell.mitmemory.cache", DISPATCH_QUEUE_SERIAL);
        _countLimit = NSUIntegerMax;
        _ageLimit = DBL_MAX;
        _costLimit = NSUIntegerMax;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appReceiveMemoryWarning) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    }
    return self;
}


#pragma mark ------------------ Add ------------------
#pragma mark action 设置对象
- (void)setObject:(id)object forKey:(id)key {
    [self setObject:object forKey:key cost:0];
}

#pragma mark action 为 key 设置对象，消耗
- (void)setObject:(id)object forKey:(id)key cost:(NSUInteger)cost {
    if (UNEXPECT(!key)) {
        return;
    }
    if (UNEXPECT(!object)) {
        [self removeObjectForKey:key];
        return;
    }
    [self lock];
    MITMapNode * node = CFDictionaryGetValue(_hashMap->_dic, (__bridge const void *)(key));
    NSTimeInterval now = CACurrentMediaTime();
    if (node) {
        _hashMap->_totalCost -= node->_cost;
        _hashMap->_totalCost += cost;
        node->_cost +=cost;
        node->_time = now;
        node->_value = object;
        [_hashMap moveToFirst:node];
    }else{
        node = [MITMapNode new];
        node->_time = now;
        node->_cost = 0;
        node->_key = key;
        node->_value = object;
        [_hashMap insertToFirst:node];
    }
    //设置 cost
    if (_hashMap->_totalCost > _costLimit) {
        dispatch_async(_queue, ^{
            [self deleteCostToNum:_costLimit];
        });
    }
    //设置数量
    if (_hashMap->_totalNum >_countLimit) {
        MITMapNode * removeNode = [_hashMap deleteLast];
        if (_hashMap->_releaseAsynchronously) {
            //这里是为了在制定的线程去释放
            dispatch_queue_t queue = _hashMap->_releaseOnMainThread ? dispatch_get_main_queue() : MitMemoryCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                [removeNode class]; //hold and release in queue
            });
        } else if (_hashMap->_releaseOnMainThread && !pthread_main_np()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [removeNode class]; //hold and release in queue
            });
        }
    }
    [self unlock];
}


#pragma mark ------------------ Delete ------------------
#pragma mark action 删除Cost
- (void)deleteCostToNum:(NSUInteger)cost{
    BOOL isfinish = false;
    [self lock];
    if (cost == 0) {
        [_hashMap deleteAll];
        isfinish = true;
    } else if(_hashMap->_totalCost<cost){
        isfinish = true;
    }
    [self unlock];
    if (isfinish) {
        return;
    }
    while (!isfinish) {
        [self lock];
        if (_hashMap->_totalCost>cost) {
            [_hashMap deleteLast];
        } else {
            isfinish = true;
        }
        [self unlock];
    }
}

#pragma mark action 删除到 age
- (void)deleteWithAge:(NSTimeInterval)age{
    BOOL isFinish = false;
    NSTimeInterval now = CACurrentMediaTime();
    [self lock];
    if (age<=0) {
        [_hashMap deleteAll];
        isFinish = true;
    }else if(!_hashMap->_tail||(now - _hashMap->_tail->_time)>age){
        
        isFinish = true;
    }
    if (isFinish) {
        return;
    }
    [self unlock];
    
    while (!isFinish) {
        [self lock];
        if ((now - _hashMap->_tail->_time)>age) {
            [_hashMap deleteLast];
        }else{
            isFinish = true;
        }
        [self unlock];
    }
}

#pragma mark action 根据数量去减少
- (void)deleteWithCount:(NSUInteger)count{
    BOOL finish = NO;
    [self lock];
    if (_countLimit == 0||count ==0) {
        [self removeAllObjects];
        finish = YES;
    } else if (_hashMap->_totalNum <= _countLimit) {
        finish = YES;
    }
    [self unlock];
    if (finish) return;
    NSMutableArray *holder = [NSMutableArray new];
    while (!finish) {
        [self lock];
        MITMapNode * node = [_hashMap deleteLast];
        if (node) {
            [holder addObject:node];
        }
        [self unlock];
    }
    if (holder.count) {
        dispatch_queue_t queue = _hashMap->_releaseOnMainThread ? dispatch_get_main_queue() : MitMemoryCacheGetReleaseQueue();
        dispatch_async(queue, ^{
            [holder count];
        });
    }
}




#pragma mark action 移除对象
- (void)removeObjectForKey:(id)key {
    if (UNEXPECT(!key)) {
        return;
    }
    [self lock];
    MITMapNode * node = CFDictionaryGetValue(_hashMap->_dic, (__bridge const void *)(key));
    if (node) {
        [_hashMap deleteNode:node];
    }
    [self unlock];
}

#pragma mark action 获取对象
-(id)objectForKey:(id)key{
    if (UNEXPECT(!key)) {
        return nil;
    }
    [self lock];
    MITMapNode * node = CFDictionaryGetValue(_hashMap->_dic, (__bridge const void*)key);
    if (node) {
        node->_time = CACurrentMediaTime();
        [_hashMap moveToFirst:node];
    }
    [self unlock];
    return node?node:nil;
    
}

#pragma mark action 移除所有对象
- (void)removeAllObjects{
    [_hashMap deleteAll];
}

#pragma mark ------------------ Lock ------------------

#pragma mark action 锁
- (void)lock{
    //    pthread_mutex_lock(&_lock);
    dispatch_semaphore_wait(_lock, DISPATCH_TIME_FOREVER);
}
#pragma mark action 解锁
- (void)unlock{
    //    pthread_mutex_unlock(&_lock);
    dispatch_semaphore_signal(_lock);
}

#pragma mark action 初始化锁
- (void)initLock{
    //pthread_mutex_init(&_lock, NULL);
    _lock = dispatch_semaphore_create(1);
}
#pragma mark action 销毁锁
- (void)destroyLock{
    
    //    pthread_mutex_destroy(&_lock);

}


#pragma mark action dealloc
-(void)dealloc{
    [[NSNotificationCenter defaultCenter]removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [[NSNotificationCenter defaultCenter]removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    [_hashMap deleteAll];
    [self destroyLock];
}


#pragma mark ------------------ Setter & Getter ------------------

#pragma mark action 设置 cost 限制
-(void)setCostLimit:(NSUInteger)costLimit{
    [self lock];
    _costLimit = costLimit;
    [self unlock];
    
}
#pragma mark action 设置时间限制
-(void)setAgeLimit:(NSTimeInterval)ageLimit{
    [self lock];
    _ageLimit = ageLimit;
    [self unlock];
}

#pragma mark action 设置数量限制
-(void)setCountLimit:(NSUInteger)countLimit{
    [self lock];
    _countLimit = countLimit;
    [self unlock];
    if (CFDictionaryGetCount(_hashMap->_dic)>countLimit) {
        [self deleteWithCount:countLimit];
    }
}



#pragma mark ------------------ 通知方法 ------------------

#pragma mark action 收到内存警告
- (void)appReceiveMemoryWarning {
    if (self.memoryCallBack) {
        self.memoryCallBack(self);
    }
    if (self.deleteAllWhieMemoryWarning) {
        [self removeAllObjects];
    }
}

#pragma mark action 进入后台
- (void)appDidEnterBackground {
    if (self.backgroudCallBack) {
        self.backgroudCallBack(self);
    }
    if (self.deleteAllWhileBackGroud) {
        [self removeAllObjects];
    }
}


#pragma mark action 重写描述
-(NSString *)description{
    if (_name) return [NSString stringWithFormat:@"<%@: %p> (%@) %@", self.class, self, _name,_hashMap];
    else return [NSString stringWithFormat:@"<%@: %p> %@", self.class, self,_hashMap->_dic];
}


@end
