#include "json.h"
#include <string.h>

static void whitespace(struct pf_json *j) {
    while (j->position<j->length) {
        char c=j->data[j->position];
        if (c!=' ' && c!='\r' && c!='\n' && c!='\t') break;
        j->position++;
    }
}

static int value(struct pf_json *j,unsigned depth) {
    whitespace(j);
    if (depth>6 || j->used>=160 || j->position>=j->length) return -1;
    int index=j->used++;
    struct pf_json_token *t=j->tokens+index;
    memset(t,0,sizeof(*t)); t->start=j->position;
    char c=j->data[j->position++];
    if (c=='{' || c=='[') {
        t->type=c=='{' ? PF_OBJECT:PF_ARRAY;
        char closing=c=='{' ? '}':']'; whitespace(j);
        if (j->position<j->length && j->data[j->position]==closing) j->position++;
        else for (;;) {
            if (c=='{') {
                int key=value(j,depth+1);
                if (key<0 || j->tokens[key].type!=PF_STRING) return -1;
                /* Reject duplicate keys before any command is interpreted. */
                for (int old=index+1;old<key;) {
                    const struct pf_json_token *a=j->tokens+old,*b=j->tokens+key;
                    if (a->length==b->length && !memcmp(j->data+a->start,j->data+b->start,a->length)) return -1;
                    old=j->tokens[old+1].next;
                }
                whitespace(j);
                if (j->position>=j->length || j->data[j->position++]!=':') return -1;
            }
            if (value(j,depth+1)<0) return -1;
            t->count++; whitespace(j);
            if (j->position>=j->length) return -1;
            char separator=j->data[j->position++];
            if (separator==closing) break;
            if (separator!=',') return -1;
        }
        t->length=j->position-t->start;
    } else if (c=='"') {
        t->type=PF_STRING; t->start=j->position;
        while (j->position<j->length && j->data[j->position]!='"') {
            unsigned char b=j->data[j->position++];
            if (b<32 || b>126 || b=='\\') return -1;
        }
        if (j->position>=j->length) return -1;
        t->length=j->position-t->start; j->position++;
    } else if (c>='0' && c<='9') {
        t->type=PF_NUMBER;
        while (j->position<j->length && j->data[j->position]>='0' && j->data[j->position]<='9') j->position++;
        t->length=j->position-t->start;
        if (t->length>10 || (c=='0' && t->length>1)) return -1;
    } else {
        const char *literal=0;
        if (c=='t') { literal="true"; t->type=PF_TRUE; }
        if (c=='f') { literal="false"; t->type=PF_FALSE; }
        if (c=='n') { literal="null"; t->type=PF_NULL; }
        if (!literal) return -1;
        size_t size=strlen(literal);
        if (j->length-t->start<size || memcmp(j->data+t->start,literal,size)) return -1;
        j->position=t->start+size; t->length=size;
    }
    t->next=j->used; return index;
}

int pf_json_parse(struct pf_json *j,const char *data,size_t length) {
    if (!j || !data || !length || length>4096) return -1;
    j->data=data; j->length=length; j->position=0; j->used=0;
    if (value(j,0)!=0) return -1;
    whitespace(j); return j->position==j->length ? 0:-1;
}

int pf_json_field(const struct pf_json *j,int object,const char *name) {
    if (object<0 || object>=j->used || j->tokens[object].type!=PF_OBJECT) return -1;
    const struct pf_json_token *parent=j->tokens+object;
    for (int i=object+1;i<parent->next;) {
        const struct pf_json_token *key=j->tokens+i;
        if (strlen(name)==key->length && !memcmp(j->data+key->start,name,key->length)) return i+1;
        i=j->tokens[i+1].next;
    }
    return -1;
}

int pf_json_uint(const struct pf_json *j,int token,unsigned maximum,unsigned *out) {
    if (token<0 || token>=j->used || j->tokens[token].type!=PF_NUMBER) return -1;
    const struct pf_json_token *t=j->tokens+token; unsigned result=0;
    for (size_t i=0;i<t->length;i++) {
        unsigned digit=(unsigned)(j->data[t->start+i]-'0');
        if (digit>maximum || result>(maximum-digit)/10) return -1;
        result=result*10+digit;
    }
    *out=result; return 0;
}

int pf_json_bool(const struct pf_json *j,int token,int *out) {
    if (token<0 || token>=j->used) return -1;
    if (j->tokens[token].type==PF_TRUE) { *out=1; return 0; }
    if (j->tokens[token].type==PF_FALSE) { *out=0; return 0; }
    return -1;
}

int pf_json_string(const struct pf_json *j,int token,char *out,size_t capacity) {
    if (token<0 || token>=j->used || j->tokens[token].type!=PF_STRING) return -1;
    const struct pf_json_token *t=j->tokens+token;
    if (t->length>=capacity) return -1;
    memcpy(out,j->data+t->start,t->length); out[t->length]=0; return 0;
}
