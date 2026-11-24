#define _GNU_SOURCE
#include "../src/journal.h"
#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    char directory[]="/tmp/pf-journal-XXXXXX";
    assert(mkdtemp(directory));
    struct pf_journal journal,reopened;
    assert(!pf_journal_open(&journal,directory));
    assert(!pf_journal_reserve(&journal,"power-cut-before-uart",1));
    assert(!pf_journal_open(&reopened,directory));
    assert(!pf_journal_find(&reopened,"power-cut-before-uart")->acknowledged);
    assert(pf_journal_reserve(&reopened,"power-cut-before-uart",1));
    assert(!pf_journal_reserve(&reopened,"acknowledged",2));
    assert(!pf_journal_acknowledge(&reopened,"acknowledged"));
    assert(!pf_journal_open(&journal,directory));
    assert(pf_journal_find(&journal,"acknowledged")->acknowledged);
    assert(pf_journal_reserve(&journal,"invalid/id",1));
    assert(pf_journal_reserve(&journal,"bad-portions",0));
    for (unsigned i=0;i<20;i++) {
        char id[32]; snprintf(id,sizeof(id),"operation-%u",i);
        assert(!pf_journal_reserve(&journal,id,1));
    }
    assert(!pf_journal_open(&reopened,directory));
    assert(reopened.count==PF_OPERATION_HISTORY);
    assert(!pf_journal_find(&reopened,"operation-0"));
    assert(pf_journal_find(&reopened,"operation-19"));
    char path[320]; snprintf(path,sizeof(path),"%s/operations.dat",directory);
    int fd=open(path,O_WRONLY|O_TRUNC); assert(fd>=0);
    assert(write(fd,"PFOPS001",8)==8); close(fd);
    assert(pf_journal_open(&reopened,directory));
    unlink(path); rmdir(directory);
    assert(pf_journal_reserve(&journal,"unwritable-directory",1));
    puts("Durable operation journal validation passed");
}
