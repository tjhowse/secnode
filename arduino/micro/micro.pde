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
#include "msgtypes.h"
#include <utility/w5100.h> // For the ethernet library.

#define DUMP(str, i, buf, sz) { Serial.println(str); \
								for(i=0; i<(sz); ++i) { if(buf[i]<0x10) Serial.print('0'); Serial.print(buf[i], HEX); } \
								Serial.println(); }

#define GETSIZE(details) (details & 0x0F)
#define GETTYPE(details) ((details & 0xF0)>>4)

#define SETSIZE(details,size) ((details & 0xF0) | size)
#define SETTYPE(details,type) ((details & 0x0F) | (type << 4))

#define QUEUESIZE 64 // Bytes
#define XMITSLOT 500 // Milliseconds
#define ACKWAIT 200 // Milliseconds


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
byte xmit_buffer[16];
byte recv_buffer[16];
int msgsize;

byte temp_msg[16];

byte key[] = {
	0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 
	0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 
	0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 
	0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61
};
	
void setup()
{
	Ethernet.begin(mac, ip);
	W5100.setRetransmissionTime(0x07D0);
	W5100.setRetransmissionCount(3);
	Serial.begin(9600);
	Serial.println("Hello...");
	
	msgcount = 0;
	xmit_cursor = 0;
	add_cursor = 0;
	
	aes256_init(&ctxt, key);
	zero_buffer(xmit_buffer);
	randomSeed(analogRead(5));
	
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
		//enqueue_message(1, 4, testmessage);
		//enqueue_message(1, 3, testmessage);
		//Serial.println(add_cursor);
		//Serial.println(xmit_cursor);
		
		// TODO Send a heartbeat to the server/s. It might respond with commands,
		// add any commands to the command queue.
		// Consider just enqueueing a message once every cycle to act as a heartbeat.
		// TODO Act on commands.
		
		poll_state();		
		xmit_time();
		
		if (get_buffer_util() > 10)
		{
			Serial.print("Buffer filling: ");
			Serial.println(get_buffer_util());
		}		
	} 
	aes256_done(&ctxt);
}

void poll_state()
{
	// This function polls the hardware and determines whether the server needs to know anything.
	
	// TODO Check card number interrupt buffers. See if there has been a card scanned.
	
	// TODO Check digital and analogue inputs.
	int delme = analogRead(0);
	
	zero_buffer(temp_msg);
	memcpy(&temp_msg, &delme,2);
	enqueue_message(A0_RAW, 2, temp_msg);
	
	// TODO Check interrupt buffer for the tamper accelerometer.
}

void xmit_time()
{
	// This function connects to the server/s and sends as many messages as it can inside its time slot.
	if (((int)GETSIZE(queue[xmit_cursor]) == 0) && !check_buffer_empty(xmit_buffer)) return;
	
	if (!pri_server.connect())
	{
		Serial.println("Failed to connect to primary server.");
		return;
	}
#ifdef SECSERVER
	if (!sec_server.connect())
		Serial.println("Failed to connect to secondary server.");
#endif
	
	// If a really big message is last, this might overrun the time slot. No way to fix unless the time taken
	// to send messages can be pre-calculated faster than actually sending the message.
	time = millis();
	while (((millis()-time) < XMITSLOT) && ((int)GETSIZE(queue[xmit_cursor]) != 0))
	{
		//Serial.println((int)GETSIZE(queue[xmit_cursor]));
		xmit_message();
		wait_ack();
	}
		
	pri_server.stop();
#ifdef SECSERVER
	sec_server.stop();
#endif	
}

void xmit_message()
{
	// This function pops a message off the queue, encrypts it, sends it and moves the send cursor along.
	
	// If the xmit buffer is empty, the previous message was successfully sent.
	if (!check_buffer_empty(xmit_buffer))
	{
		zero_buffer(xmit_buffer);
		
		msgsize = (int)GETSIZE(queue[xmit_cursor]);
		
		xmit_buffer[0] = msgcount++;

		for (int i = 0; i <= msgsize; i++)
		{
			xmit_buffer[i+1] = queue[xmit_cursor];
			//DUMP("Enqueueing byte: ", j, xmit_buffer, 16);
			queue[xmit_cursor] = 0x00; // Consider not doing this until the message is ack'd
			inc_cursor(&xmit_cursor);
		}
		// TODO add a random byte at the second-from-the-end.
		append_random(xmit_buffer);
		append_checksum(xmit_buffer);		
		aes256_encrypt_ecb(&ctxt, xmit_buffer);
	}
	
	if (pri_server.connected())
		pri_server.write(xmit_buffer,16);

	if (sec_server.connected())
		sec_server.write(xmit_buffer,16);
		
}

void wait_ack()
{
	unsigned long acktime = millis();

	// Wait for data to become available on the receive end of this client connection, or time out.
	while (((millis()-acktime) < ACKWAIT) && !pri_server.available())
		delay(10);
	
	// If it left the above loop because it got a response...
	if (pri_server.available())
	{
		for (int i = 0; i < 16; i++)
		{
			while ((recv_buffer[i] = pri_server.read()) == -1) {}
		}
		aes256_decrypt_ecb(&ctxt, recv_buffer);
		if (check_checksum(recv_buffer))
		{
			Serial.println("Ack checksum fail. Sending again.");
			DUMP("Received: ", i, recv_buffer, 16);
		} else {
			//DUMP("Received: ", i, recv_buffer, 16);
			// Received reply, checksum passed.
			// TODO If a "I have news for you" flag comes in from the server, enqueue another heartbeat packet
			// to allow the server to send another message.
			zero_buffer(xmit_buffer);
		}
	} else {
		//Serial.print("Didn't receive an ack for message: ");
		aes256_decrypt_ecb(&ctxt, xmit_buffer);
		DUMP("Didn't receive an ack for message: ", i, xmit_buffer, 16);
		aes256_encrypt_ecb(&ctxt, xmit_buffer);
	}
}

void dump_queue()
{
	DUMP("Queue: ", j, queue, 64);
	for (int i = 0; i < 64; i++)
	{
		if ((xmit_cursor == i) && (add_cursor == i))
		{
			Serial.print("BB");
		} else if (add_cursor == i)
		{
			Serial.print("AA");
		} else if (xmit_cursor == i)
		{
			Serial.print("XX");
		} else {
			Serial.print("__");
		}
	}
}

int get_buffer_util()
{
	if (add_cursor < xmit_cursor)
		return (QUEUESIZE-xmit_cursor)+add_cursor;
	return add_cursor-xmit_cursor;
}

void append_checksum(byte* buffer)
{
	// Not sure if this is a great checksum. It should be good enough.
	buffer[15] = 0x00;
	for (int i = 0; i < 15; i++)
		buffer[15] ^= buffer[i];
}

void append_random(byte* buffer)
{
	// I'm no cryptography buff, but it seems to me that if the node sent the same encrypted message occasionally,
	// when a state transmission happened to synch with a value of the msgcount value, information could potentially 
	// leak. Making the second-last byte random would make this ^255 less likely. I think.
	buffer[14] = random(255);
}

bool check_checksum(byte* buffer)
{
	for (int i = 0; i < 15; i++)
		buffer[15] ^= buffer[i];
		
	return (bool)buffer[15];
}

bool check_buffer_empty(byte* buffer)
{
	for (int i = 0; i <= 15; i++)
		if ((int)buffer[i]) return 1;
	
	return 0;
}

void zero_buffer(byte* buffer)
{
	for (int i = 0; i < 16; i++)
		buffer[i] = 0x00;
}

void zero_msg_temp()
{
}	

void enqueue_message(byte type, byte size, byte* data)
{	
	if ((int)size > 13)
	{
		Serial.println("Overlarge message not enqueued.");
		return;
	}
	
	for (int i = 0; i <= size; i++)
	{
		if (!i)
		{
			queue[add_cursor] = SETTYPE(queue[add_cursor],type);
			queue[add_cursor] = SETSIZE(queue[add_cursor],size);
		} else {
			queue[add_cursor] = data[i-1];
		}
		inc_cursor(&add_cursor);
		check_overrun();
	}
	//Serial.println("Message enqueued.");
}

void check_overrun()
{
	if (add_cursor == xmit_cursor)
	{
		// Uh-oh. Our buffer has filled. Let's move the xmit_cursor along to the start of the oldest message.
		//Serial.print("Buffer overrun, size of next message: ");
		//Serial.println((int)GETSIZE(queue[xmit_cursor]));
		if ((int)GETSIZE(queue[xmit_cursor]))
		{
			for (int j = 0; j < ((int)GETSIZE(queue[add_cursor])); j++)
			{
				queue[add_cursor] = 0x00;
				inc_cursor(&xmit_cursor);
			}
		}
	}
}

void inc_cursor(int* cursor)
{
	// Moves the add cursor through the send queue, wrapping to the start properly if need be.
	if ((++(*cursor)) >= QUEUESIZE)
		(*cursor) = 0;
}

int peek_cursor(int* cursor)
{
	if (((*cursor)+1) >= QUEUESIZE)
		return 0;
	return ((*cursor)+1);	
}
