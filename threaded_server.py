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
				decrypted[5] = 'a'
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

if __name__ == "__main__":
	HOST, PORT = "192.168.1.100", 5555

	server = ThreadedTCPServer((HOST, PORT), ThreadedTCPRequestHandler)
	ip, port = server.server_address

	# Start a thread with the server -- that thread will then start one
	# more thread for each request
	server_thread = threading.Thread(target=server.serve_forever)
	# Exit the server thread when the main thread terminates
	server_thread.daemon = True
	server_thread.start()
	
	while 1:
		time.sleep(1)
