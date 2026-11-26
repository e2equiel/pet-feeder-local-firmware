#define _GNU_SOURCE
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#include "json.h"
#include "local_api.h"
#include "mcu_protocol.h"
#include "journal.h"
#include "discovery.h"
#include "feeding_events.h"

#ifdef __GLIBC__
extern int uclibc_sscanf(const char *,const char *,...) __asm__("sscanf");
#define sscanf uclibc_sscanf
#endif

#define RING_SIZE 2048
static unsigned char ring[RING_SIZE];
static volatile unsigned ring_head,ring_tail,ring_overflow;
static int observed_uart=-1,tx_uart=-1,tx_fault;
static unsigned char serial_frame[260];
static size_t serial_used;
static struct pf_meal current_meals[PF_MAX_MEALS],pending_meals[PF_MAX_MEALS];
static size_t current_count,pending_count;
static unsigned schedule_generation,request_generation;
static uint32_t schedule_revision,expected_revision;
static unsigned last_mcu_ms,last_query_ms,deadline_ms;
static int have_schedule,initialized,listener=-1,client=-1,pending;
static char api_token[97],device_id[40]="unidentified",input[8192];
static size_t input_used;
static struct pf_journal journal;
static int feeding_enabled,journal_ready,feed_ack,clock_ack,clock_synced;
static unsigned manual_commands_sent;
static char feed_operation[65];

static uint64_t event_milliseconds(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC,&t)) return 0;
    return (uint64_t)t.tv_sec*1000u+(unsigned)(t.tv_nsec/1000000);
}

static unsigned milliseconds(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC,&t)) return 0;
    return (unsigned)t.tv_sec*1000u+(unsigned)(t.tv_nsec/1000000);
}

void pf_uart_observe(int fd,const unsigned char *data,size_t length) {
    if (fd<0 || fd>8) return;
    if (observed_uart<0) {
        char path[48],target[80];
        snprintf(path,sizeof(path),"/proc/self/fd/%d",fd);
        ssize_t n=readlink(path,target,sizeof(target)-1);
        if (n<0) return;
        target[n]=0;
        if (strcmp(target,"/dev/ttySAK1")) return;
        observed_uart=fd;
    }
    if (fd!=observed_uart) return;
    for (size_t i=0;i<length;i++) {
        unsigned next=(ring_head+1)&(RING_SIZE-1);
        if (next==ring_tail) { ring_overflow=1; break; }
        ring[ring_head]=data[i];
        __asm__ volatile("" ::: "memory");
        ring_head=next;
    }
}

static void drain_serial(void) {
    if (ring_overflow) {
        serial_used=0; ring_tail=ring_head; ring_overflow=0; have_schedule=0;
    }
    while (ring_tail!=ring_head) {
        unsigned char byte=ring[ring_tail];
        ring_tail=(ring_tail+1)&(RING_SIZE-1);
        if (!serial_used && byte!=255) continue;
        if (serial_used==1 && byte!=255 && byte!=252) { serial_used=0; continue; }
        serial_frame[serial_used++]=byte;
        if (serial_used<4 || serial_used<(size_t)serial_frame[3]+4) continue;
        last_mcu_ms=milliseconds();
        pf_events_observe(serial_frame,serial_used,event_milliseconds());
        if (pending==5 && serial_frame[2]==1 && serial_frame[3]==1)
            feed_ack=serial_frame[4]==0 ? 1:-1;
        if (pending==6 && serial_frame[2]==6 && serial_frame[3]==1)
            clock_ack=serial_frame[4]==0 ? 1:-1;
        if (serial_frame[2]==0x30 &&
            !pf_decode_schedule(serial_frame+4,serial_frame[3],current_meals,&current_count)) {
            have_schedule=1; schedule_generation++;
            schedule_revision=pf_schedule_revision(current_meals,current_count);
        }
        serial_used=0;
    }
}

static int serial_write(const unsigned char *data,size_t length) {
    if (tx_fault || observed_uart<0) return -1;
    if (tx_uart<0) tx_uart=open("/dev/ttySAK1",O_WRONLY|O_NOCTTY|O_NONBLOCK);
    if (tx_uart<0) return -1;
    ssize_t count=pf_uart_transmit(tx_uart,data,(unsigned)length);
    if (count!=(ssize_t)length) { tx_fault=1; return -1; }
    return 0;
}

static int query_schedule(void) {
    unsigned char frame[7]; pf_encode_schedule_query(frame);
    last_query_ms=milliseconds(); return serial_write(frame,sizeof(frame));
}

static int read_text(const char *path,char *out,size_t capacity) {
    int fd=open(path,O_RDONLY);
    if (fd<0) return -1;
    ssize_t size=read(fd,out,capacity-1); close(fd);
    if (size<=0 || (size_t)size>=capacity-1) return -1;
    while (size>0 && (out[size-1]=='\r' || out[size-1]=='\n')) size--;
    out[size]=0; return (int)size;
}

static int token_equal(const char *a,size_t length,const char *b) {
    size_t expected=strlen(b); unsigned difference=(unsigned)(length^expected);
    for (size_t i=0;i<expected;i++) difference|=(unsigned char)b[i]^(i<length ? (unsigned char)a[i]:0);
    return difference==0;
}

static int header_auth(const char *request,size_t length,const char *scheme,const char *secret) {
    const char *cursor=request,*limit=request+length;
    while (cursor<limit) {
        const char *end=memchr(cursor,'\n',(size_t)(limit-cursor));
        if (!end) end=limit;
        if ((size_t)(end-cursor)>14 && !strncasecmp(cursor,"Authorization:",14)) {
            const char *value=cursor+14;
            while (value<end && (*value==' ' || *value=='\t')) value++;
            size_t prefix=strlen(scheme);
            const char *last=end;
            if (last>value && last[-1]=='\r') last--;
            return (size_t)(last-value)>=prefix && !strncasecmp(value,scheme,prefix) &&
                token_equal(value+prefix,(size_t)(last-value)-prefix,secret);
        }
        cursor=end<limit ? end+1:limit;
    }
    return 0;
}

int pf_rtsp_authorized(const char *request) {
    /* HTTP and RTSP use the same private per-device token. */
    static char encoded[160];
    if (!api_token[0]) return 0;
    if (!encoded[0]) {
        static const char alphabet[]="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        char raw[112]; snprintf(raw,sizeof(raw),"feeder:%s",api_token);
        size_t length=strlen(raw),i=0,j=0;
        while (i<length) {
            size_t left=length-i; unsigned v=(unsigned char)raw[i++]<<16;
            if (left>1) v|=(unsigned char)raw[i++]<<8;
            if (left>2) v|=(unsigned char)raw[i++];
            encoded[j++]=alphabet[(v>>18)&63]; encoded[j++]=alphabet[(v>>12)&63];
            encoded[j++]=left>1 ? alphabet[(v>>6)&63]:'=';
            encoded[j++]=left>2 ? alphabet[v&63]:'=';
        }
        encoded[j]=0;
    }
    return header_auth(request,strlen(request),"Basic ",encoded);
}

static void disconnect(void) {
    if (client>=0) close(client);
    client=-1; input_used=0; pending=0;
}

static void respond_type(int status,const char *body,const char *content_type) {
    char output[4096];
    int length=snprintf(output,sizeof(output),
        "HTTP/1.1 %d Response\r\nContent-Type: %s\r\nConnection: close\r\nCache-Control: no-store\r\nContent-Length: %u\r\n\r\n%s",
        status,content_type,(unsigned)strlen(body),body);
    if (length>0 && length<(int)sizeof(output) && client>=0)
        (void)send(client,output,(size_t)length,MSG_DONTWAIT|MSG_NOSIGNAL);
    disconnect();
}

static void respond(int status,const char *body) { respond_type(status,body,"application/json"); }

static void respond_schedule(int verified) {
    char body[2304];
    int used=snprintf(body,sizeof(body),"{\"revision\":\"%08x\",\"verified\":%s,\"meals\":[",
        schedule_revision,verified ? "true":"false");
    for (size_t i=0;i<current_count && used>0 && used<(int)sizeof(body);i++) {
        struct pf_meal *m=current_meals+i;
        int n=snprintf(body+used,sizeof(body)-(size_t)used,
            "%s{\"weekdays\":%u,\"hour\":%u,\"minute\":%u,\"portions\":%u,\"enabled\":%s}",
            i ? ",":"",m->weekdays,m->hour,m->minute,m->portions,m->enabled ? "true":"false");
        if (n<0 || n>=(int)sizeof(body)-used) { respond(500,"{\"error\":\"response_overflow\"}"); return; }
        used+=n;
    }
    if (used<0 || used>(int)sizeof(body)-3) { respond(500,"{\"error\":\"response_overflow\"}"); return; }
    memcpy(body+used,"]}",3); respond(200,body);
}

static int parse_meals(const char *body,size_t length) {
    struct pf_json j; char revision[9];
    if (pf_json_parse(&j,body,length) || j.tokens[0].type!=PF_OBJECT || j.tokens[0].count!=2) return -1;
    if (pf_json_string(&j,pf_json_field(&j,0,"expected_revision"),revision,sizeof(revision)) || strlen(revision)!=8) return -1;
    expected_revision=0;
    for (unsigned i=0;i<8;i++) {
        unsigned char c=(unsigned char)revision[i]; unsigned digit;
        if (c>='0' && c<='9') digit=c-'0';
        else if (c>='a' && c<='f') digit=c-'a'+10;
        else return -1;
        expected_revision=(expected_revision<<4)|digit;
    }
    int array=pf_json_field(&j,0,"meals");
    if (array<0 || j.tokens[array].type!=PF_ARRAY || j.tokens[array].count>PF_MAX_MEALS) return -1;
    pending_count=(size_t)j.tokens[array].count;
    int item=array+1;
    for (size_t i=0;i<pending_count;i++) {
        unsigned week,hour,minute,portions; int enabled;
        if (j.tokens[item].type!=PF_OBJECT || j.tokens[item].count!=5 ||
            pf_json_uint(&j,pf_json_field(&j,item,"weekdays"),127,&week) ||
            pf_json_uint(&j,pf_json_field(&j,item,"hour"),23,&hour) ||
            pf_json_uint(&j,pf_json_field(&j,item,"minute"),59,&minute) ||
            pf_json_uint(&j,pf_json_field(&j,item,"portions"),10,&portions) || !portions ||
            pf_json_bool(&j,pf_json_field(&j,item,"enabled"),&enabled)) return -1;
        pending_meals[i]=(struct pf_meal){week,hour,minute,portions,enabled};
        item=j.tokens[item].next;
    }
    return 0;
}

static void start_query(int operation) {
    request_generation=schedule_generation; pending=operation;
    deadline_ms=milliseconds()+2500;
    if (query_schedule()) respond(503,"{\"error\":\"mcu_unavailable\"}");
}

static void respond_feed(const struct pf_operation *operation) {
    char body[256];
    snprintf(body,sizeof(body),"{\"operation_id\":\"%s\",\"accepted\":%s,\"dispensed\":null}",
        operation->id,operation->acknowledged ? "true":"false");
    respond(200,body);
}

static void start_feed(const char *body,size_t length) {
    struct pf_json j; unsigned portions;
    if (!feeding_enabled || !journal_ready) { respond(403,"{\"error\":\"feeding_not_enabled\"}"); return; }
    if (pf_json_parse(&j,body,length) || j.tokens[0].type!=PF_OBJECT || j.tokens[0].count!=2 ||
        pf_json_uint(&j,pf_json_field(&j,0,"portions"),10,&portions) || !portions ||
        pf_json_string(&j,pf_json_field(&j,0,"operation_id"),feed_operation,sizeof(feed_operation)) ||
        !pf_operation_id_valid(feed_operation)) {
        respond(422,"{\"error\":\"invalid_feed\"}"); return;
    }
    const struct pf_operation *previous=pf_journal_find(&journal,feed_operation);
    if (previous) {
        if (previous->portions!=portions) { respond(422,"{\"error\":\"operation_id_reused\"}"); return; }
        respond_feed(previous); return;
    }
    if (tx_fault || !last_mcu_ms || (unsigned)(milliseconds()-last_mcu_ms)>30000) {
        respond(503,"{\"error\":\"mcu_unavailable\"}"); return;
    }
    if (pf_journal_reserve(&journal,feed_operation,portions)) {
        journal_ready=0; respond(503,"{\"error\":\"journal_unavailable\"}"); return;
    }
    unsigned char frame[14];
    if (pf_encode_feed(portions,frame) || serial_write(frame,sizeof(frame))) {
        respond(502,"{\"error\":\"feed_outcome_unknown\"}"); return;
    }
    manual_commands_sent++; feed_ack=0; pending=5; deadline_ms=milliseconds()+2500;
}

static void set_clock(const char *body,size_t length) {
    struct pf_json j; unsigned fields[6];
    static const char *names[]={"year","month","day","hour","minute","second"};
    static const unsigned maxima[]={2099,12,31,23,59,59};
    if (pf_json_parse(&j,body,length) || j.tokens[0].type!=PF_OBJECT || j.tokens[0].count!=6) {
        respond(422,"{\"error\":\"invalid_clock\"}"); return;
    }
    for (unsigned i=0;i<6;i++) if (pf_json_uint(&j,pf_json_field(&j,0,names[i]),maxima[i],fields+i)) {
        respond(422,"{\"error\":\"invalid_clock\"}"); return;
    }
    unsigned char frame[10];
    if (pf_encode_clock(fields,frame)) { respond(422,"{\"error\":\"invalid_clock\"}"); return; }
    if (serial_write(frame,sizeof(frame))) { respond(503,"{\"error\":\"mcu_unavailable\"}"); return; }
    pending=6; clock_ack=0; deadline_ms=milliseconds()+2500;
}

static void request_ready(size_t header_length,size_t body_length) {
    char method[12]={0},path[128]={0},body[512];
    sscanf(input,"%11s %127s",method,path);
    if (!strcmp(method,"GET") && !strcmp(path,"/description.xml")) {
        char description[1024]; pf_description(description,sizeof(description),device_id);
        respond_type(200,description,"application/xml"); return;
    }
    if (!header_auth(input,header_length,"Bearer ",api_token)) { respond(401,"{\"error\":\"invalid_auth\"}"); return; }
    if (!strcmp(method,"GET") && !strcmp(path,"/api/v1/info")) {
        snprintf(body,sizeof(body),"{\"api_version\":1,\"id\":\"%s\",\"model\":\"V330L-DU4L-VS\",\"version\":\"0.2.1\",\"max_meals\":8,\"max_portions\":10,\"feeding_enabled\":%s,\"rtsp_port\":8555,\"scheduled_feed_events\":true}",device_id,feeding_enabled && journal_ready ? "true":"false");
        respond(200,body);
    } else if (!strcmp(method,"GET") && !strcmp(path,"/api/v1/events")) {
        char events[3072];
        if (pf_events_json(events,sizeof(events),event_milliseconds()))
            respond(503,"{\"error\":\"event_identity_unavailable\"}");
        else respond(200,events);
    } else if (!strcmp(method,"GET") && !strcmp(path,"/api/v1/status")) {
        snprintf(body,sizeof(body),"{\"mcu_connected\":%s,\"schedule_revision\":\"%08x\",\"serial_fault\":%s,\"manual_commands_sent\":%u,\"clock_synced\":%s}",
            last_mcu_ms && (unsigned)(milliseconds()-last_mcu_ms)<30000 ? "true":"false",
            schedule_revision,tx_fault ? "true":"false",manual_commands_sent,clock_synced ? "true":"false");
        respond(200,body);
    } else if (!strcmp(method,"GET") && !strcmp(path,"/api/v1/schedules")) {
        start_query(1);
    } else if (!strcmp(method,"PUT") && !strcmp(path,"/api/v1/schedules")) {
        if (parse_meals(input+header_length,body_length)) { respond(422,"{\"error\":\"invalid_schedule\"}"); return; }
        start_query(2);
    } else if (!strcmp(method,"POST") && !strcmp(path,"/api/v1/feed")) {
        start_feed(input+header_length,body_length);
    } else if (!strcmp(method,"POST") && !strcmp(path,"/api/v1/clock")) {
        set_clock(input+header_length,body_length);
    } else respond(404,"{\"error\":\"not_found\"}");
}

static void pending_tick(void) {
    if (!pending) return;
    if ((int)(milliseconds()-deadline_ms)>=0) { respond(504,"{\"error\":\"mcu_timeout\"}"); return; }
    if (pending==6) {
        if (!clock_ack) return;
        if (clock_ack<0) { respond(502,"{\"error\":\"clock_rejected\"}"); return; }
        clock_synced=1; respond(200,"{\"acknowledged\":true}"); return;
    }
    if (pending==5) {
        if (!feed_ack) return;
        if (feed_ack<0) { respond(502,"{\"error\":\"feed_outcome_unknown\"}"); return; }
        if (pf_journal_acknowledge(&journal,feed_operation)) {
            journal_ready=0; respond(502,"{\"error\":\"feed_outcome_unknown\"}"); return;
        }
        respond_feed(pf_journal_find(&journal,feed_operation)); return;
    }
    if (schedule_generation==request_generation) return;
    if (pending==1) { respond_schedule(0); return; }
    if (pending==2) {
        if (!have_schedule || schedule_revision!=expected_revision) { respond(409,"{\"error\":\"schedule_conflict\"}"); return; }
        unsigned char frame[PF_MAX_SCHEDULE_FRAME]; size_t size;
        if (pf_encode_schedule(pending_meals,pending_count,frame,sizeof(frame),&size) || serial_write(frame,size)) {
            respond(503,"{\"error\":\"mcu_unavailable\"}"); return;
        }
        pending=3; request_generation=schedule_generation;
        last_query_ms=milliseconds(); return;
    }
    if (pending==4) {
        if (current_count!=pending_count || memcmp(current_meals,pending_meals,pending_count*sizeof(*current_meals))) {
            respond(502,"{\"error\":\"schedule_readback_mismatch\"}"); return;
        }
        respond_schedule(1);
    }
}

static void initialize(void) {
    const char *directory=getenv("PF_STATE_DIR");
    if (!directory) directory="/mnt/config/pet-feeder-local";
    char path[320]; int n=snprintf(path,sizeof(path),"%s/api.token",directory);
    if (n<0 || n>=(int)sizeof(path) || read_text(path,api_token,sizeof(api_token))<32) return;
    for (size_t i=0;api_token[i];i++) {
        char c=api_token[i];
        if (!((c>='a' && c<='z') || (c>='A' && c<='Z') || (c>='0' && c<='9') || c=='-' || c=='_')) { api_token[0]=0; return; }
    }
    if (read_text("/sys/class/net/wlan0/address",device_id,sizeof(device_id))<0) strcpy(device_id,"unidentified");
    journal_ready=!pf_journal_open(&journal,directory);
    snprintf(path,sizeof(path),"%s/feeding.enabled",directory);
    feeding_enabled=access(path,F_OK)==0;
    unsigned char entropy[16]; char boot_id[33]={0};
    int random=open("/dev/urandom",O_RDONLY);
    if (random>=0) {
        if (read(random,entropy,sizeof(entropy))==(ssize_t)sizeof(entropy)) {
            for (unsigned i=0;i<sizeof(entropy);i++) snprintf(boot_id+2*i,3,"%02x",entropy[i]);
            pf_events_init(boot_id);
        }
        close(random);
    }
    listener=socket(AF_INET,SOCK_STREAM,0);
    if (listener<0) return;
    int one=1; setsockopt(listener,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));
    fcntl(listener,F_SETFL,O_NONBLOCK);
    struct sockaddr_in address={0}; address.sin_family=AF_INET; address.sin_port=htons(8080);
    if (bind(listener,(struct sockaddr *)&address,sizeof(address)) || listen(listener,2)) { close(listener); listener=-1; }
}

void pf_api_tick(void) {
    drain_serial();
    if (!initialized) { initialized=1; initialize(); }
    if (listener<0) return;
    pf_discovery_tick(device_id,milliseconds());
    if (pending==3 && (unsigned)(milliseconds()-last_query_ms)>=100) {
        pending=4; request_generation=schedule_generation;
        if (query_schedule()) respond(503,"{\"error\":\"mcu_unavailable\"}");
    }
    pending_tick();
    if (client<0) {
        int fd=accept(listener,0,0);
        if (fd>=0) { client=fd; fcntl(fd,F_SETFL,O_NONBLOCK); input_used=0; deadline_ms=milliseconds()+5000; }
    }
    if (client>=0 && !pending) {
        if ((int)(milliseconds()-deadline_ms)>=0) { disconnect(); return; }
        size_t space=sizeof(input)-1-input_used;
        if (!space) { respond(413,"{\"error\":\"request_too_large\"}"); return; }
        ssize_t n=recv(client,input+input_used,space,MSG_DONTWAIT);
        if (!n) { disconnect(); return; }
        if (n>0) {
            input_used+=(size_t)n; input[input_used]=0;
            char *end=strstr(input,"\r\n\r\n");
            if (end) {
                size_t header_length=(size_t)(end-input)+4,body_length=0;
                if (header_length>4096) { respond(413,"{\"error\":\"request_too_large\"}"); return; }
                const char *length=strcasestr(input,"\r\nContent-Length:");
                if (length && length<end) {
                    unsigned value=0;
                    if (sscanf(length+17,"%u",&value)!=1 || value>4096) { respond(400,"{\"error\":\"invalid_length\"}"); return; }
                    body_length=value;
                }
                const char *transfer=strcasestr(input,"\r\nTransfer-Encoding:");
                if (transfer && transfer<end) { respond(400,"{\"error\":\"unsupported_encoding\"}"); return; }
                if (input_used>=header_length+body_length) request_ready(header_length,body_length);
            }
        }
    }
    if (!pending && (unsigned)(milliseconds()-last_query_ms)>10000) (void)query_schedule();
}
