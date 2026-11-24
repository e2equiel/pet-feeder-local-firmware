#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../src/discovery.h"
int main(void) {
    char output[1024];
    pf_description(output,sizeof(output),"aa:bb:cc:dd:ee:ff");
    assert(strstr(output,"<serialNumber>aa:bb:cc:dd:ee:ff</serialNumber>"));
    assert(strstr(output,"uuid:00000000-0000-4000-8000-aabbccddeeff"));
    assert(strstr(output,"urn:pet-feeder-local:device:Feeder:1"));
    assert(!strstr(output,"token") && !strstr(output,"meals"));
    pf_description(output,sizeof(output),"invalid<xml>");assert(!output[0]);
    pf_description(output,2,"aa:bb:cc:dd:ee:ff");assert(output[1]==0);
    puts("Minimal discovery description and identity validation passed");
    return 0;
}
