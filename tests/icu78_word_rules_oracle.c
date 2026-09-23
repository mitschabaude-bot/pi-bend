/* Test/generation only: read ICU78's compiled default word rules from Node. */
#include <node_api.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
extern const void *english(void) __asm__("_ZN6icu_786Locale10getEnglishEv");
extern void *word_iterator(const void *,int32_t *) __asm__("_ZN6icu_7813BreakIterator18createWordInstanceERKNS_6LocaleER10UErrorCode");
extern const uint8_t *binary_rules(void *,uint32_t *) __asm__("_ZN6icu_7822RuleBasedBreakIterator14getBinaryRulesERj");
extern void destroy_iterator(void *) __asm__("_ZN6icu_7822RuleBasedBreakIteratorD0Ev");
extern void *ucptrie_openFromBinary_78(int,int,const void *,int32_t,int32_t *,int32_t *);
extern int32_t ucptrie_getRange_78(const void *,int32_t,int,uint32_t,void *,void *,uint32_t *);
extern void ucptrie_close_78(void *);
static napi_value extract(napi_env env,napi_callback_info info) {
 int32_t error=0;uint32_t length=0;void *iter=word_iterator(english(),&error);
 if(error>0 || !iter){napi_throw_error(env,0,"word iterator unavailable");return 0;}
 const uint8_t *raw=binary_rules(iter,&length);napi_value result,blob,categories;
 napi_create_object(env,&result);napi_create_buffer_copy(env,length,raw,0,&blob);napi_set_named_property(env,result,"rules",blob);
 uint32_t offset,trie_length;memcpy(&offset,raw+32,4);memcpy(&trie_length,raw+36,4);
 void *trie=ucptrie_openFromBinary_78(-1,-1,raw+offset,trie_length,0,&error);
 if(error>0 || !trie){destroy_iterator(iter);napi_throw_error(env,0,"word category trie unavailable");return 0;}
 uint8_t *data;napi_create_buffer(env,0x110000*2,(void**)&data,&categories);
 for(int32_t start=0;start<0x110000;){uint32_t value;int32_t end=ucptrie_getRange_78(trie,start,0,0,0,0,&value);
  if(end<start){ucptrie_close_78(trie);destroy_iterator(iter);napi_throw_error(env,0,"invalid category range");return 0;}
  for(int32_t cp=start;cp<=end;cp++){data[2*cp]=value&255;data[2*cp+1]=value>>8;}start=end+1;
 }
 napi_set_named_property(env,result,"categories",categories);ucptrie_close_78(trie);destroy_iterator(iter);return result;
}
extern void *utext_openUChars_78(void *,const uint16_t *,int64_t,int32_t *);
extern void *utext_close_78(void *);
extern void set_text(void *,void *,int32_t *) __asm__("_ZN6icu_7822RuleBasedBreakIterator7setTextEP5UTextR10UErrorCode");
extern int32_t first(void *) __asm__("_ZN6icu_7822RuleBasedBreakIterator5firstEv");
extern int32_t next(void *) __asm__("_ZN6icu_7822RuleBasedBreakIterator4nextEv");
extern int32_t status(void *) __asm__("_ZNK6icu_7822RuleBasedBreakIterator13getRuleStatusEv");
static napi_value segments(napi_env env,napi_callback_info info){
 napi_value arg,result;size_t argc=1,length=0;int32_t error=0;
 napi_get_cb_info(env,info,&argc,&arg,0,0);napi_get_value_string_utf16(env,arg,0,0,&length);
 char16_t *text=malloc((length+1)*sizeof(char16_t));if(!text){napi_throw_error(env,0,"allocation failed");return 0;}
 napi_get_value_string_utf16(env,arg,text,length+1,&length);
 void *iter=word_iterator(english(),&error),*ut=utext_openUChars_78(0,(const uint16_t *)text,length,&error);
 if(error>0 || !iter || !ut){if(iter)destroy_iterator(iter);if(ut)utext_close_78(ut);free(text);napi_throw_error(env,0,"iterator failed");return 0;}
 set_text(iter,ut,&error);napi_create_array(env,&result);first(iter);uint32_t i=0;
 for(int32_t end;(end=next(iter))!=-1;){napi_value row,position,tag;napi_create_array_with_length(env,2,&row);napi_create_int32(env,end,&position);napi_create_int32(env,status(iter),&tag);napi_set_element(env,row,0,position);napi_set_element(env,row,1,tag);napi_set_element(env,result,i++,row);}
 destroy_iterator(iter);utext_close_78(ut);free(text);return result;
}
/* Pin the actual reference's resource-driven Thai/Myanmar dictionary fallback. */
extern const void *CreateLSTMDataForScript_78(int,int32_t *);
extern void DeleteLSTMData_78(const void *);
extern void *ures_openDirect_78(const char *,const char *,int32_t *);
extern void *ures_getByKey_78(const void *,const char *,void *,int32_t *);
extern void ures_close_78(void *);
static napi_value engine_resources(napi_env env,napi_callback_info info){
 int32_t states[6]={0},error=0;void *root=ures_openDirect_78("icudt78l-brkitr","root",&error);states[0]=error;
 if(root){void *lstm=ures_getByKey_78(root,"lstm",0,&error);states[1]=error;if(lstm)ures_close_78(lstm);ures_close_78(root);}
 const char *models[]={"Thai_graphclust_model4_heavy","Burmese_graphclust_model5_heavy"};int scripts[]={38,28};
 for(int i=0;i<2;i++){error=0;void *resource=ures_openDirect_78("icudt78l-brkitr",models[i],&error);states[2+i]=error;if(resource)ures_close_78(resource);
  error=0;const void *data=CreateLSTMDataForScript_78(scripts[i],&error);states[4+i]=error;if(data)DeleteLSTMData_78(data);}
 napi_value result;napi_create_array_with_length(env,6,&result);for(int i=0;i<6;i++){napi_value code;napi_create_int32(env,states[i],&code);napi_set_element(env,result,i,code);}return result;
}
static napi_value init(napi_env env,napi_value exports){napi_value fn;napi_create_function(env,"extract",7,extract,0,&fn);napi_set_named_property(env,exports,"extract",fn);napi_create_function(env,"segments",8,segments,0,&fn);napi_set_named_property(env,exports,"segments",fn);napi_create_function(env,"engineResources",15,engine_resources,0,&fn);napi_set_named_property(env,exports,"engineResources",fn);return exports;}
NAPI_MODULE(NODE_GYP_MODULE_NAME,init)
