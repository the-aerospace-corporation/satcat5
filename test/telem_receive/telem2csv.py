# -*- coding: utf-8 -*-

# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

'''
Telem2csv takes a wireshark (pcap) file and a yaml cfg file to generate a csv file for a particular
telemetry type.  The yaml cfg file allows user to specify how to filter out the packets and which
fields in the telemetry data to save into the output csv file.


Invocation of this command requires user to specify both the pcap file and the configuration file.
Specification of the output file name is optional and defaults to 'output_telem.csv'.

ex: python telem2csv.py --Capfile example_cap_100k.pcapng --Cfgfile example_traffic_and_mactbl.yaml --csvfile output_telem_portcnt.csv
'''
import argparse
import csv
import yaml
import cbor2
import pyshark

# this funcion squashes a multi-level dictionary to a single-level dictionary
def squash_dict (data, rootname='', num=''):
    flat_dict = {}
    for k in list(data.keys()):
        fieldname = k
        if (isinstance(data[k], list) and isinstance(data[k][0], dict)):
            cnt = 0
            for i in data[k]:
                flat_dict.update(squash_dict(i, k, cnt))
                cnt = cnt + 1
        else:
            if (rootname or num):
                flat_dict[rootname+str(num)+'_'+k] = data[k]
            else:
                flat_dict[k] = data[k]
    return flat_dict


#####################################################
if __name__ == "__main__":

    # Parse command
    parser = argparse.ArgumentParser(
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument('--Capfile',
                        required=True,
                        type=str,
                        help='specifies name of PCAP (wireshark) file')
    parser.add_argument('--Cfgfile',
                        required=True,
                        type=str,
                        help='specifies name of yaml config file')
    parser.add_argument('--csvfile',
                        default='output_telem.csv',
                        required=False,
                        type=str,
                        help='specifies name of output csv file')
    args = parser.parse_args()

    # load configuration file
    with open(args.Cfgfile, 'r') as s:
        cfg = yaml.load(s, yaml.SafeLoader)

    # load pcap file
    cap = pyshark.FileCapture (args.Capfile)
    cap.load_packets()
    cap.reset()

    # filter packets according to yaml pkt_filters parameters
    log_pkts = []

    # assemble filter search string from yaml parameters
    cmd = "True"
    for i in cfg['pkt_filters']['pkt_fields']:
        if (cfg['pkt_filters']['pkt_fields'][i] != None):
            cmd = cmd + ' and pkt.' + str(i) + ' == ' + cfg['pkt_filters']['pkt_fields'][i]

    # apply search string to filter out packets
    for i in range(len(cap)):
        pkt = cap.next_packet()
        pkt_layer = [x.layer_name.lower() for x in pkt.layers]
        if set(cfg['pkt_filters']['pkt_layers']).issubset(set(pkt_layer)):
            if eval(cmd):
                log_pkts.append(pkt)

    # Find all packets with specific cbor field
    sel_pkts = []
    for i in range(len(log_pkts)):
        data = log_pkts[i].data.data.binary_value
        decoded_message = cbor2.loads(data)
        if cfg['pkt_filters']['cbor_field'] in decoded_message:
            sel_pkts.append({'pkt' : log_pkts[i], 'msg': decoded_message, 'flat_msg' : squash_dict(decoded_message) })

    # If Fields are specified, compile flattened field names matching requested field names
    # Otherwise, use all fields in cbor message
    csv_fields = {"timestamp"}

    if cfg['fields']['cbor'] != None:
        for p in sel_pkts:
            sq = p['flat_msg']
            for f in cfg['fields']['cbor']:
                csv_fields.update({x for x in sq if f in x})
    else:
        for p in sel_pkts:
            sq = p['flat_msg']
            csv_fields.update(set(sq.keys()))

    # Open new csv file and write out data
    csvfile     = open (args.csvfile, 'w', newline='')
    csvwriter   = csv.DictWriter(csvfile, fieldnames = csv_fields)

    csvwriter.writeheader()

    csv_row = dict()
    for p in sel_pkts:
        for f in csv_fields:
            if f in p['flat_msg']:
                csv_row[f] = p['flat_msg'][f]
            elif f == 'timestamp':
                csv_row[f] = p['pkt'].sniff_time
            else:
                csv_row[f] = None
        csvwriter.writerow(csv_row)

    csvfile.close()

