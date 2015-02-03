//
//  CDStorage.m
//  LeanChat
//
//  Created by lzw on 15/1/29.
//  Copyright (c) 2015年 AVOS. All rights reserved.
//

#import "CDStorage.h"
#import "CDUtils.h"

#define MSG_TABLE_SQL @"CREATE TABLE IF NOT EXISTS `msgs` (`id` INTEGER PRIMARY KEY AUTOINCREMENT, `msg_id` VARCHAR(63) UNIQUE NOT NULL,`convid` VARCHAR(63) NOT NULL,`object` BLOB NOT NULL,`time` VARCHAR(63) NOT NULL)"
#define ROOMS_TABLE_SQL @"CREATE TABLE IF NOT EXISTS `rooms` (`id` INTEGER PRIMARY KEY AUTOINCREMENT,`convid` VARCHAR(63) UNIQUE NOT NULL,`unread_count` INTEGER DEFAULT 0)"

#define FIELD_ID @"id"
#define FIELD_CONVID @"convid"
#define FIELD_OBJECT @"object"
#define FIELD_TIME @"time"
#define FIELD_MSG_ID @"msg_id"

#define FIELD_UNREAD_COUNT @"unread_count"

static CDStorage* _storage;

@interface CDStorage(){
    
}

@property FMDatabaseQueue* dbQueue;

@end

@implementation CDStorage

+(instancetype)sharedInstance{
    if(_storage==nil){
        _storage=[[CDStorage alloc] init];
    }
    return _storage;
}

- (NSString *)dbPathWithUserId:(NSString*)userId {
    NSString *libPath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    return [libPath stringByAppendingPathComponent:[NSString stringWithFormat:@"chat_%@",userId]];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
    }
    return self;
}

-(void)setupWithUserId:(NSString*)userId{
    _dbQueue=[FMDatabaseQueue databaseQueueWithPath:[self dbPathWithUserId:userId]];
    [_dbQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:MSG_TABLE_SQL];
        [db executeUpdate:ROOMS_TABLE_SQL];
    }];
}

-(FMDatabaseQueue*)getDBQueue{
    return _dbQueue;
}

#pragma mark - msgs table

-(NSArray*)getMsgsWithConvid:(NSString*)convid maxTime:(int64_t)time limit:(int)limit db:(FMDatabase*)db{
    NSString* timeStr=[CDUtils strOfInt64:time];
    FMResultSet* rs=[db executeQuery:@"select * from msgs where convid=? and time<? order by time desc limit ?" withArgumentsInArray:@[convid,timeStr,@(limit)]];
    NSMutableArray* msgs=[self getMsgsByResultSet:rs];
    return [CDUtils reverseArray:msgs];
}

-(AVIMTypedMessage*)getMsgByMsgId:(NSString*)msgId{
    __block AVIMTypedMessage* msg=nil;
    [_dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet* rs=[db executeQuery:@"SELECT * FROM msgs where msg_id=?" withArgumentsInArray:@[msgId]];
        if([rs next]){
            msg=[self getMsgByResultSet:rs];
        }
        [rs close];
    }];
    return msg;
}

-(BOOL)updateMsg:(AVIMTypedMessage*)msg byMsgId:(NSString*)msgId{
    __block BOOL result;
    [_dbQueue inDatabase:^(FMDatabase *db) {
        NSData* data=[NSKeyedArchiver archivedDataWithRootObject:msg];
        result=[db executeUpdate:@"UPDATE msgs SET object=? WHERE msg_id=?" withArgumentsInArray:@[data,msgId]];
    }];
    return result;
}

-(BOOL)updateStatus:(AVIMMessageStatus)status byMsgId:(NSString*)msgId{
    AVIMTypedMessage* msg=[self getMsgByMsgId:msgId];
    if(msg){
        msg.status=status;
        return [self updateMsg:msg byMsgId:msgId];
    }else{
        return NO;
    }
}

-(NSMutableArray*)getMsgsByResultSet:(FMResultSet*)rs{
    NSMutableArray *result = [NSMutableArray array];
    while ([rs next]) {
        AVIMTypedMessage *msg=[self getMsgByResultSet:rs];
        [result addObject:msg];
    }
    [rs close];
    return result;
}

-(AVIMTypedMessage* )getMsgByResultSet:(FMResultSet*)rs{
    AVIMTypedMessage* msg;
    NSData* data=[rs objectForColumnName:FIELD_OBJECT];
    if(data!=nil){
        msg=[NSKeyedUnarchiver unarchiveObjectWithData:data];
    }
    return msg;
}

-(int64_t)insertMsg:(AVIMTypedMessage*)msg{
    __block int64_t rowId;
    [_dbQueue inDatabase:^(FMDatabase *db) {
        NSData* data=[NSKeyedArchiver archivedDataWithRootObject:msg];
        NSDictionary* dict=@{FIELD_MSG_ID:msg.messageId,FIELD_CONVID:msg.conversationId,FIELD_OBJECT:data,FIELD_TIME:[CDUtils strOfInt64:msg.sendTimestamp]};
        BOOL result=[db executeUpdate:@"insert into msgs (msg_id,convid,object,time) values(:msg_id,:convid,:object,:time)" withParameterDictionary:dict];
        if(result){
            rowId=[db lastInsertRowId];
        }else{
            rowId=-1;
        }
    }];
    return rowId;
}

#pragma mark - rooms table

-(CDRoom*)getRoomByResultSet:(FMResultSet*)rs{
    CDRoom* room=[[CDRoom alloc] init];
    room.convid=[rs stringForColumn:FIELD_CONVID];
    room.unreadCount=[rs intForColumn:FIELD_UNREAD_COUNT];
    room.lastMsg=[self getMsgByResultSet:rs];
    return room;
}

-(NSArray*)getRooms{
    NSMutableArray* rooms=[NSMutableArray array];
    [_dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet* rs=[db executeQuery:@"SELECT * FROM rooms JOIN msgs ON rooms.convid=msgs.convid GROUP BY msgs.convid ORDER BY msgs.time DESC"];
        while ([rs next]) {
            [rooms addObject:[self getRoomByResultSet:rs]];
        }
        [rs close];
    }];
    return rooms;
}

-(void)insertRoomWithConvid:(NSString*)convid{
    [_dbQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"INSERT INTO ROOMS (convid) VALUES(?) " withArgumentsInArray:@[convid]];
    }];
}

@end