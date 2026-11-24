#define _GNU_SOURCE
#include <arpa/inet.h>
#include <fcntl.h>
#include <net/if.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>
#include "discovery.h"
#define ST "urn:pet-feeder-local:device:Feeder:1"
static int listener=-2;
static unsigned last_reply,last_initialize;

static int uuid(char *out,unsigned size,const char *id) {
    char compact[13]; unsigned used=0;
    for (unsigned i=0;id[i];i++) {
        if (id[i]==':') continue;
        if (used==12 || !((id[i]>='0'&&id[i]<='9')||(id[i]>='a'&&id[i]<='f'))) return -1;
        compact[used++]=id[i];
    }
    if (used!=12) return -1;
    compact[12]=0;
    snprintf(out,size,"00000000-0000-4000-8000-%s",compact); return 0;
}
void pf_description(char *out,unsigned size,const char *id) {
    char identifier[40];
    if (uuid(identifier,sizeof(identifier),id)) { if(size)out[0]=0; return; }
    snprintf(out,size,"<?xml version=\"1.0\"?><root xmlns=\"urn:schemas-upnp-org:device-1-0\"><specVersion><major>1</major><minor>0</minor></specVersion><device><deviceType>" ST "</deviceType><friendlyName>Pet Feeder Local</friendlyName><manufacturer>Pet Feeder Local</manufacturer><modelName>V330L-DU4L-VS</modelName><serialNumber>%s</serialNumber><UDN>uuid:%s</UDN></device></root>",id,identifier);
}
void pf_discovery_tick(const char *id,unsigned now) {
    if (listener==-2 || (listener<0 && now-last_initialize>=10000)) {
        last_initialize=now;
        listener=socket(AF_INET,SOCK_DGRAM,0);
        if(listener<0)return;
        int one=1; setsockopt(listener,SOL_SOCKET,SO_REUSEADDR,&one,sizeof(one));
        struct sockaddr_in addr={0};addr.sin_family=AF_INET;addr.sin_port=htons(1900);
        struct ip_mreq group={0};group.imr_multiaddr.s_addr=inet_addr("239.255.255.250");
        /* WAN-blocking routes must not choose the multicast interface. */
        struct ifreq interface;memset(&interface,0,sizeof(interface));strcpy(interface.ifr_name,"wlan0");
        if(ioctl(listener,SIOCGIFADDR,&interface)) {close(listener);listener=-1;return;}
        group.imr_interface=((struct sockaddr_in*)&interface.ifr_addr)->sin_addr;
        if(bind(listener,(struct sockaddr*)&addr,sizeof(addr)) || setsockopt(listener,IPPROTO_IP,IP_ADD_MEMBERSHIP,&group,sizeof(group))) {close(listener);listener=-1;return;}
        fcntl(listener,F_SETFL,O_NONBLOCK);
    }
    if(listener<0)return;
    char request[1024];struct sockaddr_in peer={0};socklen_t peer_size=sizeof(peer);
    int n=recvfrom(listener,request,sizeof(request)-1,MSG_DONTWAIT,(struct sockaddr*)&peer,&peer_size);
    if(n<=0)return;
    request[n]=0;
    /* Bound responses to one per second, and only answer actual discovery. */
    if((last_reply && now-last_reply<1000) || strncmp(request,"M-SEARCH * HTTP/1.1\r\n",21) || !strcasestr(request,"MAN: \"ssdp:discover\""))return;
    if(!strcasestr(request,"ST: " ST "\r\n") && !strcasestr(request,"ST: ssdp:all\r\n"))return;
    struct ifreq interface;memset(&interface,0,sizeof(interface));strcpy(interface.ifr_name,"wlan0");
    if(ioctl(listener,SIOCGIFADDR,&interface))return;
    const struct sockaddr_in *address=(const struct sockaddr_in*)&interface.ifr_addr;
    char ip[20],identifier[40],response[768];
    if(!inet_ntop(AF_INET,&address->sin_addr,ip,sizeof(ip))||uuid(identifier,sizeof(identifier),id))return;
    n=snprintf(response,sizeof(response),"HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=120\r\nEXT:\r\nLOCATION: http://%s:8080/description.xml\r\nSERVER: Linux/4.4 UPnP/1.0 PetFeederLocal/0.2.0\r\nST: " ST "\r\nUSN: uuid:%s::" ST "\r\n\r\n",ip,identifier);
    if(n>0&&n<(int)sizeof(response)){(void)sendto(listener,response,(unsigned)n,MSG_DONTWAIT,(struct sockaddr*)&peer,peer_size);last_reply=now;}
}
