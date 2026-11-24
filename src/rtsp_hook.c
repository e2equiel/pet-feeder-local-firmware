#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include "local_api.h"
/* The build host's glibc headers redirect sscanf to __isoc99_sscanf;
 * this device's uClibc exports the compatible function as sscanf. */
extern int uclibc_sscanf(const char *,const char *,...) __asm__("sscanf");
#define sscanf uclibc_sscanf

/* Device-specific ABI verified against its original libmpi_venc.so. */
struct venc_stream { void *data; uint32_t size, reserved[3], frame_type; };
typedef int (*encode_fn)(unsigned, void *, int, void *, struct venc_stream *);
typedef int (*idr_fn)(unsigned);
static encode_fn real_encode;
static idr_fn force_idr;

struct channel {
    int listener, client, playing, interleaved;
    uint16_t sequence;
    uint32_t timestamp;
    char input[4096];
    unsigned input_size;
    unsigned char parameters[3][512];
    unsigned parameter_size[3];
};
static struct channel channels[2] = {
    {.listener=-1, .client=-1}, {.listener=-1, .client=-1}
};

static void disconnect(struct channel *c) {
    if (c->client >= 0) close(c->client);
    c->client=-1; c->playing=0; c->input_size=0;
}

static int send_bytes(struct channel *c, const void *data, unsigned size) {
    if (c->client < 0) return 0;
    ssize_t n=send(c->client, data, size, MSG_NOSIGNAL|MSG_DONTWAIT);
    if (n != (ssize_t)size) { disconnect(c); return 0; }
    return 1;
}

static void base64(const unsigned char *src, unsigned n, char *out) {
    static const char alphabet[]="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    unsigned i=0, j=0;
    while (i<n) {
        unsigned left=n-i, value=(unsigned)src[i++]<<16;
        if (left>1) value|=(unsigned)src[i++]<<8;
        if (left>2) value|=src[i++];
        out[j++]=alphabet[(value>>18)&63]; out[j++]=alphabet[(value>>12)&63];
        out[j++]=left>1 ? alphabet[(value>>6)&63] : '=';
        out[j++]=left>2 ? alphabet[value&63] : '=';
    }
    out[j]=0;
}

static void reply(struct channel *c, int sequence, const char *status, const char *headers, const char *body) {
    char response[3584];
    unsigned size=body ? strlen(body) : 0;
    int n=snprintf(response,sizeof(response),
        "RTSP/1.0 %s\r\nCSeq: %d\r\nServer: pf2-local\r\n%sContent-Length: %u\r\n\r\n%s",
        status,sequence,headers ? headers : "",size,body ? body : "");
    if (n>0 && n<(int)sizeof(response)) send_bytes(c,response,n);
}

static void process_request(struct channel *c, const char *request) {
    char method[24]={0}, url[256]={0}, headers[512];
    sscanf(request,"%23s %255s",method,url);
    const char *field=strcasestr(request,"\nCSeq:");
    int sequence=0;
    if (field) sscanf(field+6,"%d",&sequence);
    if (strcmp(method,"OPTIONS") && !pf_rtsp_authorized(request)) {
        reply(c,sequence,"401 Unauthorized","WWW-Authenticate: Basic realm=\"pet-feeder-local\"\r\n",0);
        return;
    }
    if (!strcmp(method,"OPTIONS")) {
        reply(c,sequence,"200 OK","Public: OPTIONS, DESCRIBE, SETUP, PLAY, GET_PARAMETER, TEARDOWN\r\n",0);
    } else if (!strcmp(method,"DESCRIBE")) {
        char vps[685],sps[685],pps[685],sdp[2560];
        base64(c->parameters[0],c->parameter_size[0],vps);
        base64(c->parameters[1],c->parameter_size[1],sps);
        base64(c->parameters[2],c->parameter_size[2],pps);
        snprintf(sdp,sizeof(sdp),
            "v=0\r\no=- 1 1 IN IP4 0.0.0.0\r\ns=Pet feeder local\r\nt=0 0\r\n"
            "a=control:*\r\nm=video 0 RTP/AVP 96\r\nc=IN IP4 0.0.0.0\r\n"
            "a=rtpmap:96 H265/90000\r\na=fmtp:96 sprop-vps=%s;sprop-sps=%s;sprop-pps=%s\r\n"
            "a=control:trackID=0\r\n",vps,sps,pps);
        snprintf(headers,sizeof(headers),"Content-Type: application/sdp\r\nContent-Base: %s/\r\n",url);
        reply(c,sequence,"200 OK",headers,sdp);
    } else if (!strcmp(method,"SETUP")) {
        if (!strcasestr(request,"RTP/AVP/TCP")) {
            reply(c,sequence,"461 Unsupported Transport",0,0); return;
        }
        field=strcasestr(request,"interleaved=");
        c->interleaved=0;
        if (field) sscanf(field+12,"%d",&c->interleaved);
        c->interleaved &= 0xff;
        snprintf(headers,sizeof(headers),"Session: pf2local;timeout=60\r\nTransport: RTP/AVP/TCP;unicast;interleaved=%d-%d\r\n",c->interleaved,c->interleaved+1);
        reply(c,sequence,"200 OK",headers,0);
    } else if (!strcmp(method,"PLAY")) {
        reply(c,sequence,"200 OK","Session: pf2local\r\nRange: npt=0.000-\r\n",0);
        c->playing=1;
        if (force_idr) force_idr((unsigned)(c-channels));
    } else if (!strcmp(method,"GET_PARAMETER")) {
        reply(c,sequence,"200 OK","Session: pf2local\r\n",0);
    } else if (!strcmp(method,"TEARDOWN")) {
        reply(c,sequence,"200 OK",0,0); disconnect(c);
    } else reply(c,sequence,"405 Method Not Allowed",0,0);
}

static void accept_and_read(struct channel *c, unsigned index) {
    if (c->listener < 0) {
        int fd=socket(AF_INET,SOCK_STREAM,0), one=1;
        if (fd<0) return;
        setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));
        fcntl(fd,F_SETFL,O_NONBLOCK);
        struct sockaddr_in a={0}; a.sin_family=AF_INET; a.sin_port=htons(8555+index);
        if (bind(fd,(struct sockaddr *)&a,sizeof(a)) || listen(fd,1)) { close(fd); return; }
        c->listener=fd;
    }
    struct sockaddr_in peer; socklen_t peer_size=sizeof(peer);
    int fd=accept(c->listener,(struct sockaddr *)&peer,&peer_size);
    if (fd>=0) {
        uint32_t ip=ntohl(peer.sin_addr.s_addr);
        if (!((ip >> 24) == 10 || (ip >> 20) == 0xac1 || (ip >> 16) == 0xc0a8)) close(fd);
        else {
            disconnect(c); c->client=fd; c->sequence=1000; c->timestamp=0;
            fcntl(fd,F_SETFL,O_NONBLOCK);
            int size=262144; setsockopt(fd,SOL_SOCKET,SO_SNDBUF,&size,sizeof(size));
            if (force_idr) force_idr(index);
        }
    }
    if (c->client<0) return;
    unsigned space=sizeof(c->input)-1-c->input_size;
    if (!space) { disconnect(c); return; }
    ssize_t n=recv(c->client,c->input+c->input_size,space,MSG_DONTWAIT);
    if (n==0) { disconnect(c); return; }
    if (n<0) return;
    c->input_size+=n; c->input[c->input_size]=0;
    while (c->client>=0 && c->input_size) {
        unsigned used;
        if ((unsigned char)c->input[0]=='$') {
            if (c->input_size<4) break;
            used=4+((unsigned char)c->input[2]<<8)+(unsigned char)c->input[3];
            if (c->input_size<used) break;
        } else {
            char *end=strstr(c->input,"\r\n\r\n");
            if (!end) break;
            used=(unsigned)(end-c->input)+4;
            process_request(c,c->input);
            if (c->client<0) break;
        }
        memmove(c->input,c->input+used,c->input_size-used);
        c->input_size-=used; c->input[c->input_size]=0;
    }
}

static int nal_start(const unsigned char *data,unsigned size,unsigned offset,unsigned *prefix) {
    for (unsigned i=offset;i+3<size;i++) {
        if (data[i] || data[i+1]) continue;
        if (data[i+2]==1) { *prefix=3; return i; }
        if (data[i+2]==0 && data[i+3]==1) { *prefix=4; return i; }
    }
    return -1;
}

static void rtp(struct channel *c,const unsigned char *payload,unsigned size,int marker) {
    unsigned char packet[1416]; unsigned length=12+size;
    packet[0]='$'; packet[1]=c->interleaved; packet[2]=length>>8; packet[3]=length;
    packet[4]=0x80; packet[5]=96|(marker ? 0x80:0);
    packet[6]=c->sequence>>8; packet[7]=c->sequence; c->sequence++;
    packet[8]=c->timestamp>>24; packet[9]=c->timestamp>>16;
    packet[10]=c->timestamp>>8; packet[11]=c->timestamp;
    packet[12]=0x50; packet[13]=0x46; packet[14]=0x32; packet[15]=0x01;
    memcpy(packet+16,payload,size); send_bytes(c,packet,16+size);
}

static void send_nal(struct channel *c,const unsigned char *data,unsigned size,int last) {
    if (size<2) return;
    if (size<=1200) { rtp(c,data,size,last); return; }
    unsigned char fragment[1200]; unsigned position=2;
    while (position<size && c->client>=0) {
        unsigned take=size-position; if (take>1197) take=1197;
        fragment[0]=(data[0]&0x81)|(49<<1); fragment[1]=data[1];
        fragment[2]=((data[0]>>1)&63)|(position==2 ? 0x80:0)|(position+take==size ? 0x40:0);
        memcpy(fragment+3,data+position,take);
        rtp(c,fragment,take+3,last && position+take==size); position+=take;
    }
}

static void process_frame(unsigned index,struct venc_stream *frame) {
    if (index>1 || !frame || !frame->data || !frame->size || frame->size>1048576) return;
    struct channel *c=channels+index;
    const unsigned char *data=frame->data; unsigned size=frame->size,prefix=0;
    int start=nal_start(data,size,0,&prefix);
    while (start>=0) {
        unsigned begin=start+prefix,next_prefix=0;
        int next=nal_start(data,size,begin,&next_prefix);
        unsigned length=(next>=0 ? (unsigned)next:size)-begin;
        if (length>=2) {
            unsigned type=(data[begin]>>1)&63;
            if (type>=32 && type<=34 && length<=512) {
                memcpy(c->parameters[type-32],data+begin,length); c->parameter_size[type-32]=length;
            }
        }
        start=next; prefix=next_prefix;
    }
    accept_and_read(c,index);
    if (c->playing && c->client>=0) {
        start=nal_start(data,size,0,&prefix);
        while (start>=0 && c->client>=0) {
            unsigned begin=start+prefix,next_prefix=0;
            int next=nal_start(data,size,begin,&next_prefix);
            unsigned length=(next>=0 ? (unsigned)next:size)-begin;
            send_nal(c,data+begin,length,next<0); start=next; prefix=next_prefix;
        }
    }
    c->timestamp+=9000; /* The stock encoder produces 10 frames/second. */
}

int ak_venc_encode_frame(unsigned handle,void *y,int third,void *uv,struct venc_stream *out) {
    if (!real_encode) {
        real_encode=(encode_fn)dlsym(RTLD_NEXT,"ak_venc_encode_frame");
        force_idr=(idr_fn)dlsym(RTLD_NEXT,"ak_venc_request_idr");
    }
    if (!real_encode) return -1;
    int result=real_encode(handle,y,third,uv,out);
    if (handle==0) pf_api_tick();
    if (!result) process_frame(handle,out);
    return result;
}
