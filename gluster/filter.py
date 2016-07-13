#!/usr/bin/env python3

#author: Jan Wrona, wrona@cesnet.cz

# Copyright (C) 2015 CESNET
#
# LICENSE TERMS
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in
#    the documentation and/or other materials provided with the
#    distribution.
# 3. Neither the name of the Company nor the names of its contributors
#    may be used to endorse or promote products derived from this
#    software without specific prior written permission.
#
# ALTERNATIVELY, provided that this notice is retained in full, this
# product may be distributed under the terms of the GNU General Public
# License (GPL) version 2 or later, in which case the provisions
# of the GPL apply INSTEAD OF those given above.
#
# This software is provided ``as is'', and any express or implied
# warranties, including, but not limited to, the implied warranties of
# merchantability and fitness for a particular purpose are disclaimed.
# In no event shall the company or contributors be liable for any
# direct, indirect, incidental, special, exemplary, or consequential
# damages (including, but not limited to, procurement of substitute
# goods or services; loss of use, data, or profits; or business
# interruption) however caused and on any theory of liability, whether
# in contract, strict liability, or tort (including negligence or
# otherwise) arising in any way out of the use of this software, even
# if advised of the possibility of such damage.


import sys, socket

def fsm(key, value):
    global volfile_dict
    global in_volume

    if key == 'volume':
        volfile_dict[value] = {}
        in_volume = value
    elif in_volume:
        if key == 'end-volume':
            in_volume = None
        elif key == 'type':
            volfile_dict[in_volume][key] = value
        elif key == 'option':
            opt_tupple = tuple(value.split(None, 1))
            volfile_dict[in_volume].setdefault(key, []).append(opt_tupple)
        elif key == 'subvolumes':
            volfile_dict[in_volume][key] = value.split()
    else:
        print('invalid volume file')
        exit(1)

####################################################################################################
if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('bad argument count')
        exit(1)


with open(sys.argv[1]) as f:
    volfile = f.read()


volfile_dict = {}
in_volume = None
for line in volfile.splitlines():
    splitted = line.split(None, 1)
    if len(splitted) == 0:
        continue
    elif len(splitted) == 1:
        value = None
    else:
        value = splitted[1]
    key = splitted[0]
    fsm(key, value)


volume_dht = None
for key, value in volfile_dict.items():
    if value['type'] == 'cluster/nufa':
        volume_dht = value

if not volume_dht:
    exit(0)

local_subvolume_dht = None
#loop through all distribute (NUFA) subvolumes:
for subvolume_dht in volume_dht['subvolumes']:
    #find first replication subovlume, thats where we want to store our data
    subvolume_replicate_first = volfile_dict[subvolume_dht]['subvolumes'][0]
    #loop trhough all its options and chech if it is local brick
    for key, value in volfile_dict[subvolume_replicate_first]['option']:
        if key == 'remote-host' and value == socket.gethostname():
            local_subvolume_dht = subvolume_dht

if not local_subvolume_dht:
    exit(0)

with open(sys.argv[1], 'w') as f:
    for line in volfile.splitlines(True):
        f.write(line)
        if 'nufa' in line:
            f.write('    option local-volume-name {}\n'.format(local_subvolume_dht))
