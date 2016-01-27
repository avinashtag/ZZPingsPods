//
//  ZZPing.m
//  ZZPing
//
//  Created by Avinash Tag on 12/01/16.
//  Copyright © 2016   . All rights reserved.
//

#import "ZZPing.h"
#import "ZZPings.h"
#if TARGET_OS_EMBEDDED || TARGET_IPHONE_SIMULATOR
#import <CFNetwork/CFNetwork.h>
#else
#import <CoreServices/CoreServices.h>
#endif

#import "ICMPHeader.h"

#include <sys/socket.h>
#include <netinet/in.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/types.h>
#include <arpa/inet.h>
#include <netdb.h>


@interface ZZPingDetails ()

@property (strong, nonatomic) NSDate                *sendDate;
@property (strong, nonatomic) NSDate                *receiveDate;

@end


@implementation ZZPingDetails

#pragma mark * ICMP On-The-Wire Format

static uint16_t in_cksum(const void *buffer, size_t bufferLen)
// This is the standard BSD checksum code, modified to use modern types.
{
    size_t              bytesLeft;
    int32_t             sum;
    const uint16_t *    cursor;
    union {
        uint16_t        us;
        uint8_t         uc[2];
    } last;
    uint16_t            answer;
    
    bytesLeft = bufferLen;
    sum = 0;
    cursor = buffer;
    
    /*
     * Our algorithm is simple, using a 32 bit accumulator (sum), we add
     * sequential 16 bit words to it, and at the end, fold back all the
     * carry bits from the top 16 bits into the lower 16 bits.
     */
    while (bytesLeft > 1) {
        sum += *cursor;
        cursor += 1;
        bytesLeft -= 2;
    }
    
    /* mop up an odd byte, if necessary */
    if (bytesLeft == 1) {
        last.uc[0] = * (const uint8_t *) cursor;
        last.uc[1] = 0;
        sum += last.us;
    }
    
    /* add back carry outs from top 16 bits to low 16 bits */
    sum = (sum >> 16) + (sum & 0xffff);	/* add hi 16 to low 16 */
    sum += (sum >> 16);			/* add carry */
    answer = (uint16_t) ~sum;   /* truncate to 16 bits */
    
    return answer;
}


#pragma mark - custom acc

-(void)setHost:(NSString *)host {
    _host = host;
}

-(NSNumber *)latency {
    if (self.sendDate) {
        return  @(([self.receiveDate timeIntervalSinceDate:self.sendDate]) *1000);
    }
    else {
        return @(0);
    }
}

#pragma mark - copying

-(id)copyWithZone:(NSZone *)zone {
    ZZPingDetails *copy = [[[self class] allocWithZone:zone] init];
    copy.sequenceNumber = self.sequenceNumber;
    copy.payloadSize = self.payloadSize;
    copy.ttl = self.ttl;
    copy.host = [self.host copy];
    copy.sendDate = [self.sendDate copy];
    copy.receiveDate = [self.receiveDate copy];
    return copy;
}

#pragma mark - memory

-(id)init {
    if (self = [super init]) {
    }
    return self;
}

-(void)dealloc {
    self.host = nil;
    self.sendDate = nil;
    self.receiveDate = nil;
}

#pragma mark - description

-(NSString *)description {
//    64 bytes from 10.13.148.148: icmp_seq=0 ttl=64 time=119.609 ms
    return [NSString stringWithFormat:@"%lu bytes icmp_seq=%lu  ttl=%lu  rtt=%0.3fms", (unsigned long)self.payloadSize, (unsigned long)self.sequenceNumber, (unsigned long)self.ttl, [self.latency doubleValue]];
}


@end



@interface ZZPing ()

@property (nonatomic, copy,   readwrite) NSData *           hostAddress;
@property (nonatomic, assign, readwrite) uint16_t           nextSequenceNumber;
@property (nonatomic, strong)__block NSMutableDictionary           *pings;

- (void)stopHostResolution;
- (void)stopDataTransfer;

@end

@implementation ZZPing
{
    CFHostRef               _host;
    CFSocketRef             _socket;
    NSUInteger              _ttl;
    NSUInteger              _packetCount;
    NSTimeInterval          _timeout;
    NSUInteger              _payloadSize;
    
    
}
static NSUInteger       const kDefaultPayloadSize   =   64;
static NSUInteger       const kDefaultTTL           =   49;
static NSUInteger       const kDefaultPacketCount   =   1;
static NSTimeInterval   const kDefaultTimeout       =   60.0;
static dispatch_source_t timer;

@synthesize hostName           = _hostName;
@synthesize hostAddress        = _hostAddress;

@synthesize identifier         = _identifier;
@synthesize nextSequenceNumber = _nextSequenceNumber;


#pragma mark - @property Setter Getter

-(void)setTtl:(NSUInteger)ttl {
    @synchronized(self) {
            _ttl = ttl;
    }
}

-(NSUInteger)ttl {
    @synchronized(self) {
        return _ttl ? _ttl : kDefaultTTL;
    }
}

-(void)setPayloadSize:(NSUInteger)payloadSize {
    @synchronized(self) {
        _payloadSize = payloadSize;
    }
}

-(NSUInteger)payloadSize {
    @synchronized(self) {
        return _payloadSize ? _payloadSize : kDefaultPayloadSize;
    }
}
-(void)setTimeout:(NSTimeInterval)timeout {
    @synchronized(self) {
        _timeout = timeout;
    }
}

-(NSTimeInterval)timeout {
    @synchronized(self) {
        return _timeout ? _timeout : kDefaultTimeout;
    }
}

-(void)setPacketCount:(NSUInteger)packetCount {
    @synchronized(self) {
        _packetCount = packetCount;
    }
}

-(NSUInteger)packetCount {
    @synchronized(self) {
        return _packetCount ? _packetCount : kDefaultPacketCount;
    }
}

- (NSNumber *)minimumLatency{
    return [[[self.pings allValues]valueForKeyPath:@"self.latency"] valueForKeyPath:@"@min.self"];
}

- (NSNumber *)averageLatency{
    return [[[self.pings allValues]valueForKeyPath:@"self.latency"] valueForKeyPath:@"@avg.self"];
}

- (NSNumber *)maximumLatency{
    return [[[self.pings allValues]valueForKeyPath:@"self.latency"] valueForKeyPath:@"@max.self"];
}


#pragma mark memory

+ (ZZPing *)pingWithHostName:(NSString *)hostName{
    return [[ZZPing alloc] initWithHostName:hostName address:nil];
}

+ (ZZPing *)pingWithHostAddress:(NSString *)hostAddress{
    return [[ZZPing alloc] initWithHostName:NULL address:hostAddress];
}


- (id)initWithHostName:(NSString *)hostName address:(NSString *)address{
    
    assert( (hostName != nil) == (address == nil) );
    self = [super init];
    if (self != nil) {
        self->_hostName    = [hostName copy];
        self->_hostAddress = [[self convertToAddress:address] copy];
        self->_identifier  = (uint16_t) arc4random();
        self.pings = [[NSMutableDictionary alloc]init];
    }
    return self;
}

- (void)dealloc{
    
    [self stop];
    assert(self->_host == NULL);
    assert(self->_socket == NULL);
}

-(NSData *)convertToAddress:(NSString *)hostAddress{
    
    const char *address = [hostAddress UTF8String];
    struct sockaddr_in serverAddr;
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_len = sizeof(serverAddr);
    serverAddr.sin_port = htons(80);
    serverAddr.sin_addr.s_addr = inet_addr(address);
    return [NSData dataWithBytes:&serverAddr length:serverAddr.sin_len];
}


#pragma mark Ping Block Setter

- (void)didStartWithAddress:(PingDidStartWithAddress)startWithAddress{
    self.pingDidStartWithAddress = startWithAddress;
}

- (void)didFailError:(PingDidFailWithError )fail{
    self.pingDidFailWithError = fail;
}

- (void)didSendPacket:(PingDidSendPacket )packet{
    self.pingDidSendPacket = packet;
}

- (void)didFailToSendPacket:(PingDidFailToSendPacket)fail{
    self.pingDidFailToSendPacket = fail;
}

- (void)didReceivePingResponsePacket:(PingDidReceivePingResponsePacket)receiveResponse{
    self.pingDidReceivePingResponsePacket = receiveResponse;
}

- (void)didReceiveUnexpectedPacket:(PingDidReceiveUnexpectedPacket)receiveResponse{
    self.pingDidReceiveUnexpectedPacket = receiveResponse;
}

- (void)didTimeout:(PingDidFailWithTimeout )timeout{
    self.pingDidFailWithTimeout = timeout;
}

- (void)didSendFinalReport:(PingSendFinalReport)report{
    self.pingSendFinalReport = report;
}

#pragma mark ICMP Headers

+ (NSUInteger)icmpHeaderOffsetInPacket:(NSData *)packet{
    NSUInteger              result;
    const struct IPHeader * ipPtr;
    size_t                  ipHeaderLength;
    
    result = NSNotFound;
    if ([packet length] >= (sizeof(IPHeader) + sizeof(ICMPHeader))) {
        ipPtr = (const IPHeader *) [packet bytes];
        assert((ipPtr->versionAndHeaderLength & 0xF0) == 0x40);     // IPv4
        assert(ipPtr->protocol == 1);                               // ICMP
        ipHeaderLength = (ipPtr->versionAndHeaderLength & 0x0F) * sizeof(uint32_t);
        if ([packet length] >= (ipHeaderLength + sizeof(ICMPHeader))) {
            result = ipHeaderLength;
        }
    }
    return result;
}

+ (const struct ICMPHeader *)icmpInPacket:(NSData *)packet{
    const struct ICMPHeader *   result;
    NSUInteger                  icmpHeaderOffset;
    
    result = nil;
    icmpHeaderOffset = [self icmpHeaderOffsetInPacket:packet];
    if (icmpHeaderOffset != NSNotFound) {
        result = (const struct ICMPHeader *) (((const uint8_t *)[packet bytes]) + icmpHeaderOffset);
    }
    return result;
}


#pragma mark C Routine Callback

static void SocketReadCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
// This C routine is called by CFSocket when there's data waiting on our
// ICMP socket.  It just redirects the call to Objective-C code.
{
    dispatch_source_cancel(timer);
    ZZPing *    obj;
    
    obj = (__bridge ZZPing *) info;
    assert([obj isKindOfClass:[ZZPing class]]);
    
#pragma unused(s)
    assert(s == obj->_socket);
#pragma unused(type)
    assert(type == kCFSocketReadCallBack);
#pragma unused(address)
    assert(address == nil);
#pragma unused(data)
    assert(data == nil);
    [obj readData];
}

static void HostResolveCallback(CFHostRef theHost, CFHostInfoType typeInfo, const CFStreamError *error, void *info)
// This C routine is called by CFHost when the host resolution is complete.
// It just redirects the call to the appropriate Objective-C method.
{
    ZZPing *    obj;
    
    
    obj = (__bridge ZZPing *) info;
    assert([obj isKindOfClass:[ZZPing class]]);
    
#pragma unused(theHost)
    assert(theHost == obj->_host);
#pragma unused(typeInfo)
    assert(typeInfo == kCFHostAddresses);
    
    if ( (error != NULL) && (error->domain != 0) ) {
        [obj didFailWithHostStreamError:*error];
    } else {
        [obj hostResolutionDone];
    }
}

#pragma mark Start Ping

- (void)startWithHostAddress
// We have a host address, so let's actually start pinging it.
{
    int                     err;
    int                     fd;
    const struct sockaddr * addrPtr;
    
    assert(self.hostAddress != nil);
    
    // Open the socket.
    
    addrPtr = (const struct sockaddr *) [self.hostAddress bytes];
    
    fd = -1;
    err = 0;
    switch (addrPtr->sa_family) {
        case AF_INET: {
            fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
            if (fd < 0) {
                err = errno;
            }
        } break;
        case AF_INET6:
            //TODO:: give support of ipv6
            assert(NO);
            // fall through
        default: {
            err = EPROTONOSUPPORT;
        } break;
    }
    
    //    ** set time to live time to socket **
    if (self.ttl) {
        u_char ttlForSockOpt = (u_char)self.ttl;
        setsockopt(fd, IPPROTO_IP, IP_TTL, &ttlForSockOpt, sizeof(NSUInteger));
    }
    
    
    if (err != 0) {
        [self didFailWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:err userInfo:nil]];
    } else {
        
        CFSocketContext     context = {0, (__bridge void *)(self), NULL, NULL, NULL};
        CFRunLoopSourceRef  rls;
        
        // Wrap it in a CFSocket and schedule it on the runloop.
        
        self->_socket = CFSocketCreateWithNative(NULL, fd, kCFSocketReadCallBack, SocketReadCallback, &context);
        assert(self->_socket != NULL);
        
        // The socket will now take care of cleaning up our file descriptor.
        
        assert( CFSocketGetSocketFlags(self->_socket) & kCFSocketCloseOnInvalidate );
        fd = -1;
        
        rls = CFSocketCreateRunLoopSource(NULL, self->_socket, 0);
        assert(rls != NULL);
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
        
        CFRelease(rls);
        self.pingDidStartWithAddress ? self.pingDidStartWithAddress(nil, [self getHostname]):nil ;
    }
    assert(fd == -1);
}


- (void)start{
    // If the user supplied us with an address, just start pinging that.  Otherwise
    // start a host resolution.
    
    if (self->_hostAddress != nil) {
        [self startWithHostAddress];
    } else {
        Boolean             success;
        CFHostClientContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
        CFStreamError       streamError;
        
        assert(self->_host == NULL);
        
        self->_host = CFHostCreateWithName(NULL, (__bridge CFStringRef) self.hostName);
        assert(self->_host != NULL);
        
        CFHostSetClient(self->_host, HostResolveCallback, &context);
        
        CFHostScheduleWithRunLoop(self->_host, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        
        success = CFHostStartInfoResolution(self->_host, kCFHostAddresses, &streamError);
        if ( ! success ) {
            [self didFailWithHostStreamError:streamError];
        }
    }
}


- (void)hostResolutionDone
// Called by our CFHost resolution callback (HostResolveCallback) when host
// resolution is complete.  We just latch the first IPv4 address and kick
// off the pinging process.
{
    Boolean     resolved;
    NSArray *   addresses;
    
    // Find the first IPv4 address.
    
    addresses = (__bridge NSArray *) CFHostGetAddressing(self->_host, &resolved);
    if ( resolved && (addresses != nil) ) {
        resolved = false;
        for (NSData * address in addresses) {
            const struct sockaddr * addrPtr;
            
            addrPtr = (const struct sockaddr *) [address bytes];
            if ( [address length] >= sizeof(struct sockaddr) && addrPtr->sa_family == AF_INET) {
                self.hostAddress = address;
                resolved = true;
                break;
            }
        }
    }
    
    // We're done resolving, so shut that down.
    
    [self stopHostResolution];
    
    // If all is OK, start pinging, otherwise shut down the pinger completely.
    
    if (resolved) {
        [self startWithHostAddress];
    } else {
        [self didFailWithError:[NSError errorWithDomain:(NSString *)kCFErrorDomainCFNetwork code:kCFHostErrorHostNotFound userInfo:nil]];
    }
}



- (void)noop
{
}

#pragma mark Ping Fail

- (void)didFailWithError:(NSError *)error{
    
    assert(error != nil);
    
    // We retain ourselves temporarily because it's common for the delegate method
    // to release its last reference to use, which causes -dealloc to be called here.
    // If we then reference self on the return path, things go badly.  I don't think
    // that happens currently, but I've got into the habit of doing this as a
    // defensive measure.
    [self performSelector:@selector(noop) withObject:nil afterDelay:0.0];
    [self stop];
    self.pingDidFailWithError ? self.pingDidFailWithError(error):nil;
}

- (void)didFailWithHostStreamError:(CFStreamError)streamError
// Convert the CFStreamError to an NSError and then call through to
// -didFailWithError: to shut down the pinger object and tell the
// delegate about the error.
{
    NSDictionary *  userInfo;
    NSError *       error;
    
    if (streamError.domain == kCFStreamErrorDomainNetDB) {
        userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSNumber numberWithInteger:streamError.error], kCFGetAddrInfoFailureKey,
                    nil
                    ];
    } else {
        userInfo = nil;
    }
    error = [NSError errorWithDomain:(NSString *)kCFErrorDomainCFNetwork code:kCFHostErrorUnknown userInfo:userInfo];
    assert(error != nil);
    
    [self didFailWithError:error];
}





#pragma mark Ping Send

- (void)sendPing{
    [self sendPingWithData:nil];
}

- (void)sendPingWithData:(NSData *)data{
    
    ZZPingDetails *ping = [[ZZPingDetails alloc]init];
    
    ping.sequenceNumber = self.nextSequenceNumber;
    ping.payloadSize = self.payloadSize;
    ping.ttl = self.ttl;

    int             err;
    NSData *        payload;
    NSMutableData * packet;
    ICMPHeader *    icmpPtr;
    ssize_t         bytesSent;
    
    // Construct the ping packet.
    
    payload = [self payloadWithSize:self.payloadSize];
    packet = [NSMutableData dataWithLength:sizeof(*icmpPtr) + [payload length]];
    assert(sizeof(packet) != self.payloadSize);
    assert(packet != nil);
    
    icmpPtr = [packet mutableBytes];
    icmpPtr->type = kICMPTypeEchoRequest;
    icmpPtr->code = 0;
    icmpPtr->checksum = 0;
    icmpPtr->identifier     = OSSwapHostToBigInt16(self.identifier);
    icmpPtr->sequenceNumber = OSSwapHostToBigInt16(self.nextSequenceNumber);
    memcpy(&icmpPtr[1], [payload bytes], [payload length]);
    
    // The IP checksum returns a 16-bit number that's already in correct byte order
    // (due to wacky 1's complement maths), so we just put it into the packet as a
    // 16-bit unit.
    
    icmpPtr->checksum = in_cksum([packet bytes], [packet length]);
    
    // Send the packet.
    
    if (self->_socket == NULL) {
        bytesSent = -1;
        err = EBADF;
    } else {
        
        [self timeoutProcess];
        ping.sendDate = [NSDate date];

        bytesSent = sendto(
                           CFSocketGetNative(self->_socket),
                           [packet bytes],
                           [packet length],
                           0,
                           (struct sockaddr *) [self.hostAddress bytes],
                           (socklen_t) [self.hostAddress length]
                           );
        err = 0;
        if (bytesSent < 0) {
            err = errno;
        }
    }
    
    // Handle the results of the send.
    
    if ( (bytesSent > 0) && (((NSUInteger) bytesSent) == [packet length]) ) {
        
        // Complete success.  Tell the client.
        
        self.pingDidSendPacket ? self.pingDidSendPacket(ping):nil;
        [self.pings setValue:ping forKey:[@(self.nextSequenceNumber) stringValue]];
    }
    else {
        NSError *   error;
        
        // Some sort of failure.  Tell the client.
        
        if (err == 0) {
            err = ENOBUFS;          // This is not a hugely descriptor error, alas.
        }
        error = [NSError errorWithDomain:NSPOSIXErrorDomain code:err userInfo:nil];
        
        self.pingDidFailToSendPacket ? self.pingDidFailToSendPacket(ping, error):nil;
    }
    
    self.nextSequenceNumber += 1;
}

-(NSData*)payloadWithSize:(NSInteger)size{
    
    NSMutableData* theData = [NSMutableData dataWithCapacity:size];
    for( unsigned int i = 0 ; i < size/4 ; ++i )
    {
        u_int32_t randomBits = arc4random();
        [theData appendBytes:(void*)&randomBits length:4];
    }
    return theData;
}


#pragma mark Timeout 

-(void)timeoutProcess{
    
    dispatch_queue_t timeOutQueue = nil;
    timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, timeOutQueue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, self.timeout* NSEC_PER_SEC), DISPATCH_TIME_FOREVER, 0 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        dispatch_source_cancel(timer);
        [self stop];
        if (self.pingDidFailWithTimeout) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.pingDidFailWithTimeout(nil);
            });
        }
    });
    dispatch_resume(timer);
}


#pragma mark Read Ping Response

- (void)readData

// Called by the socket handling code (SocketReadCallback) to process an ICMP
// messages waiting on the socket.
{
    int                     err;
    struct sockaddr_storage addr;
    socklen_t               addrLen;
    ssize_t                 bytesRead;
    void *                  buffer;
    enum { kBufferSize = 65535 };
    
    // 65535 is the maximum IP packet size, which seems like a reasonable bound
    // here (plus it's what <x-man-page://8/ping> uses).
    
    buffer = malloc(kBufferSize);
    assert(buffer != NULL);
    
    // Actually read the data.
    
    addrLen = sizeof(addr);
    bytesRead = recvfrom(CFSocketGetNative(self->_socket), buffer, kBufferSize, 0, (struct sockaddr *) &addr, &addrLen);
    err = 0;
    if (bytesRead < 0) {
        err = errno;
    }
    
    // Process the data we read.
    
    if (bytesRead > 0) {
        NSMutableData *     packet;
        
        packet = [NSMutableData dataWithBytes:buffer length:(NSUInteger) bytesRead];
        assert(packet != nil);
        
        // We got some data, pass it up to our client.
        __weak typeof(self) weakself = self;
        [self validatePacket:packet :^(BOOL success) {

            const struct ICMPHeader *headerPointer = [[self class] icmpInPacket:packet];
            NSUInteger seqNo = (NSUInteger)OSSwapBigToHostInt16(headerPointer->sequenceNumber);
            NSNumber *key = @(seqNo);
            ZZPingDetails *ping = (ZZPingDetails *)self.pings[[key stringValue]];
            ping.receiveDate = [NSDate date];
            ping.host = [weakself getHostname];
            if (success) {
                weakself.pingDidReceivePingResponsePacket ? weakself.pingDidReceivePingResponsePacket(ping):nil;
            }
            else {
                weakself.pingDidReceiveUnexpectedPacket ? weakself.pingDidReceiveUnexpectedPacket(ping):nil;
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1*NSEC_PER_SEC ), dispatch_get_main_queue(), ^{
                if (weakself.packetCount==weakself.nextSequenceNumber) {
                    weakself.pingSendFinalReport? weakself.pingSendFinalReport([weakself.pings allValues]):nil;
                    [weakself.pings removeAllObjects];
                    [weakself stop];
                }
                else{
                    [weakself sendPing];
                }
            });
        }];
    }
    else {
        // We failed to read the data, so shut everything down.
        err = (err == 0) ? EPIPE :0;
        [self didFailWithError:[NSError errorWithDomain:NSPOSIXErrorDomain code:err userInfo:nil]];
    }
    free(buffer);
    // Note that we don't loop back trying to read more data.  Rather, we just
    // let CFSocket call us again.
}

-(NSString*)getHostname{
    const struct sockaddr * soc = (const struct sockaddr *) [self.hostAddress bytes];
    struct sockaddr_in *socket = (struct sockaddr_in *) soc;
    return [NSString stringWithFormat:@"%s",inet_ntoa(socket->sin_addr)];
}

- (void)validatePacket:(NSMutableData *)packet :(void(^)(BOOL success))success{
    BOOL                result;
    NSUInteger          icmpHeaderOffset;
    ICMPHeader *        icmpPtr;
    uint16_t            receivedChecksum;
    uint16_t            calculatedChecksum;
    
    result = NO;
    
    icmpHeaderOffset = [[self class] icmpHeaderOffsetInPacket:packet];
    if (icmpHeaderOffset != NSNotFound) {
        icmpPtr = (struct ICMPHeader *) (((uint8_t *)[packet mutableBytes]) + icmpHeaderOffset);
        
        receivedChecksum   = icmpPtr->checksum;
        icmpPtr->checksum  = 0;
        calculatedChecksum = in_cksum(icmpPtr, [packet length] - icmpHeaderOffset);
        icmpPtr->checksum  = receivedChecksum;
        
        if (receivedChecksum == calculatedChecksum) {
            if ( (icmpPtr->type == kICMPTypeEchoReply) && (icmpPtr->code == 0) ) {
                if ( OSSwapBigToHostInt16(icmpPtr->identifier) == self.identifier ) {
                    if ( OSSwapBigToHostInt16(icmpPtr->sequenceNumber) < self.nextSequenceNumber ) {
                        result = YES;
                    }
                }
            }
        }
    }
    success ? success(result): nil;
}

#pragma mark Stop Ping

- (void)stopHostResolution
// Shut down the CFHost.
{
    if (self->_host != NULL) {
        CFHostSetClient(self->_host, NULL, NULL);
        CFHostUnscheduleFromRunLoop(self->_host, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        CFRelease(self->_host);
        self->_host = NULL;
    }
}

- (void)stopDataTransfer
// Shut down anything to do with sending and receiving pings.
{
    if (self->_socket != NULL) {
        CFSocketInvalidate(self->_socket);
        CFRelease(self->_socket);
        self->_socket = NULL;
    }
}

- (void)stop
// See comment in header.
{
    [self stopHostResolution];
    [self stopDataTransfer];
    
    // If we were started with a host name, junk the host address on stop.  If the
    // client calls -start again, we'll re-resolve the host name.
    
    if (self.hostName != nil) {
        self.hostAddress = NULL;
    }
    
    _pingDidStartWithAddress = nil;
    _pingDidFailWithError = nil;
    _pingDidSendPacket = nil;
    _pingDidFailToSendPacket = nil;
    _pingDidReceivePingResponsePacket = nil;
    _pingDidReceiveUnexpectedPacket = nil;
    _pingDidFailWithTimeout = nil;
    _pingSendFinalReport = nil;
    _hostName = nil;
    _hostAddress = nil;
    _pings = nil;

}

@end
