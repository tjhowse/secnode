'''
Secnode server.

This server accepts TCP connections from a remote device and decrypts them.

by Travis Howse <tjhowse@gmail.com>
2012.   License, GPL v2 or later

'''

from Crypto.Cipher import AES

import SocketServer
import sys

def toHex(s):
    lst = []
    for ch in s:
        hv = hex(ord(ch)).replace('0x', '')
        if len(hv) == 1:
            hv = '0'+hv
        lst.append(hv)
    
    return reduce(lambda x,y:x+y, lst)

class MyTCPHandler(SocketServer.BaseRequestHandler):
	"""
	The RequestHandler class for our server.

	It is instantiated once per connection to the server, and must
	override the handle() method to implement communication to the
	client.
	"""


	def handle(self):
		# self.request is the TCP socket connected to the client
		self.data = self.request.recv(16).strip()

		print "{} wrote:".format(self.client_address[0])
		print sys.getsizeof(self.data)
		if (sys.getsizeof(self.data) == 37):
			obj2 = AES.new('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', AES.MODE_ECB)
			print toHex(obj2.decrypt(self.data))
		
		# just send back the same data, but upper-cased
		#self.request.sendall(self.data.upper())

if __name__ == "__main__":
	HOST, PORT = "192.168.1.100", 5555

	# Create the server, binding to localhost on port 9999
	server = SocketServer.TCPServer((HOST, PORT), MyTCPHandler)

	# Activate the server; this will keep running until you
	# interrupt the program with Ctrl-C
	server.serve_forever()
	
