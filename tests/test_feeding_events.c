#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../src/feeding_events.h"

int main(void) {
    char out[3072];
    unsigned char row[]={255,252,7,5,16,21,2,1,1};
    pf_events_init(NULL); assert(!pf_events_observe(row,sizeof(row),100));
    assert(pf_events_json(out,sizeof(out),100)==-1);
    pf_events_init("bad"); assert(pf_events_json(out,sizeof(out),100)==-1);
    pf_events_init("0123456789abcdef0123456789abcdef");
    assert(!pf_events_json(out,sizeof(out),100)); assert(strstr(out,"\"events\":[]"));
    assert(!pf_events_observe(row,8,100));
    row[1]=255; assert(!pf_events_observe(row,9,100)); row[1]=252;
    row[2]=1; assert(!pf_events_observe(row,9,100)); row[2]=7;
    row[3]=4; assert(!pf_events_observe(row,9,100)); row[3]=5;
    row[5]=24; assert(!pf_events_observe(row,9,100)); row[5]=21;
    row[8]=0; assert(!pf_events_observe(row,9,100)); row[8]=1;
    assert(pf_events_observe(row,9,100));
    assert(!pf_events_json(out,sizeof(out),550)); assert(strstr(out,"\"age_ms\":450"));
    assert(strstr(out,"\"sequence\":1") && strstr(out,"\"portions\":1"));
    assert(pf_events_json(out,4,550)==-1);
    assert(!pf_events_json(out,sizeof(out),99)); assert(strstr(out,"\"events\":[]"));
    assert(!pf_events_json(out,sizeof(out),600101)); assert(strstr(out,"\"events\":[]"));
    for (unsigned i=0;i<20;i++) assert(pf_events_observe(row,9,0x100000000ull+i));
    assert(!pf_events_json(out,sizeof(out),0x100000020ull));
    assert(strstr(out,"\"sequence\":21,"));
    assert(!strstr(out,"\"sequence\":5,")); assert(strstr(out,"\"sequence\":6,"));
    pf_events_init("fedcba9876543210fedcba9876543210");
    assert(!pf_events_json(out,sizeof(out),100)); assert(strstr(out,"\"sequence\":0,"));
    puts("Scheduled MCU telemetry: accepted records, rejected ACKs, bounded history and monotonic age passed.");
}
