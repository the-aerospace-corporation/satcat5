# -*- coding: utf-8 -*-

# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

'''
This unit test file is run using pytest.
ex: pytest test_telem_receive.py
If printing is also desired, use the -s modifer after pytest
If verbosity is desired, use the -v modifier
'''

import csv
import socket
import threading
import time

import cbor2
import pandas as pd
import pytest
from ptp_telem import TelemReceive
from ptp_telem import squash_dict

def test_telem_recieve():
    """Tests setup of telem_receive, sending packets and writing to csv"""
    udp_IP='127.0.0.1'
    udp_port=5556
    
    telem_receive = TelemReceive(udp_IP=udp_IP, udp_port=udp_port, output_file_name="test_output_telem")
    
    thread = threading.Thread(target=telem_receive.read_from_socket)
    thread.start()
    telem_receive.toggle_printing()
    time.sleep(1)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
      
    data1 = {
        "col0": "value1",
        "col1": "value2",
        
    }
    encoded_data1 = cbor2.dumps(data1)
    
    sock.sendto(encoded_data1, (udp_IP, udp_port))
    time.sleep(.1)
    data2 = {
        "col0": "value3",
        "col1": "value4",
        }
    
    encoded_data2 = cbor2.dumps(data2)
    
    sock.sendto(encoded_data2, (udp_IP, udp_port))
    time.sleep(0.1)
    telem_receive.close()
    time.sleep(1)
    thread.join()
    sock.close()
    time.sleep(2)
    
    with open('test_output_telem_0.csv', 'r') as f:
        lines = f.readlines()
        assert len(lines) == 3
        assert 'col0' in lines[0]
        assert 'col1' in lines[0]
        assert 'value1' in lines[1]
        assert 'value2' in lines[1]
    
        assert 'value3' in lines[2]
        assert 'value4' in lines[2]

def test_cbor_telem():
    """Tests sending 50 rows of CBOR encoded data to the UDP socket and then checks to ensure they are equal"""
    udp_IP='127.0.0.1'
    udp_port=5556
    
    telem_receive = TelemReceive(udp_IP=udp_IP, udp_port=udp_port, output_file_name="test_output_cbor")
    
    thread = threading.Thread(target=telem_receive.read_from_socket)
    thread.start()
    telem_receive.toggle_printing()
    time.sleep(1)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    truth_data0 = []
    truth_data1 = []
    for idx in range(50):
        data = {
            "mean_path_delay":      1.0 + idx * .01,
            "offset_from_master":   2.0 + idx * .01,
            "t1_secs":              3.0 + idx * .01,
            "t1_subns":             4.0 + idx * .01,
            "t2_secs":              5.0 + idx * .01,
            "t2_subns":             6.0 + idx * .01,
            "t3_secs":              7.0 + idx * .01,
            "t3_subns":             7.0 + idx * .01,
            "t4_secs":              8.0 + idx * .01,
            "t4_subns":             9.0 + idx * .01,
        }
        encoded_data = cbor2.dumps(data)
        truth_data0.append(data)
        sock.sendto(encoded_data, (udp_IP, udp_port))
        time.sleep(0.1)

        data = {
            "frm_cnt":           1 + idx * 1,
            "ingress_err_cnt":   2 + idx * 2,
            "egress_err_cnt":    3 + idx * 3,
            "sgmii_err_cnt":     4 + idx * 4,
            "fifo_err_cnt":      5 + idx * 5,
        }
        encoded_data = cbor2.dumps(data)
        truth_data1.append(data)
        sock.sendto(encoded_data, (udp_IP, udp_port))
        time.sleep(0.1)

    telem_receive.close()
    thread.join()
    sock.close()
    
    truth0_df = pd.DataFrame(truth_data0)
    output0_df = pd.read_csv('test_output_cbor_0.csv')
    truth1_df = pd.DataFrame(truth_data1)
    output1_df = pd.read_csv('test_output_cbor_1.csv')
    
    # asserts the two df are equal
    pd.testing.assert_frame_equal(output0_df, truth0_df)
    pd.testing.assert_frame_equal(output1_df, truth1_df)

def test_cbor_heir():
    """Tests heirarchical CBR messages"""
    udp_IP='127.0.0.1'
    udp_port=5556

    telem_receive = TelemReceive(udp_IP=udp_IP, udp_port=udp_port, output_file_name="test_output_cborheir")

    thread = threading.Thread(target=telem_receive.read_from_socket)
    thread.start()
    telem_receive.toggle_printing()
    time.sleep(1)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    truth_data0 = []
    for idx in range(50):
        port_data_list = []
        for portnum in range(5):
            port_data = {
                'rxb' : portnum+ idx *1,
                'rxf' : portnum+ idx *2,
                'txb' : portnum+ idx *3,
                'txf' : portnum+ idx *4
            }
            port_data_list.append(port_data)

        telem_data = {
            'total_packet' : idx,
            'port_stats'   : port_data_list
        }

        encoded_data = cbor2.dumps(telem_data)
        truth_data0.append(squash_dict(telem_data))
        sock.sendto(encoded_data, (udp_IP, udp_port))
        time.sleep(0.1)

    telem_receive.close()
    thread.join()
    sock.close()

    truth0_df = pd.DataFrame(truth_data0)
    output0_df = pd.read_csv('test_output_cborheir_0.csv')

    # asserts the two df are equal
    pd.testing.assert_frame_equal(output0_df, truth0_df)

