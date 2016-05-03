//
//  BreadWalletUITests-Bridging-Header.h
//  BreadWallet
//
//  Created by Aaron Voisine on 5/3/16.
//  Copyright © 2016 Aaron Voisine. All rights reserved.
//

#ifndef BreadWalletUITests_Bridging_Header_h
#define BreadWalletUITests_Bridging_Header_h

#include "BreadWallet-Prefix.pch"

#if SNAPSHOT
static const bool _SNAPSHOT = 1;
#else
static const bool _SNAPSHOT = 0;
#endif

#endif /* BreadWalletUITests_Bridging_Header_h */
