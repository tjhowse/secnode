'''
Secnode server.

This server accepts TCP connections from a remote device and decrypts them.

by Travis Howse <tjhowse@gmail.com>
2012.   License, GPL v2 or later

'''

from Crypto.Cipher import AES

import SocketServer
import sys
import time
import socket
import threading
import sqlite3

queue = []
xmitslot = 500 #milliseconds

def toHex(s):
	lst = []
	for ch in s:
		hv = hex(ord(ch)).replace('0x', '')
		if len(hv) == 1:
			hv = '0'+hv
		lst.append(hv)
	
	return reduce(lambda x,y:x+y, lst)


class ThreadedTCPRequestHandler(SocketServer.BaseRequestHandler):

	def handle(self):
		data = self.request.recv(16)
		while data != '':
			cur_thread = threading.current_thread()
			if (sys.getsizeof(data) == 37):
				obj2 = AES.new('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', AES.MODE_ECB)
				raw = obj2.decrypt(data)
				decrypted = list(raw)
				decrypted = "".join(decrypted)			
				
				print toHex(decrypted)
				if check_checksum(raw):
					#bytearray(raw)[5] = 0xBB
					self.request.sendall(obj2.encrypt(raw))
					#self.request.sendall(obj2.encrypt(list(decrypted)))
				else:
					print "Hark! A checksum failed!"
				
			else:
				print "Lost a message! Very bad!"
			data = self.request.recv(16)
	
			
		#response = "{}: {}".format(cur_thread.name, data)
		#self.request.sendall(response)

def append_checksum(message);
	parity = 0
	for byte in bytearray(message):
		parity = parity ^ byte
	
		
def check_checksum(message):
	parity = 0
	for byte in bytearray(message):
		parity = parity ^ byte
	if parity == 0:
		return True
	return False
		
class ThreadedTCPServer(SocketServer.ThreadingMixIn, SocketServer.TCPServer):
	pass
	
	
def init_sqldb(db):
	db.execute('CREATE TABLE IF NOT EXISTS nodes (id real, tag text, description text, cryptkey text, ip text, status text, zone text)')
	db.execute('CREATE TABLE IF NOT EXISTS msgqueue (id real, message text)')
	
	db.execute('INSERT INTO nodes VALUES (1, "TEST", "TEST NODE", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "192.168.1.177", "FINE, I GUESS.", "OUTSIDE")')
	
	db.commit()
	# TODO Load a nodes list from a CSV file, populate the nodes DB.
	
def enqueue_message(node_id, message):
	global sqldb
	
	t = (node_id, message)
	
	sqldb.execute('INSERT INTO msgqueue VALUES (?,?)',t)
	
if __name__ == "__main__":
	HOST, PORT = "192.168.1.151", 5555

	server = ThreadedTCPServer((HOST, PORT), ThreadedTCPRequestHandler)
	ip, port = server.server_address

	# Start a thread with the server -- that thread will then start one
	# more thread for each request
	server_thread = threading.Thread(target=server.serve_forever)
	# Exit the server thread when the main thread terminates
	server_thread.daemon = True
	server_thread.start()
	
	# TODO: Initialise SQL database
	sqldb = sqlite3.connect('secnode.db')
	init_sqldb(sqldb)
	
	while 1:
		time.sleep(1)
		enqueue_message(1, "111111")
		

	
