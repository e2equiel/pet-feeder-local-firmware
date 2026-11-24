#include "../src/json.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    struct pf_json j; unsigned number; int boolean; char text[65];
    const char *valid="{\"expected_revision\":\"1234abcd\",\"meals\":[{\"weekdays\":127,\"hour\":8,\"minute\":0,\"portions\":2,\"enabled\":false}]}";
    assert(pf_json_parse(&j,valid,strlen(valid))==0);
    int meals=pf_json_field(&j,0,"meals");
    assert(meals>0 && j.tokens[meals].type==PF_ARRAY && j.tokens[meals].count==1);
    int meal=meals+1;
    assert(pf_json_uint(&j,pf_json_field(&j,meal,"weekdays"),127,&number)==0 && number==127);
    assert(pf_json_bool(&j,pf_json_field(&j,meal,"enabled"),&boolean)==0 && !boolean);
    assert(pf_json_string(&j,pf_json_field(&j,0,"expected_revision"),text,sizeof(text))==0 && !strcmp(text,"1234abcd"));
    const char *invalid[]={"{\"portions\":1,\"portions\":2}","{\"portions\":1.5}","{\"portions\":01}","{\"portions\":-1}","{\"id\":\"bad\\nvalue\"}","{\"a\":[1,]}","{\"a\":true,}","{} garbage","[", "\"unterminated"};
    for (size_t i=0;i<sizeof(invalid)/sizeof(*invalid);i++) assert(pf_json_parse(&j,invalid[i],strlen(invalid[i]))<0);
    const char *large="{\"portions\":4294967295}";
    assert(pf_json_parse(&j,large,strlen(large))==0);
    assert(pf_json_uint(&j,pf_json_field(&j,0,"portions"),10,&number)<0);
    puts("Bounded JSON parser validation passed");
    return 0;
}
