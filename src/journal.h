#ifndef PF_JOURNAL_H
#define PF_JOURNAL_H
#include <stdint.h>
#define PF_OPERATION_HISTORY 16
struct pf_operation { char id[65]; uint8_t portions,acknowledged; };
struct pf_journal {
    char directory[280];
    struct pf_operation operations[PF_OPERATION_HISTORY];
    unsigned count;
};
int pf_journal_open(struct pf_journal *journal,const char *directory);
int pf_operation_id_valid(const char *id);
const struct pf_operation *pf_journal_find(const struct pf_journal *,const char *id);
/* Persist a reservation before a motor command. Repeated IDs never reserve twice. */
int pf_journal_reserve(struct pf_journal *,const char *id,unsigned portions);
int pf_journal_acknowledge(struct pf_journal *,const char *id);
#endif
