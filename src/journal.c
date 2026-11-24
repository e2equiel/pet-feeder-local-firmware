#define _GNU_SOURCE
#include "journal.h"
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int pf_operation_id_valid(const char *id) {
    size_t length=strlen(id);
    if (!length || length>64) return 0;
    for (size_t i=0;i<length;i++) {
        char c=id[i];
        if (!((c>='a' && c<='z') || (c>='A' && c<='Z') ||
              (c>='0' && c<='9') || c=='-' || c=='_')) return 0;
    }
    return 1;
}

static int save(struct pf_journal *j) {
    unsigned char data[9+PF_OPERATION_HISTORY*67]={0};
    memcpy(data,"PFOPS001",8); data[8]=(unsigned char)j->count;
    for (unsigned i=0;i<j->count;i++) {
        unsigned char *p=data+9+i*67;
        memcpy(p,j->operations[i].id,65);
        p[65]=j->operations[i].portions; p[66]=j->operations[i].acknowledged;
    }
    char path[320],temporary[320];
    snprintf(path,sizeof(path),"%s/operations.dat",j->directory);
    snprintf(temporary,sizeof(temporary),"%s/operations.tmp",j->directory);
    int fd=open(temporary,O_WRONLY|O_CREAT|O_TRUNC,0600);
    if (fd<0) return -1;
    size_t length=9+j->count*67;
    int result=write(fd,data,length)==(ssize_t)length && !fsync(fd) ? 0:-1;
    if (close(fd)) result=-1;
    if (result || rename(temporary,path)) return -1;
    fd=open(j->directory,O_RDONLY|O_DIRECTORY);
    if (fd<0) return -1;
    result=fsync(fd); close(fd); return result;
}

int pf_journal_open(struct pf_journal *j,const char *directory) {
    if (!j || !directory || strlen(directory)>=sizeof(j->directory)) return -1;
    memset(j,0,sizeof(*j)); strcpy(j->directory,directory);
    char path[320]; snprintf(path,sizeof(path),"%s/operations.dat",directory);
    int fd=open(path,O_RDONLY);
    if (fd<0) return errno==ENOENT ? 0:-1;
    unsigned char data[10+PF_OPERATION_HISTORY*67];
    ssize_t length=read(fd,data,sizeof(data)); close(fd);
    if (length<9 || memcmp(data,"PFOPS001",8) || data[8]>PF_OPERATION_HISTORY ||
        length!=(ssize_t)(9+data[8]*67)) return -1;
    j->count=data[8];
    for (unsigned i=0;i<j->count;i++) {
        unsigned char *p=data+9+i*67;
        if (p[64] || !pf_operation_id_valid((char *)p) || p[65]<1 || p[65]>10 || p[66]>1) return -1;
        for (unsigned k=0;k<i;k++) if (!strcmp(j->operations[k].id,(char *)p)) return -1;
        memcpy(j->operations[i].id,p,65);
        j->operations[i].portions=p[65]; j->operations[i].acknowledged=p[66];
    }
    return 0;
}

const struct pf_operation *pf_journal_find(const struct pf_journal *j,const char *id) {
    for (unsigned i=0;i<j->count;i++) if (!strcmp(j->operations[i].id,id)) return j->operations+i;
    return NULL;
}

int pf_journal_reserve(struct pf_journal *j,const char *id,unsigned portions) {
    if (!pf_operation_id_valid(id) || portions<1 || portions>10 || pf_journal_find(j,id)) return -1;
    if (j->count==PF_OPERATION_HISTORY) {
        memmove(j->operations,j->operations+1,(PF_OPERATION_HISTORY-1)*sizeof(*j->operations));
        j->count--;
    }
    struct pf_operation *op=j->operations+j->count++;
    memset(op,0,sizeof(*op)); strcpy(op->id,id); op->portions=(uint8_t)portions;
    return save(j);
}

int pf_journal_acknowledge(struct pf_journal *j,const char *id) {
    for (unsigned i=0;i<j->count;i++) if (!strcmp(j->operations[i].id,id)) {
        j->operations[i].acknowledged=1; return save(j);
    }
    return -1;
}
