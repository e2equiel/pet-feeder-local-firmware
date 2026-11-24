#include "../src/mcu_protocol.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>

int main(void) {
    uint8_t frame[PF_MAX_SCHEDULE_FRAME]; size_t length=0,count=0;
    const uint8_t one_portion[]={0xff,0xff,1,10,0x3a,9,3,14,11,10,0,0,0,0};
    assert(pf_encode_feed(1,frame)==0);
    assert(!memcmp(frame,one_portion,sizeof(one_portion)));
    assert(pf_encode_feed(0,frame)<0);
    assert(pf_encode_feed(11,frame)<0);
    assert(pf_encode_feed(10,frame)==0 && frame[9]==100);
    assert(pf_encode_schedule_query(frame)==7);
    assert(!memcmp(frame,(uint8_t[]){255,255,48,3,1,0,1},7));
    unsigned wall_clock[]={2026,11,23,23,12,33};
    assert(!pf_encode_clock(wall_clock,frame));
    assert(!memcmp(frame,(uint8_t[]){255,255,6,6,66,11,23,23,12,33},10));
    wall_clock[1]=2; wall_clock[2]=29;
    assert(pf_encode_clock(wall_clock,frame));
    wall_clock[0]=2028;
    assert(!pf_encode_clock(wall_clock,frame));
    wall_clock[0]=2100;
    assert(pf_encode_clock(wall_clock,frame));

    struct pf_meal meals[]={{127,8,0,2,1},{62,19,30,1,0}};
    struct pf_meal decoded[PF_MAX_MEALS];
    assert(pf_encode_schedule(meals,2,frame,sizeof(frame),&length)==0);
    assert(length==17 && frame[4]==16 && frame[5]==2);
    /* Turn a write into a synthetic MCU query response, recompute checksum. */
    frame[4]=1; uint8_t sum=0;
    for (size_t i=4;i<length-1;i++) sum=(uint8_t)(sum+frame[i]);
    frame[length-1]=sum;
    assert(pf_decode_schedule(frame+4,length-4,decoded,&count)==0);
    assert(count==2 && !memcmp(meals,decoded,sizeof(meals)));
    assert(decoded[1].enabled==0);
    uint32_t revision=pf_schedule_revision(decoded,count);
    decoded[1].enabled=1;
    assert(revision!=pf_schedule_revision(decoded,count));
    frame[length-1]^=1;
    assert(pf_decode_schedule(frame+4,length-4,decoded,&count)<0);
    assert(pf_decode_schedule(frame+4,length-5,decoded,&count)<0);
    frame[5]=255;
    assert(pf_decode_schedule(frame+4,length-4,decoded,&count)<0);
    meals[0].hour=24;
    assert(pf_encode_schedule(meals,2,frame,sizeof(frame),&length)<0);
    meals[0].hour=8;
    assert(pf_encode_schedule(meals,9,frame,sizeof(frame),&length)<0);
    assert(pf_encode_schedule(meals,2,frame,5,&length)<0);
    assert(pf_encode_schedule(0,0,frame,sizeof(frame),&length)==0 && length==7);
    puts("MCU protocol validation passed");
    return 0;
}
