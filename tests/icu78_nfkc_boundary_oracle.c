#include <node_api.h>
#include <stdint.h>
extern const void *unorm2_getNFKCInstance_78(int32_t *error);
extern int8_t unorm2_hasBoundaryBefore_78(const void *norm,int32_t c);
static napi_value boundaries(napi_env env,napi_callback_info info) {
  napi_value result; uint8_t *bytes; int32_t error=0;
  const void *norm=unorm2_getNFKCInstance_78(&error);
  if(error>0) { napi_throw_error(env,0,"NFKC unavailable");return 0; }
  napi_create_buffer(env,0x110000,(void**)&bytes,&result);
  for(int32_t c=0;c<0x110000;c++)bytes[c]=unorm2_hasBoundaryBefore_78(norm,c);
  return result;
}
static napi_value init(napi_env env,napi_value exports) {
 napi_value fn;napi_create_function(env,"boundaries",10,boundaries,0,&fn);napi_set_named_property(env,exports,"boundaries",fn);return exports;
}
NAPI_MODULE(NODE_GYP_MODULE_NAME,init)
