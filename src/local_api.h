#ifndef PF_LOCAL_API_H
#define PF_LOCAL_API_H
#include <stddef.h>
void pf_api_tick(void);
int pf_uart_transmit(int fd,const void *data,unsigned length);
void pf_uart_observe(int fd,const unsigned char *data,size_t length);
int pf_rtsp_authorized(const char *request);
#endif
