//
//  PQAIPerfHeader.h
//  ZZPings
//
//  Created by Avinash Tag on 16/01/18.
//  Copyright © 2018 Avinash Tag. All rights reserved.
//

#ifndef PQAIPerfHeader_h
#define PQAIPerfHeader_h

#include "iperf_config.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include <errno.h>
#include <signal.h>
#include <unistd.h>
#ifdef HAVE_STDINT_H
#include <stdint.h>
#endif
#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#ifdef HAVE_STDINT_H
#include <stdint.h>
#endif
#include <netinet/tcp.h>

#include "iperf.h"
#include "iperf_api.h"
#include "units.h"
#include "iperf_locale.h"
#include "net.h"

#endif /* PQAIPerfHeader_h */
