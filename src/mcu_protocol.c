#include "mcu_protocol.h"
#include <string.h>

int pf_meal_valid(const struct pf_meal *meal) {
    return meal && meal->weekdays <= 127 && meal->hour <= 23 &&
        meal->minute <= 59 && meal->portions >= 1 &&
        meal->portions <= PF_MAX_PORTIONS && meal->enabled <= 1;
}

int pf_encode_feed(unsigned portions, uint8_t out[14]) {
    if (!out || portions < 1 || portions > PF_MAX_PORTIONS) return -1;
    /* Reproduces stock 68.00.09's DP201 encoder (0x14b0a8).
     * The stock application uses a fixed 10 gram weight per portion.
     * The five-byte prefix is vendor protocol data, not our system clock.
     */
    const uint8_t frame[14]={0xff,0xff,0x01,0x0a,
        0x3a,0x09,0x03,0x0e,0x0b,0,0,0,0,0};
    memcpy(out,frame,sizeof(frame));
    unsigned grams=portions*10;
    out[9]=(uint8_t)grams; out[10]=(uint8_t)(grams>>8);
    return 0;
}

size_t pf_encode_schedule_query(uint8_t out[7]) {
    static const uint8_t frame[7]={0xff,0xff,0x30,0x03,0x01,0x00,0x01};
    memcpy(out,frame,sizeof(frame)); return sizeof(frame);
}

int pf_encode_schedule(const struct pf_meal *meals,size_t count,
                       uint8_t *out,size_t capacity,size_t *length) {
    if (!out || !length || count>PF_MAX_MEALS || (count && !meals)) return -1;
    size_t size=7+count*5;
    if (capacity<size) return -1;
    for (size_t i=0;i<count;i++) if (!pf_meal_valid(meals+i)) return -1;
    out[0]=out[1]=0xff; out[2]=0x30; out[3]=(uint8_t)(3+count*5);
    out[4]=0x10; out[5]=(uint8_t)count;
    for (size_t i=0;i<count;i++) {
        size_t p=6+i*5;
        out[p]=meals[i].weekdays; out[p+1]=meals[i].hour;
        out[p+2]=meals[i].minute; out[p+3]=meals[i].portions;
        out[p+4]=meals[i].enabled;
    }
    uint8_t sum=0;
    for (size_t i=4;i<size-1;i++) sum=(uint8_t)(sum+out[i]);
    out[size-1]=sum; *length=size; return 0;
}

int pf_decode_schedule(const uint8_t *payload,size_t length,
                       struct pf_meal out[PF_MAX_MEALS],size_t *count) {
    if (!payload || !out || !count || length<3 || payload[0]!=1) return -1;
    size_t n=payload[1];
    if (n>PF_MAX_MEALS || length!=3+n*5) return -1;
    uint8_t sum=0;
    for (size_t i=0;i<length-1;i++) sum=(uint8_t)(sum+payload[i]);
    if (sum!=payload[length-1]) return -1;
    struct pf_meal decoded[PF_MAX_MEALS];
    for (size_t i=0;i<n;i++) {
        const uint8_t *p=payload+2+i*5;
        decoded[i]=(struct pf_meal){p[0],p[1],p[2],p[3],p[4]};
        if (!pf_meal_valid(decoded+i)) return -1;
    }
    memcpy(out,decoded,n*sizeof(*out)); *count=n; return 0;
}

uint32_t pf_schedule_revision(const struct pf_meal *meals,size_t count) {
    uint32_t hash=2166136261u;
    hash=(hash^(uint8_t)count)*16777619u;
    for (size_t i=0;i<count;i++) {
        const uint8_t fields[]={meals[i].weekdays,meals[i].hour,
            meals[i].minute,meals[i].portions,meals[i].enabled};
        for (size_t j=0;j<sizeof(fields);j++) hash=(hash^fields[j])*16777619u;
    }
    return hash;
}
