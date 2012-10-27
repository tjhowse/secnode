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

//#define SECSERVER
								 
byte mac[] = {	0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
byte ip[] = { 192,168,1,177 };

byte pri_server_ip[] = {192,168,1,100}; // HAL9002
Client pri_server(pri_server_ip, 5555);


byte sec_server_ip[] = {192,168,1,50}; // Tinman
Client sec_server(sec_server_ip, 5555);

aes256_context ctxt;


int i,j;
byte queue[QUEUESIZE];
int xmit_cursor;
int add_cursor;
unsigned long time;
// Unsure if byte is enough (1B)
byte msgcount;
byte xmit_buffer[2];
int msgsize;

byte key[] = {
	0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 
	0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 
	0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 
	0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61
};
	
void setup()
{
	Ethernet.begin(mac, ip);
	Serial.begin(9600);
	Serial.println("Hello...");
	
	msgcount = 0;
	xmit_cursor = 0;
	add_cursor = 0;
	
	aes256_init(&ctxt, key);
	
}

void loop()
{	
	byte testmessage[4];
	
	testmessage[0] = 0x11;
	testmessage[1] = 0x22;
	testmessage[2] = 0x33;
	testmessage[3] = 0x44;
	
	while (1)
	{
		enqueue_message(1, 4, testmessage);
		Serial.println(add_cursor);
		Serial.println(xmit_cursor);
		xmit_time();
	}
 
	aes256_done(&ctxt);
}

void xmit_time()
{
	// This function connects to the server/s and sends as many messages as it can inside its time slot.

	if (!GETSIZE(queue[xmit_cursor])) return;
	
	if (!pri_server.connect())
	{
		Serial.println("Failed to connect to primary server.");
		return;
	}
#ifdef SECSERVER
	if (!sec_server.connect())
		Serial.println("Failed to connect to secondary server.");
#endif
	time = millis();

	// If a really big message is last, this might overrun the time slot. No way to fix unless the time taken
	// to send messages can be pre-calculated faster than actually sending the message.
	while (((millis()-time) < XMITSLOT) && GETSIZE(queue[xmit_cursor]))
	{
		Serial.println("Xmitting message");
		xmit_message();
	}
		
	pri_server.stop();
#ifdef SECSERVER
	sec_server.stop();
#endif
	
}

void xmit_message()
{
	// This function pops a message off the queue, encrypts it, sends it and moves the send cursor along.
	prep_xmit_buffer();
	
	msgsize = (int)GETSIZE(xmit_buffer[1]);
	Serial.print("msgsize: ");
	Serial.println(msgsize,DEC);
	aes256_encrypt_ecb(&ctxt, xmit_buffer);
	
	if (pri_server.connected())
		pri_server.write(xmit_buffer,2);
	if (sec_server.connected())
		sec_server.write(xmit_buffer,2);
	
	for (int i = 0; i < (int)msgsize; i++)
	{
		Serial.print("i: ");
		Serial.println(i,DEC);
		prep_xmit_buffer();
		aes256_encrypt_ecb(&ctxt, xmit_buffer);
		if (pri_server.connected())
			pri_server.write(xmit_buffer,2);
		if (sec_server.connected())
			sec_server.write(xmit_buffer,2);
	}	

}

void prep_xmit_buffer()
{
	xmit_buffer[0] = msgcount++;
	xmit_buffer[1] = queue[xmit_cursor];
	queue[xmit_cursor] = 0x00;
	DUMP("Message to send: ", j, xmit_buffer, 2);
	inc_cursor(&xmit_cursor);
	Serial.print("xmit_cursor: ");
	Serial.println(xmit_cursor);
}

void enqueue_message(byte type, byte size, byte* data)
{	
	queue[add_cursor] = SETTYPE(queue[add_cursor],type);
	queue[add_cursor] = SETSIZE(queue[add_cursor],size);
	inc_cursor(&add_cursor);
	Serial.print("add_cursor: ");
	Serial.println(add_cursor);
	
	for (int i = 0; i < size; i++)
	{
		queue[add_cursor] = data[i];
		inc_cursor(&add_cursor);
		Serial.print("add_cursor: ");
		Serial.println(add_cursor);
	}
	Serial.println("Message enqueued.");
}

void inc_cursor(int* cursor)
{
	// Moves the add cursor through the send queue, wrapping to the start properly if need be.
	if (++(*cursor) >= QUEUESIZE)
	{
		(*cursor) = 0;
	}
}
