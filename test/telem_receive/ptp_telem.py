# -*- coding: utf-8 -*-

# Copyright 2024 The Aerospace Corporation.
# This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.

'''
TelemReceive receives CBOR data out of a UDP socket. Each CBOR data packet is parsed to determine
its telemetry type and a csv file is generated for each telemetry type.

To run this program from the command line, it needs a command line argument 
of the csv output file name. This output file will appear in the same 
directory as the telem_receive.py file.
ex: Python telem_receive.py test.csv
'''

import argparse
import csv
import pprint
import socket
import threading
import time

import cbor2


class TelemReceive():
    def __init__(self, udp_IP='', udp_port=0x5A63, output_file_name='telem_data'):
        """Constructor for TelemRecieve
        A csv file is created for each telemetry type received from the input port.
        A telemetry type is uniquely defined by the fields in its message.

        Parameters
        ----------
        udp_IP : str, optional
            IP address of the UDP socket, by default '' (to capture broadcast packets)
        udp_port : int, optional
            port of the UDP socket, by default 5555
        output_file_name : str, optional
            Root file name for the output of the socket to be read into, by default 'telem_data'
        """
        # create UDP docket. AF_INET corresponds with IPv4 and SOCK_DGRAM corresponds with UDP
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.server_address = (udp_IP, udp_port)
        self.sock.bind(self.server_address)
        
        # socket timesout after 1 second
        self.sock.settimeout(1)
        
        # thread safe boolean
        self.running = threading.Event()
        self.running.set()

        # variables
        self.output_file_name = output_file_name
        self.fnum = 0
        self.row_count = 0
        
        # allows for graceful stopping
        self.stopped_loop = False
        
        # sets command line printing verbosity level (0, 1, 2)
        self.printing = False
        self.pp = pprint.PrettyPrinter(indent=0)

        # dictionary to keep association between telemetry type and its associated
        # (file, csv writer) tuple
        self.writers_dict = {}

    def read_from_socket(self):
        """ Reads from the open socket and prints to the csv noted in the filename
        """
            
        while self.running.is_set():
            try:
                if self.printing: print('\nWaiting to receive message')

                # receives data from socket
                data, address = self.sock.recvfrom(1500) # Matches ptp_telemetry.cc buffer length
                    
                # decodes cbor message
                decoded_message = cbor2.loads(data)
                if self.printing: print(f'recieved {len(decoded_message)} bytes from {address}')
                if self.printing: self.pp.pprint(decoded_message)

                # list of fieldnames define telemetry type
                # hash the fieldnames list to generate unique key for each telemetry type
                flattened_message = squash_dict (decoded_message)
                fieldnames = list(flattened_message.keys())
                hash_fieldnames = hash(str(fieldnames))

                # if hash_fieldnames not in part of writers_dict
                #   - open a new file
                #   - create a new csvwriter
                #   - associate file and csvwriter to new message type
                if not(hash_fieldnames in self.writers_dict):
                    csvfilename  = self.output_file_name + '_' + str(self.fnum) + '.csv'
                    csvfile   = open(csvfilename, 'w', newline='')
                    csvwriter = csv.DictWriter(csvfile, fieldnames = fieldnames)
                    csvwriter.writeheader()
                    self.writers_dict[hash_fieldnames] = (csvfile, csvwriter)
                    self.fnum = self.fnum + 1

                # write telemetry data to approriate csv file based on telemetry type
                self.writers_dict[hash_fieldnames][1].writerow(flattened_message)
                self.row_count = self.row_count + 1

            # if the socket timesout, break go into the next iteration of the loop
            except socket.timeout:
                continue

        # indicates that the loop has been broken
        self.stopped_loop = True
                
                
    def close(self):
        """Closes out the socket and stops the loop
        """
        self.running.clear()
        if self.printing: print("closing socket")
        if self.printing: print(f"files printed to {self.output_file_name}: {self.fnum}")
        if self.printing: print(f"rows printed to {self.row_count}")

        # wait for end of loop
        while not self.stopped_loop: time.sleep(0.1)

        # clean up socket and close files
        for key in self.writers_dict: self.writers_dict[key][0].close()
        self.sock.close()
        if self.printing: print("socket closed")

    
    def toggle_printing(self):
        """Toggles the printing boolean. Allows for commandline changes
        """
        self.printing = not self.printing


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


###############################
### Command line executable ###
###############################

def main(ipaddress, portnum, output_file_name):
    telem_reciever = TelemReceive(udp_IP=ipaddress, udp_port=portnum, output_file_name=output_file_name)
    thread = threading.Thread(target=telem_reciever.read_from_socket)
    thread.start()
    
    command_message = "Press 'q' at any time to quit program, p to toggle printing to the command line: "
    try:
        while True:
            command = input(command_message)
            if command == 'q':
                break
            if command == 'p':
                telem_reciever.toggle_printing()
    except KeyboardInterrupt:
        pass
    finally: 
        print("Stopping...")
        telem_reciever.close()
        thread.join()
        print("Stopped.")  


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Telemetry Reciever",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("output_file_name", type=str, help="Output file name")
    parser.add_argument('--ipaddr',
                        default  ='',
                        required = False,
                        type     = str,
                        help     = "IP address of transmitting node")
    parser.add_argument('--portnum',
                        default   = 0x5A63,
                        required  = False,
                        type      = int,
                        help      = "Port number of telemetry packets")

    args = parser.parse_args()
    main(args.ipaddr, args.portnum, args.output_file_name)
