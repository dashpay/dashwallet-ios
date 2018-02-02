#!/usr/bin/python
# -*- coding: UTF-8 -*-

##
##  Compatible with Python >= 2.6, < 3.*
##
##
##  Created by Andrew Podkovyrin, 2018
##  Copyright © 2018 Dash Foundation. All rights reserved.
##
##  Permission is hereby granted, free of charge, to any person obtaining a copy
##  of this software and associated documentation files (the "Software"), to deal
##  in the Software without restriction, including without limitation the rights
##  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
##  copies of the Software, and to permit persons to whom the Software is
##  furnished to do so, subject to the following conditions:
##
##  The above copyright notice and this permission notice shall be included in
##  all copies or substantial portions of the Software.
##
##  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
##  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
##  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
##  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
##  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
##  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
##  THE SOFTWARE.
##


import os
import urllib2
import json
import plistlib
import socket
import struct
import sqlite3

# configuration
PLIST_PATH = '../DashWallet/FixedPeers.plist'
API_HTTP_URL = 'https://www.dashninja.pl/data/masternodeslistfull-0.json'
LOCAL_MASTERNODES_FILE = 'masternodeslistfull-0.json'
SOCKET_CONNECTION_TIMEOUT = 3
MASTERNODE_DEFAULT_PORT = 9999
MASTERNODE_MIN_PROTOCOL = 70208
FIXED_PEERS_COUNT = 100

# global in-memory database
CONNECTION = sqlite3.connect(":memory:")
CONNECTION.executescript("""
CREATE TABLE masternodes (ip TEXT,
                          port INTEGER,
                          portcheck BOOLEAN,
                          countrycode TEXT,
                          activeseconds INTEGER, 
                          protocol INTEGER
                          );

CREATE INDEX index_ip on masternodes (ip);
CREATE INDEX index_port on masternodes (port);
""")


def int2ip(int_ip):
    return socket.inet_ntoa(struct.pack("!I", int_ip))


def ip2int(str_ip):
    return struct.unpack("!I", socket.inet_aton(str_ip))[0]


def import_all_masternodes():

    def load_all_masternodes_from_api():
        req = urllib2.Request(API_HTTP_URL)
        try:
            resp = urllib2.urlopen(req, timeout=30)
            resp_json_str = resp.read()

            json_response = json.loads(resp_json_str)
            return json_response

        except urllib2.HTTPError as e:
            print e.read()
            return None

    def load_all_masternodes_from_file():
        json_response = None
        with open(LOCAL_MASTERNODES_FILE) as data_file:
            json_response = json.loads(data_file.read())
        return json_response

    def fill_database(json_response):
        status = json_response['status']
        if status != 'OK':
            print 'Invalid json, status =', status
            return

        masternodes_raw = json_response['data']['masternodes']
        masternodes = []
        for mn in masternodes_raw:
            ip = mn['MasternodeIP']
            port = mn['MasternodePort']
            portcheck = True if mn['Portcheck']['Result'] == 'open' else False
            countrycode = mn['Portcheck']['CountryCode']
            activeseconds = mn['MasternodeActiveSeconds']
            protocol = mn['MasternodeProtocol']

            masternodes.append((ip, port, portcheck, countrycode, activeseconds, protocol))

        CONNECTION.executemany('INSERT INTO masternodes (ip, port, portcheck, countrycode, activeseconds, protocol) '
                               'VALUES (?, ?, ?, ?, ?, ?)', masternodes)
        CONNECTION.commit()

    json_response = None
    if os.path.isfile(LOCAL_MASTERNODES_FILE):
        print 'Loading masternodes list from local file...',
        json_response = load_all_masternodes_from_file()
    else:
        print 'Loading masternodes list from remote API...',
        json_response = load_all_masternodes_from_api()

    if json_response is not None:
        print 'Done'
        print 'Importing masternodes list...',
        fill_database(json_response)
        print 'Done'
    else:
        print 'Failed to load masternodes list'


def get_best_masternodes(count, exceptlist=None):
    if count <= 0:
        return []

    # filter best masternodes from all (alive, with max active time, with desired port and protocol)
    # group them by country and pick some
    query = 'SELECT ip, countrycode FROM masternodes' \
            ' WHERE port = {} AND portcheck = 1 AND countrycode != "__" AND protocol >= {}' \
            ' ORDER BY activeseconds DESC'.format(MASTERNODE_DEFAULT_PORT, MASTERNODE_MIN_PROTOCOL)
    cursor = CONNECTION.cursor()
    cursor.execute(query)
    filtered_masternodes = cursor.fetchall()
    ips_by_countrycode = {}
    for mn in filtered_masternodes:
        ip = mn[0]
        countrycode = mn[1]
        if exceptlist and ip in exceptlist:
            continue

        ips = None
        if countrycode in ips_by_countrycode:
            ips = ips_by_countrycode[countrycode]
        else:
            ips = []
            ips_by_countrycode[countrycode] = ips
        ips.append(ip)

    # sort by countries with maximum amount of masternodes
    max_countrycodes = sorted(ips_by_countrycode, key=lambda k: len(ips_by_countrycode[k]), reverse=True)

    result = []
    while len(result) < count:
        for countrycode in max_countrycodes:
            if countrycode not in ips_by_countrycode:
                continue

            ips = ips_by_countrycode[countrycode]
            if ips:
                ip = ips.pop(0)
                result.append(ip)
            else:
                del ips_by_countrycode[countrycode]

            if len(result) == count:
                break

        if len(ips_by_countrycode) == 0:
            break
    
    return result


def validated_ips_from_fixed_plist():

    def is_socket_alive(ip, port):
        sock = None

        try:
            address = (ip, port)
            sock = socket.create_connection(address, timeout=SOCKET_CONNECTION_TIMEOUT)
        except socket.error as msg:
            # print 'Failed to connect', address, msg
            pass

        if sock is not None:
            sock.close()
            return True
        else:
            return False

    plist_values = plistlib.readPlist(PLIST_PATH)
    fixed_ips = map(lambda i: int2ip(i), plist_values)

    result = []
    for ip in fixed_ips:
        print 'Validating', ip,

        cursor = CONNECTION.cursor()
        cursor.execute('SELECT portcheck FROM masternodes WHERE ip = ?', (ip,))
        mn = cursor.fetchone()

        if mn and mn[0]:
            print '... OK ✅'
            result.append(ip)
        else:
            alive = is_socket_alive(ip, MASTERNODE_DEFAULT_PORT)
            if alive:
                print '... OK ✅'
                result.append(ip)
            else:
                print '... Failed ❌'

    print 'Validation done. Passed:', len(result), 'Failed:', len(fixed_ips) - len(result)

    return result


def main():
    import_all_masternodes()

    validated_fixed = validated_ips_from_fixed_plist()
    leftcount = FIXED_PEERS_COUNT - len(validated_fixed)
    best_masternodes = get_best_masternodes(leftcount, validated_fixed)
    print 'Appending best matched masternodes:', len(best_masternodes)

    result = validated_fixed + best_masternodes
    result_int = map(lambda s: ip2int(s), result)

    plistlib.writePlist(result_int, PLIST_PATH)

    print PLIST_PATH, 'updated 🎉'


if __name__ == '__main__':
    main()
