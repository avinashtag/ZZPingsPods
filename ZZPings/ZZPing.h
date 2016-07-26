//
//  ATPing.h
//  ATPing
//
//  Created by Avinash Tag on 12/01/16.
//  Copyright © 2016   . All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ICMPHeader.h"

@interface ZZPingDetails : NSObject <NSCopying>

@property (assign, nonatomic) NSUInteger            sequenceNumber;
@property (assign, nonatomic) NSUInteger            payloadSize;
@property (assign, nonatomic) NSUInteger            ttl;
@property (strong, nonatomic) NSString              *host;
@property (strong, nonatomic) NSNumber    *latency;

@end


@interface ZZPing : NSObject

typedef void(^PingDidStartWithAddress)(ZZPingDetails *ping, NSString *hostName);
typedef void(^PingDidSendPacket)(ZZPingDetails *ping);
typedef void(^PingDidReceivePingResponsePacket)(ZZPingDetails *ping);
typedef void(^PingDidReceiveUnexpectedPacket)(ZZPingDetails *ping);
typedef void(^PingDidFailToSendPacket)(ZZPingDetails *ping, NSError *error);
typedef void(^PingDidTimeoutToSendPacket)(ZZPingDetails *ping);
typedef void(^PingDidFailWithError)(NSError *error);
typedef void(^PingDidFailWithTimeout)(ZZPingDetails *ping);
typedef void(^PingSendFinalReport)(NSArray *pings);


@property (nonatomic, copy) PingDidStartWithAddress             pingDidStartWithAddress;
@property (nonatomic, copy) PingDidFailWithError                pingDidFailWithError;
@property (nonatomic, copy) PingDidSendPacket                   pingDidSendPacket;
@property (nonatomic, copy) PingDidFailToSendPacket             pingDidFailToSendPacket;
@property (nonatomic, copy) PingDidReceivePingResponsePacket    pingDidReceivePingResponsePacket;
@property (nonatomic, copy) PingDidReceiveUnexpectedPacket      pingDidReceiveUnexpectedPacket;
@property (nonatomic, copy) PingDidFailWithTimeout              pingDidFailWithTimeout;

@property (nonatomic, strong) NSNumber *dnf;
@property (nonatomic, strong) NSNumber *sendReport;
@property (nonatomic, strong) NSNumber *wait;
@property (nonatomic, strong) NSString *serviceId;

// Called after the   ATPing has successfully started up.  After this callback, you
// can start sending pings via -sendPingWithData:
- (void)didStartWithAddress:(PingDidStartWithAddress)startWithAddress;

// If this is called, the   ATPing object has failed.  By the time this callback is
// called, the object has stopped (that is, you don't need to call -stop yourself).
- (void)didFailError:(PingDidFailWithError )fail;


// IMPORTANT: On the send side the packet does not include an IP header.
// On the receive side, it does.  In that case, use +[  ATPing icmpInPacket:]
// to find the ICMP header within the packet.

// Called whenever the   ATPing object has successfully sent a ping packet.
- (void)didSendPacket:(PingDidSendPacket )packet;

// Called whenever the   ATPing object tries and fails to send a ping packet.
- (void)didFailToSendPacket:(PingDidFailToSendPacket)fail;

// Called whenever the   ATPing object receives an ICMP packet that looks like
// a response to one of our pings (that is, has a valid ICMP checksum, has
// an identifier that matches our identifier, and has a sequence number in
// the range of sequence numbers that we've sent out).
- (void)didReceivePingResponsePacket:(PingDidReceivePingResponsePacket)receiveResponse;

// Called whenever the   ATPing object receives an ICMP packet that does not
// look like a response to one of our pings.
- (void)didReceiveUnexpectedPacket:(PingDidReceiveUnexpectedPacket)receiveResponse;



- (void)didTimeout:(PingDidFailWithTimeout )timeout;


+ (ZZPing *)  pingWithHostName:(NSString *)hostName;        // chooses first IPv4 address
+ (ZZPing *)  pingWithHostAddress:(NSString *)hostAddress;    // contains (struct sockaddr)
- (NSNumber *) latencyPerSec;

@property (nonatomic, copy,   readonly ) NSString *             hostName;
@property (nonatomic, copy,   readonly ) NSData *               hostAddress;
@property (nonatomic, assign, readonly ) uint16_t               identifier;
@property (nonatomic, assign, readonly ) uint16_t               nextSequenceNumber;
@property (assign, atomic) NSUInteger                           ttl;
@property (assign, atomic) NSUInteger                           payloadSize;
@property (assign, atomic) NSUInteger                           packetCount;
@property (assign, atomic) NSTimeInterval                       timeout;
@property (strong, nonatomic, readonly) NSNumber                *averageLatency;
@property (strong, nonatomic, readonly) NSNumber                *minimumLatency;
@property (strong, nonatomic, readonly) NSNumber                *maximumLatency;

@property (nonatomic, strong)__block NSMutableDictionary           *pings;

- (void)start;
// Starts the pinger object pinging.  You should call this after
// you've setup the delegate and any ping parameters.

- (void)sendPingWithData:(NSData *)data;
- (void)sendPing;
// Sends an actual ping.  Pass nil for data to use a standard 56 byte payload (resulting in a
// standard 64 byte ping).  Otherwise pass a non-nil value and it will be appended to the
// ICMP header.
//
// Do not try to send a ping before you receive the -  ATPing:didStartWithAddress: delegate
// callback.

- (void)stop;
// Stops the pinger object.  You should call this when you're done
// pinging.

-(void) destroy;

+ (const struct ICMPHeader *)icmpInPacket:(NSData *)packet;
// Given a valid IP packet contains an ICMP , returns the address of the ICMP header that
// follows the IP header.  This doesn't do any significant validation of the packet.

@end
