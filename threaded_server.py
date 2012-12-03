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
		self.request.settimeout(5)
		data = self.request.recv(16)
		while data != '':
			if (sys.getsizeof(data) == 37):
				obj2 = AES.new('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', AES.MODE_ECB)
				raw = obj2.decrypt(''.join(data))
				
				# TODO parse message, update database with statuses from node
				#print toHex(decrypted)
				#for c in message:
				#	c = c+0.00
				#	print c.hex()
				
				if check_checksum(raw):
					
					decrypted = list(raw)
					#print "In: "
					print toHex(decrypted)
					'''decrypted[0] = '\x00'
					decrypted[1] = '\x63'
					decrypted[2] = '\x03'
					decrypted[3] = '\x20'
					decrypted[4] = '\x0F'
					decrypted[5] = '\x00'
					decrypted[6] = '\x00'
					decrypted[7] = '\x00'
					decrypted[8] = '\x00'
					decrypted[9] = '\x00'
					decrypted[10] = '\x00'
					decrypted[11] = '\x00'
					decrypted[12] = '\x00'
					decrypted[13] = '\x00'
					decrypted[14] = '\x3a'
					decrypted[15] = '\x85'
					print "Out: "
					print toHex(decrypted)'''
					#parse_message(decrypted)
					decrypted = "".join(decrypted)					
					append_checksum(decrypted)
					
					#bytearray(raw)[5] = 0xBB
					# TODO Read from msgqueue and send off a message relevant to this node
					self.request.sendall(obj2.encrypt(decrypted))

				else:
					print "Hark! A checksum failed!"
				
			else:
				print "Lost a message! Very bad!"
			data = self.request.recv(16)
			
		#response = "{}: {}".format(cur_thread.name, data)
		#self.request.sendall(response)
		
	
def parse_message(message):
	for i in range(2,4):
		#print toHex(message[i])
		print "High: ",get_high(bytearray(message[i]))
		print "Low : ",get_low(bytearray(message[i]))
		

def get_high(byte):
	print type(byte)
	return byte>>4
	
def get_low(byte):
	return byte[0]&0x0F
		
def check_checksum(message):
	parity = 0
	for byte in bytearray(message):
		parity = parity ^ byte
	if parity == 0:
		return True
	return False

def append_checksum(message):
	message = bytearray(message)
	message.pop()
	parity = 0
	for byte in message:
		parity = parity ^ byte
	message.append(parity)
	return message
	
class ThreadedTCPServer(SocketServer.ThreadingMixIn, SocketServer.TCPServer):
	pass
	
	
def init_sqldb(db):
	db.execute('CREATE TABLE IF NOT EXISTS nodes (nodeid real, tag text, description text, cryptkey text, ip text, status text, zone text)')
	db.execute('CREATE TABLE IF NOT EXISTS msgqueue (msgid INTEGER PRIMARY KEY, nodeid real, message text)')
	db.execute('CREATE TABLE IF NOT EXISTS nodestatus (nodeid real, var real, state real)')
	db.execute('CREATE TABLE IF NOT EXISTS pinstate (nodeid real, pin real, state real, duration real)')
	
	db.execute('INSERT INTO nodes VALUES (1, "TEST", "TEST NODE", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "192.168.1.177", "FINE, I GUESS.", "OUTSIDE")')
	
	db.commit()
	# TODO Load a nodes list from a CSV file, populate the nodes DB.
	
def enqueue_message(node_id, message):
	global sqldb	
	t = (node_id, message)	
	sqldb.execute('INSERT INTO msgqueue VALUES (NULL,?,?)',t)
	sqldb.commit()
	
if __name__ == "__main__":
	HOST, PORT = "192.168.1.100", 5555

	server = ThreadedTCPServer((HOST, PORT), ThreadedTCPRequestHandler)
	#server.socket.settimeout(0)
	ip, port = server.server_address

	# Start a thread with the server -- that thread will then start one
	# more thread for each request
	server_thread = threading.Thread(target=server.serve_forever)
	# Exit the server thread when the main thread terminates
	server_thread.daemon = True
	server_thread.start()
	
	sqldb = sqlite3.connect('secnode.db')
	init_sqldb(sqldb)
	
	while 1:
		time.sleep(1)
		enqueue_message(1, "111111")
		

	
