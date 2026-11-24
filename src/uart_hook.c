#define _GNU_SOURCE
#include <dlfcn.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include "local_api.h"

ssize_t read(int fd,void *buffer,size_t length) {
    static ssize_t (*stock_read)(int,void *,size_t);
    if (!stock_read) stock_read=dlsym(RTLD_NEXT,"read");
    if (!stock_read) return -1;
    ssize_t result=stock_read(fd,buffer,length);
    if (result>0) pf_uart_observe(fd,buffer,(size_t)result);
    return result;
}

int pf_uart_transmit(int fd,const void *buffer,unsigned length) {
    static ssize_t (*stock_write)(int,const void *,size_t);
    if (!stock_write) stock_write=dlsym(RTLD_NEXT,"write");
    return stock_write ? (int)stock_write(fd,buffer,length):-1;
}

ssize_t write(int fd,const void *buffer,size_t length) {
    /* The vendor app must not overwrite the MCU clock with stale cloud time
     * or accept a second control path for motor/schedule writes. Our API uses
     * pf_uart_transmit directly. The stock version writes complete frames.
     */
    if (fd>=0 && fd<=8 && length>=4) {
        const unsigned char *data=buffer;
        if (data[0]==255 && data[1]==255 && length==(size_t)data[3]+4 &&
            (data[2]==1 || data[2]==6 ||
             (data[2]==0x30 && length>=5 && data[4]==0x10))) {
            char path[48],target[80];
            snprintf(path,sizeof(path),"/proc/self/fd/%d",fd);
            ssize_t n=readlink(path,target,sizeof(target)-1);
            if (n>=0) {
                target[n]=0;
                if (!strcmp(target,"/dev/ttySAK1")) return (ssize_t)length;
            }
        }
    }
    return pf_uart_transmit(fd,buffer,(unsigned)length);
}
