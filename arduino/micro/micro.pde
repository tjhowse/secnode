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
#include <EEPROM.h>
#include "aes256.h"
#include "secnode.h"
#include "msgtypes.h"
#include "eeprommap.h"

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

#define A_IO_COUNT 5
#define D_IO_COUNT 3
#define D_IO_PIN_START 4

#define CARD_SIGNAL_LENGTH 12

//#define SECSERVER
								 
byte mac[] = {	0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
byte ip[] = { 192,168,1,177 };
byte mask[] = {255,255,255,0};
byte gateway[] = {192,168,1,254};
byte dns[] = {8,8,8,8};

byte pri_server_ip[] = {192,168,1,101}; // HAL9002
Client pri_server(pri_server_ip, 5555);

byte sec_server_ip[] = {192,168,1,50}; // Tinman
Client sec_server(sec_server_ip, 5555);

aes256_context ctxt;

int i,j;
int i1, i2, i3, i4, i5, i6, i7, i8, i9;
byte queue[QUEUESIZE];
int xmit_cursor;
int add_cursor;
unsigned long time;

// Unsure if byte is enough (1B)
byte msgcount;
byte xmit_buffer[16];
byte recv_buffer[16];
byte msgsize;
byte total_msgsize;
int delme;
byte temp_msg[16];
byte digital_prev_state;

volatile byte scanned_card[CARD_SIGNAL_LENGTH];
volatile byte card_len; // Length, in bits, of the card read.
volatile byte scanner_2_used; // Flag to say that the second card reader was used.
unsigned long scan_check; // Time.
byte prev_card_len;

byte key[] = {
	0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 
	0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 
	0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 
	0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61
};
	
void setup()
{
	insert_eeprom_settings();
	load_eeprom_settings();
	
	Ethernet.begin(mac, ip); //, dns, gateway, mask);
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
	
	for (i1 = D_IO_PIN_START; i < D_IO_PIN_START+D_IO_COUNT; i1++)
		pinMode(i1, OUTPUT);
		
	clear_card_buffer();
	
	enable_interrupts();
		
	/*pri_server_ip[0] = 192;
	pri_server_ip[1] = 168;
	pri_server_ip[2] = 1;
	pri_server_ip[3] = 100;*/
	//pri_server(pri_server_ip, 5555);
	
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
		//dump_queue();
		xmit_time();	
		
		if (get_buffer_util() > 10)
		{
			Serial.print("Buffer filling: ");
			Serial.println(get_buffer_util());
		}
	} 
	aes256_done(&ctxt);
}

void enqueue_card_scan()
{
	if (!card_len) return;

	prev_card_len = card_len;
	scan_check = millis();	
	while ((millis()-scan_check) < 5)
	{
		// There might be a scan in progress right now. If the length doesn't change inside
		// a 5ms window, the scan has finished. Wiegand bits are 2ms apart at most.
		if (prev_card_len != card_len)
		{
			prev_card_len = card_len;
			scan_check = millis();
		}
	}
	//Serial.println(scanned_card);
	DUMP("Card: ", i, scanned_card, CARD_SIGNAL_LENGTH);
	disable_interrupts();
	enqueue_message(CARD_NUM, (card_len>>3)+1, (byte*)scanned_card);
	enable_interrupts();
	clear_card_buffer();
	
}

void clear_card_buffer()
{
	for (i1 = 0; i1 < CARD_SIGNAL_LENGTH; i1++)
		scanned_card[i1] = 0;
	
	card_len = 0;
	scanner_2_used = 0;
}

void enable_interrupts()
{
	//pinMode(2, OUTPUT);
	//pinMode(3, OUTPUT);
	digitalWrite(2,HIGH);
	digitalWrite(3,HIGH);
	attachInterrupt(0, card_reader_0, FALLING);
	attachInterrupt(1, card_reader_1, FALLING);
}

void disable_interrupts()
{
	detachInterrupt(0);
	detachInterrupt(1);
}	

void insert_eeprom_settings()
{
	EEPROM.write(NODE_IP, 192);
	EEPROM.write(NODE_IP+1, 168);
	EEPROM.write(NODE_IP+2, 1);
	EEPROM.write(NODE_IP+3, 177);
	
	EEPROM.write(NODE_MASK, 255);
	EEPROM.write(NODE_MASK+1, 255);
	EEPROM.write(NODE_MASK+2, 255);
	EEPROM.write(NODE_MASK+3, 0);
	
	EEPROM.write(NODE_GW, 192);
	EEPROM.write(NODE_GW+1, 168);
	EEPROM.write(NODE_GW+2, 1);
	EEPROM.write(NODE_GW+3, 254);
	
	EEPROM.write(NODE_DNS, 8);
	EEPROM.write(NODE_DNS+1, 8);
	EEPROM.write(NODE_DNS+2, 8);
	EEPROM.write(NODE_DNS+3, 8);
	
	EEPROM.write(NODE_MAC, 0xDE);
	EEPROM.write(NODE_MAC+1, 0xAD);
	EEPROM.write(NODE_MAC+2, 0xBE);
	EEPROM.write(NODE_MAC+3, 0xEF);
	EEPROM.write(NODE_MAC+4, 0xFE);
	EEPROM.write(NODE_MAC+5, 0xED);
	
	EEPROM.write(SERVER1_IP, 192);
	EEPROM.write(SERVER1_IP+1, 168);
	EEPROM.write(SERVER1_IP+2, 1);
	EEPROM.write(SERVER1_IP+3, 100);

	EEPROM.write(SERVER2_IP, 192);
	EEPROM.write(SERVER2_IP+1, 168);
	EEPROM.write(SERVER2_IP+2, 1);
	EEPROM.write(SERVER2_IP+3, 100);
	
	for (i1 = 0; i1 < 32; i1++)
		EEPROM.write(NODE_KEY + i1, 0x61);
		
	for (i1 = 0; i1 < 5; i1++)
		EEPROM.write(PIN_MODES + i1, 0x1);
}


void load_eeprom_settings()
{
	pri_server_ip[0] = EEPROM.read(SERVER1_IP);
	pri_server_ip[1] = EEPROM.read(SERVER1_IP+1);
	pri_server_ip[2] = EEPROM.read(SERVER1_IP+2);
	pri_server_ip[3] = EEPROM.read(SERVER1_IP+3);
	
	sec_server_ip[0] = EEPROM.read(SERVER2_IP);
	sec_server_ip[1] = EEPROM.read(SERVER2_IP+1);
	sec_server_ip[2] = EEPROM.read(SERVER2_IP+2);
	sec_server_ip[3] = EEPROM.read(SERVER2_IP+3);
	
	mask[0] = EEPROM.read(NODE_MASK);
	mask[1] = EEPROM.read(NODE_MASK+1);
	mask[2] = EEPROM.read(NODE_MASK+2);
	mask[3] = EEPROM.read(NODE_MASK+3);
	
	gateway[0] = EEPROM.read(NODE_GW);
	gateway[1] = EEPROM.read(NODE_GW+1);
	gateway[2] = EEPROM.read(NODE_GW+2);
	gateway[3] = EEPROM.read(NODE_GW+3);
	
	dns[0] = EEPROM.read(NODE_DNS);
	dns[1] = EEPROM.read(NODE_DNS+1);
	dns[2] = EEPROM.read(NODE_DNS+2);
	dns[3] = EEPROM.read(NODE_DNS+3);

	ip[0] = EEPROM.read(NODE_IP);
	ip[1] = EEPROM.read(NODE_IP+1);
	ip[2] = EEPROM.read(NODE_IP+2);
	ip[3] = EEPROM.read(NODE_IP+3);
	
	for (i1 = 0; i1 < 32; i1++)
		key[i1] = EEPROM.read(NODE_KEY + i1);

	for (i1 = 0; i1 < D_IO_COUNT; i1++)
	{
		if (EEPROM.read(PIN_MODES + i1))
			pinMode(i1+D_IO_PIN_START, INPUT);
		else
			pinMode(i1+D_IO_PIN_START, OUTPUT);
	}
}

void poll_state()
{
	// This function polls the hardware and determines whether the server needs to know anything.
	
	// TODO Check card number interrupt buffers. See if there has been a card scanned.
	
	// TODO Remove this
	/*for (i6 = 0; i6 < A_IO_COUNT; i6++)
	{
		delme = analogRead(i7);
		enqueue_raw_analogue(&i6, &delme);
	}*/
	
	/*for (i6 = D_IO_PIN_START; i6 < (D_IO_COUNT+D_IO_PIN_START); i6++)
		enqueue_digital(&i6);*/
	enqueue_card_scan();
	enqueue_digital_alarms();
	enqueue_analogue_alarms();

	// TODO Check interrupt buffer for the tamper accelerometer.
}

void enqueue_digital_alarms()
{
	for (i6 = D_IO_PIN_START; i6 < (D_IO_COUNT+D_IO_PIN_START); i6++)
	{
		delme = digitalRead(i6);
		if (delme != (bool)(digital_prev_state & (0x01<<(i6-D_IO_PIN_START))))
		{
			enqueue_digital(&i6, &delme);
			if (delme)
			{
				digital_prev_state |= ((0x01)<<(i6-D_IO_PIN_START));
			} else {
				digital_prev_state &= ~((0x01)<<(i6-D_IO_PIN_START));
			}
		}
	}
}

void enqueue_analogue_alarms()
{
	for (i7 = 0; i7 < A_IO_COUNT; i7++)
	{
		// TODO In the future these will be compared to calibrated values. For now, apply a dumb threshold.
		delme = analogRead(i7);
		if (delme == 1023)
			enqueue_raw_analogue(&i7, &delme);
	}
}

void enqueue_digital(int* input, int* value)
{
	// TODO Tidy this.
	delme = *value;
	zero_buffer(temp_msg);
	memcpy(&temp_msg, &delme,1);
	temp_msg[0] = SETTYPE(temp_msg[0],((byte)*input)-D_IO_PIN_START);
	enqueue_message(D_STATUS, 1, temp_msg);
}

void enqueue_raw_analogue(int* input, int* value)
{
	// TODO Tidy this.
	delme = *value;
	zero_buffer(temp_msg);
	memcpy(&temp_msg, &delme,2);
	temp_msg[1] = SETTYPE(temp_msg[1],(byte)*input);
	temp_msg[2] = temp_msg[0];
	temp_msg[0] = temp_msg[1];
	temp_msg[1] = temp_msg[2];	
	enqueue_message(A_RAW, 2, temp_msg);
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
		total_msgsize = 0;
		msgsize = GETSIZE(queue[xmit_cursor]);
		xmit_buffer[0] = msgcount++;
		while ((total_msgsize + msgsize) <= 13)
		{
			for (i1 = 0; i1 <= msgsize; i1++)
			{
				xmit_buffer[total_msgsize+i1+1] = queue[xmit_cursor];
				//DUMP("Enqueueing byte: ", j, xmit_buffer, 16);
				queue[xmit_cursor] = 0x00; // Consider not doing this until the message is ack'd
				inc_cursor(&xmit_cursor);
			}
			total_msgsize += (msgsize+1);
			msgsize = GETSIZE(queue[xmit_cursor]);
			if (!msgsize) break;
		}
		// TODO add a random byte at the second-from-the-end.
		append_random(xmit_buffer);
		append_checksum(xmit_buffer);
		//DUMP("Sending: ", j, xmit_buffer, 16);
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
		for (i2 = 0; i2 < 16; i2++)
		{
			while ((recv_buffer[i2] = pri_server.read()) == -1) {}
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
	for (i3 = 0; i3 < 64; i3++)
	{
		if ((xmit_cursor == i3) && (add_cursor == i3))
		{
			Serial.print("BB");
		} else if (add_cursor == i3)
		{
			Serial.print("AA");
		} else if (xmit_cursor == i3)
		{
			Serial.print("XX");
		} else {
			Serial.print("__");
		}
	}
	Serial.println("");
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
	for (i = 0; i < 15; i++)
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
	for (i = 0; i < 15; i++)
		buffer[15] ^= buffer[i];
		
	return (bool)buffer[15];
}

bool check_buffer_empty(byte* buffer)
{
	for (i = 0; i <= 15; i++)
		if ((int)buffer[i]) return 1;
	
	return 0;
}

void zero_buffer(byte* buffer)
{
	for (i = 0; i < 16; i++)
		buffer[i] = 0x00;
}

void enqueue_message(byte type, byte size, byte* data)
{	
	if ((int)size > 13)
	{
		Serial.println("Overlarge message not enqueued.");
		return;
	}
	
	for (i4 = 0; i4 <= size; i4++)
	{
		if (!i4)
		{
			queue[add_cursor] = SETTYPE(queue[add_cursor],type);
			queue[add_cursor] = SETSIZE(queue[add_cursor],size);
		} else {
			queue[add_cursor] = data[i4-1];
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
			for (i5 = 0; i5 < ((int)GETSIZE(queue[add_cursor])); i5++)
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

void card_reader_0()
{
	card_len++;
}

void card_reader_1()
{
	scanned_card[card_len>>3] |= 0x01<<(card_len%8);
	card_len++;
	// Assuming the data1 line from the second card reader leads here
	if (!digitalRead(4))
		scanner_2_used = 1;
}

