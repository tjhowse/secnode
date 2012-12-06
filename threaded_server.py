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
import array
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
		mysqldb = sqlite3.connect('secnode.db',timeout=10)
		#global sqldb
		#mysqldb = sqldb
		self.request.settimeout(5)
		data = self.request.recv(16)
		while data != '':
			if (sys.getsizeof(data) == 37):
				nodeID = get_nodeID(mysqldb,self.client_address[0])
				if nodeID == 0:
					print "Bad node ID"
					return
				obj2 = AES.new(get_cryptokey(mysqldb, nodeID), AES.MODE_ECB)
				decrypted = list(obj2.decrypt(''.join(data)))
				
				if check_checksum(decrypted):

					#print toHex(decrypted)
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
					parse_message(mysqldb, nodeID, decrypted)
					
					decrypted[5] = '\xF0'
					# TODO Read from msgqueue and send off a message relevant to this node
					
					decrypted = build_reply(mysqldb, nodeID)
					
					decrypted = append_checksum(decrypted)
					self.request.sendall(obj2.encrypt(decrypted))

				else:
					print "Hark! A checksum failed!"
				
			else:
				print "Lost a message! Very bad!"
			data = self.request.recv(16)
			
		#response = "{}: {}".format(cur_thread.name, data)
		#self.request.sendall(response)
		
def build_reply(mysqldb, nodeID):
	reply = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
	c = mysqldb.cursor()	
	c.execute('SELECT msgid,message FROM msgqueue WHERE nodeid=?',(nodeID,))
	result = c.fetchone()
	#if result != None:
		#reply = c.fetchone()
	c.close()
	return reply
	
def parse_message(mysqldb, nodeID,message):
	i = 1
	while True:
		msg_type = get_high(message[i])
		msg_size = get_low(message[i])
		if ((msg_type == 0) and (msg_size == 0)) or i >= 13:
			break
		if msg_type == 0:
			# Analogue status inputstate (nodeid integer, pin integer, state integer, raw integer )')
			pin_num = get_high(message[i+1])
			pin_state = get_low(message[i+1])
			mysqldb.execute('UPDATE inputstate SET state=? WHERE nodeid=? AND pin=?', (pin_state,nodeID,pin_num))
		elif msg_type == 1:
			# Analogue raw value
			pin_num = get_high(message[i+1])
			raw_val = (get_low(message[i+1])<<8)&get_high(message[i+2])&get_low(message[i+2])
			mysqldb.execute('UPDATE inputstate SET raw=? WHERE nodeid=? AND pin=?', (raw_val,nodeID,pin_num))
		elif msg_type == 2:
			# Digital value
			pin_num = get_high(message[i+1])
			pin_state = get_low(message[i+1])
			mysqldb.execute('UPDATE outputstate SET state=? WHERE nodeid=? AND pin=?', (pin_state,nodeID,pin_num))
		elif msg_type == 3:
			# Digital value
			card_number = message[i+1:msg_size+2]
			print "Card: ",decode_card(card_number)
			if check_card(mysqldb, decode_card(card_number)):
				drive_output(mysqldb, nodeID, 0, 1, 2000)
			#mysqldb.execute('UPDATE outputstate SET state=? WHERE nodeid=? AND pin=?', (pin_state,nodeID,pin_num))
			
		i = i + msg_size + 1 
	mysqldb.commit()
	'''c = mysqldb.cursor()
	c.execute('SELECT * FROM inputstate WHERE nodeid=1')
	value = c.fetchone()
	while value:
		print value
		value = c.fetchone()
	c.execute('SELECT * FROM outputstate WHERE nodeid=1')
	value = c.fetchone()
	while value:
		print value
		value = c.fetchone()
	c.close()'''

def drive_output(mysqldb, nodeid, pin, high_low, pulse):
	message = [0,0,0,0,0,0]
	if pulse != 0:
		message[0] = set_high(message[0], 5)
		message[0] = set_low(message[0], 5)
		message[1] = set_high(message[1], pin)
		message[1] = set_low(message[1], 0)
		# Not entirely sure how to pack a python integer into four bytes, so I'll encode 2000 by hand for now.
		# TODO
		message[2] = '\x00'
		message[3] = '\x00'
		message[4] = '\x07'
		message[5] = '\xD0'
	else:
		message[0] = set_high(message[0], 4)
		message[0] = set_low(message[0], 1)
		message[1] = set_high(message[1], pin)
		message[1] = set_low(message[1], high_low)
	#enqueue_message(sqldb, nodeid, message)
	print message
	
def decode_card(raw_card):
	# This function decodes a raw card bitstring and produces a card number. For now, it will always return 1.
	return 1
	
def check_card(mysqldb, card_number):
	# In the future this will check a number of factors, including whether this card has access on this node in this direction at this time.
	# For now, if the card exists in the database it has all access.
	c = mysqldb.cursor()
	c.execute('SELECT * FROM cards WHERE cardnumber=?',(card_number,))
	result = c.fetchone()
	if result != None:
		c.close()
		return 1
	else:
		c.close()
		return 0
	
def get_nodeID(mysqldb, ip):
	c = mysqldb.cursor()
	c.execute('SELECT nodeid FROM nodes WHERE ip=?',(ip,))
	result = c.fetchone()
	if result != None:
		c.close()
		return result[0]
	else:
		c.close()
		return 0

def get_cryptokey(mysqldb, nodeID):
	c = mysqldb.cursor()	
	c.execute('SELECT cryptokey FROM nodes WHERE nodeid=?',(nodeID,))
	result = c.fetchone()
	if result != None:
		c.close()
		return result[0]
	else:
		c.close()
		return 0
		
def get_high(byte):	
	return bytearray(byte)[0]>>4
	
def get_low(byte):
	return bytearray(byte)[0]&0x0F
	
def set_high(byte, val):
	byte = byte & 0x0F
	byte = byte|((val&0x0F)<<4)
	return byte
	
def set_low(byte, val):
	byte = byte & 0xF0
	byte = byte|(val&0x0F)
	return byte
	
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
	return array.array('B',message).tostring()
	
class ThreadedTCPServer(SocketServer.ThreadingMixIn, SocketServer.TCPServer):
	pass
	
	
def init_sqldb(db):
	
	db.execute('DROP TABLE IF EXISTS nodes')
	db.execute('DROP TABLE IF EXISTS msgqueue')
	db.execute('DROP TABLE IF EXISTS nodestatus')
	db.execute('DROP TABLE IF EXISTS inputstate')
	db.execute('DROP TABLE IF EXISTS outputstate')
	db.execute('DROP TABLE IF EXISTS cards')
	db.commit()
	
	db.execute('CREATE TABLE IF NOT EXISTS nodes (nodeid INTEGER PRIMARY KEY, tag text, description text, cryptokey text, ip text, status text, zone text)')
	db.execute('CREATE TABLE IF NOT EXISTS msgqueue (msgid integer, nodeid integer, message text)')
	db.execute('CREATE TABLE IF NOT EXISTS nodestatus (nodeid INTEGER PRIMARY KEY, var integer, state integer)')
	db.execute('CREATE TABLE IF NOT EXISTS inputstate (nodeid integer, pin integer, state integer, raw integer )')
	db.execute('CREATE TABLE IF NOT EXISTS outputstate (nodeid integer, pin integer, state integer, duration integer)')
	db.execute('CREATE TABLE IF NOT EXISTS cards (cardnumber integer, cardraw text)')
	
	#db.execute('INSERT INTO nodes VALUES (1, "TEST", "TEST NODE", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "192.168.1.177", "FINE, I GUESS.", "OUTSIDE")')
	setup_new_node(db)
	
	db.commit()
	# TODO Load a nodes list from a CSV file, populate the nodes DB.
	
def setup_new_node(db):
	db.execute('INSERT INTO nodes VALUES (1, "TEST", "TEST NODE", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "192.168.1.177", "FINE, I GUESS.", "OUTSIDE")')
	db.execute('INSERT INTO inputstate VALUES (1, 0, 2, 0)')
	db.execute('INSERT INTO inputstate VALUES (1, 1, 2, 0)')
	db.execute('INSERT INTO inputstate VALUES (1, 2, 2, 0)')
	db.execute('INSERT INTO inputstate VALUES (1, 3, 2, 0)')
	db.execute('INSERT INTO inputstate VALUES (1, 4, 2, 0)')
	
	db.execute('INSERT INTO outputstate VALUES (1, 0, 0, 0)')
	db.execute('INSERT INTO outputstate VALUES (1, 1, 0, 0)')
	db.execute('INSERT INTO outputstate VALUES (1, 2, 0, 0)')
	db.execute('INSERT INTO outputstate VALUES (1, 3, 0, 0)')
	db.execute('INSERT INTO outputstate VALUES (1, 4, 0, 0)')
	
	db.execute('INSERT INTO cards VALUES (1, 0)')
	
	db.commit()
	
def enqueue_message(sqldb,node_id, message):
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
	
	sqldb = sqlite3.connect('secnode.db', timeout=10, check_same_thread = False)
	print sqldb #sqlite3.config(SQLITE_CONFIG_SERIALIZED)
	init_sqldb(sqldb)
	print sqlite3
	
	while 1:
		time.sleep(1)
		enqueue_message(sqldb, 1, "111111")
		

	
