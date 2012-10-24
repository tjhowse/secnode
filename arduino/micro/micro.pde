/*
Secnode client.

This client encrypts data and sends them to a server.

by Travis Howse <tjhowse@gmail.com>
2012.   License, GPL v2 or later
*/

#include <SPI.h>
#include <Ethernet.h>

#include "aes256.h"

#define DUMP(str, i, buf, sz) { Serial.println(str); \
                               for(i=0; i<(sz); ++i) { if(buf[i]<0x10) Serial.print('0'); Serial.print(buf[i], HEX); } \
                               Serial.println(); }

byte mac[] = {  0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
byte ip[] = { 192,168,1,177 };
byte server[] = {192,168,1,100}; // HAL9002
aes256_context ctxt;
Client client(server, 5555);
int i;

void setup()
{
  Ethernet.begin(mac, ip);
  Serial.begin(9600);
  Serial.println("Connecting...");
  
  uint8_t key[] = {
    0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 
    0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 
    0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 
    0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61, 0x61
  };
  
  aes256_init(&ctxt, key);
  Serial.println("done");
  
  /*uint8_t data[] = {
    0x61, 0x73, 0x64, 0x66, 0x61, 0x73, 0x64, 0x66,
    0x61, 0x73, 0x64, 0x66, 0x61, 0x73, 0x64, 0x66
  };*/
  uint8_t data[] = "Hello this is a";
  DUMP("Sending: ", i, data, sizeof(data));
  
  aes256_encrypt_ecb(&ctxt, data); 
  DUMP("Encrypted: ", i, data, sizeof(data));
  
  if (client.connect()) {
    Serial.println("connected");
    //client.println("testing");
    DUMP("Sending: ", i, data, sizeof(data));
    //Serial.println((uint8_t&)data);
    //ETHDUMP(i, data, sizeof(data),client);
    Serial.println(sizeof(data));
    client.write(data, sizeof(data));

    //client.println((uint8_t&)data);
  }
  
  aes256_done(&ctxt);
}

void loop()
{
 
  
}
    
