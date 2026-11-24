#ifndef PF_JSON_H
#define PF_JSON_H
#include <stddef.h>

enum pf_json_type { PF_OBJECT, PF_ARRAY, PF_STRING, PF_NUMBER, PF_TRUE, PF_FALSE, PF_NULL };
struct pf_json_token { enum pf_json_type type; size_t start,length; int next,count; };
struct pf_json {
    const char *data;
    size_t length,position;
    struct pf_json_token tokens[160];
    int used;
};

/* Deliberately bounded API JSON: ASCII keys/IDs, integral numbers, booleans,
 * objects and arrays. Escaped strings and floating-point values are rejected.
 */
int pf_json_parse(struct pf_json *json,const char *data,size_t length);
int pf_json_field(const struct pf_json *json,int object,const char *name);
int pf_json_uint(const struct pf_json *json,int token,unsigned maximum,unsigned *out);
int pf_json_bool(const struct pf_json *json,int token,int *out);
int pf_json_string(const struct pf_json *json,int token,char *out,size_t capacity);
#endif
