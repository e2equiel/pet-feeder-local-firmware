#ifndef PF_DISCOVERY_H
#define PF_DISCOVERY_H
void pf_discovery_tick(const char *identity, unsigned now);
void pf_description(char *output, unsigned size, const char *identity);
#endif
