/*
Secnode client.

This client encrypts data and sends them to a server.

by Travis Howse <tjhowse@gmail.com>
2012.	 License, GPL v2 or later
*/

#include <SPI.h>
#include <Ethernet.h>
#include <stdio.h>
#include <stdlib.h>
#include <WProgram.h>
#include "aes256.h"
#include "secnode.h"

#define DUMP(str, i, buf, sz) { Serial.println(str); \
															 for(i=0; i<(sz); ++i) { if(buf[i]<0x10) Serial.print('0'); Serial.print(buf[i], HEX); } \
															 Serial.println(); }

#define GETSIZE(details) details & 0x0F
#define GETTYPE(details) (details & 0xF0)>>4

#define SETSIZE(details,size) (details & 0xF0) | size
#define SETTYPE(details,type) (details & 0x0F) | (type << 4)

#define QUEUESIZE 512 // Bytes
#define XMITSLOT 500 // Milliseconds
								 
byte mac[] = {	0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
byte ip[] = { 192,168,1,177 };
byte pri_server_ip[] = {192,168,1,100}; // HAL9002
byte sec_server_ip[] = {192,168,1,50}; // Tinman
aes256_context ctxt;
Client pri_server(pri_server_ip, 5555);
Client sec_server(sec_server_ip, 5555);
int i;
byte queue[QUEUESIZE];
int xmit_cursor;
int add_cursor;
unsigned long time;
// Unsure if byte is enough (1B)
byte msgcount;
byte xmit_buffer[2];
byte msgsize;

byte key[] = {
	0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 
	0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 
	0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 
	0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61
};
	
void setup()
{
	message testmessage;
	Ethernet.begin(mac, ip);
	Serial.begin(9600);
	Serial.println("Connecting...");
	
	msgcount = 0;
	
	aes256_init(&ctxt, key);
	
	/*byte data[] = {
		0x61, 0x73, 0x64, 0x66, 0x61, 0x73, 0x64, 0x66,
		0x61, 0x73, 0x64, 0x66, 0x61, 0x73, 0x64, 0x66
	};*/
	byte data[] = "Hello this is a";
	aes256_encrypt_ecb(&ctxt, data);
	
	
	if (pri_server.connect()) {
		Serial.println("connected");
		//client.println("testing");
		DUMP("Sending: ", i, data, sizeof(data));
		//Serial.println((byte&)data);
		//ETHDUMP(i, data, sizeof(data),client);
		Serial.println(sizeof(data));
		pri_server.write(data, sizeof(data));

		//client.println((byte&)data);
	}
	
	aes256_done(&ctxt);
	
	
	testmessage.details = 0x00;
	
	testmessage.details = SETTYPE(testmessage.details,5);
	testmessage.details = SETSIZE(testmessage.details,4);
	
	Serial.print("Whole: ");
	Serial.println(testmessage.details, HEX);
	Serial.print("Size: ");
	Serial.println(GETSIZE(testmessage.details), HEX);
	Serial.print("Type: ");
	Serial.println(GETTYPE(testmessage.details), HEX);
}

void loop()
{
 
	
}

void xmit_time()
{
	// This function connects to the server/s and sends as many messages as it can inside its time slot.

	if (add_cursor == xmit_cursor) return;
	
	if (!pri_server.connect())
		Serial.println("Failed to connect to primary server.");
	
	if (!sec_server.connect())
		Serial.println("Failed to connect to secondary server.");

	time = millis();

	// If a really big message is last, this might overrun the time slot. No way to fix unless the time taken
	// to send messages can be pre-calculated faster than actually sending the message.
	while ((millis()-time) > XMITSLOT)
		xmit_message();
		
	pri_server.stop();
	sec_server.stop();
	
}

void xmit_message()
{
	// This function pops a message off the queue, encrypts it, sends it and moves the send cursor along.
	
	get_xmit_bytes();
	
	msgsize = GETSIZE(xmit_buffer[1]);
	aes256_encrypt_ecb(&ctxt, xmit_buffer);
	
	if (pri_server.connected())
		pri_server.write(xmit_buffer,2);
	if (pri_server.connected())
		pri_server.write(xmit_buffer,2);
	
	for (i = 0; i < msgsize; i++)
	{
		get_xmit_bytes();
		aes256_encrypt_ecb(&ctxt, xmit_buffer);
		if (pri_server.connected())
			pri_server.write(xmit_buffer,2);
		if (pri_server.connected())
			pri_server.write(xmit_buffer,2);
	}	

}

void get_xmit_bytes()
{
	xmit_buffer[0] = msgcount++;
	xmit_buffer[1] = queue[xmit_cursor];
	inc_cursor(xmit_cursor);
}

void enqueue_message(byte type, byte size, byte* data)
{
	queue[add_cursor] = SETTYPE(queue[add_cursor],type);
	queue[add_cursor] = SETSIZE(queue[add_cursor],size);
	inc_cursor(add_cursor);
	
	for (i = 0; i < size; i++)
	{
		queue[add_cursor] = data[i];
		inc_cursor(add_cursor);
	}
}

void inc_cursor(int cursor)
{
	// Moves the add cursor through the send queue, wrapping to the start properly if need be.
	if (++cursor >= QUEUESIZE)
	{
		cursor = 0;
	}
}