//
//  PQAPacket.h
//  PQAApp
//
//  Created by Avinash Tag on 20/04/16.
//  Copyright © 2016 Rohde & Schwarz. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PQAPacket : NSObject


@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, strong) NSNumber *recieved;
@end
