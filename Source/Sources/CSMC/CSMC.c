#include "CSMC.h"
#include <IOKit/IOKitLib.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
/* Wire layout described by the AppleSMC user client, selector 2.
   Protocol research: https://github.com/exelban/stats/blob/master/SMC/smc.swift
   Original implementation; bounded temperature-only discovery never reads identifying values. */
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } Version;
typedef struct { uint16_t version,length; uint32_t cpu,gpu,memory; } Limits;
typedef struct __attribute__((packed)) { uint32_t size,type; uint8_t attributes; } Info;
typedef struct { uint32_t key; Version version; Limits limits; Info info;
 uint16_t padding; uint8_t result,status,command; uint32_t data; uint8_t bytes[32]; } Wire;
_Static_assert(sizeof(Wire)==80,"SMC wire size");
_Static_assert(offsetof(Wire,bytes)==48,"SMC bytes offset");
static uint32_t four(const char *s) { return ((uint32_t)(uint8_t)s[0]<<24)|((uint32_t)(uint8_t)s[1]<<16)|((uint32_t)(uint8_t)s[2]<<8)|(uint8_t)s[3]; }
static int32_t call(uint32_t c,Wire *in,Wire *out) { size_t n=sizeof(*out); kern_return_t r=IOConnectCallStructMethod(c,2,in,sizeof(*in),out,&n); if(r) return r; if(n!=sizeof(*out))return kIOReturnUnderrun; return out->result==0?0:(out->result==0x84?kIOReturnNotFound:kIOReturnError); }
int32_t states_smc_open(uint32_t *c) { io_service_t s=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC")); if(!s)return kIOReturnNotFound; int32_t r=IOServiceOpen(s,mach_task_self(),0,c);IOObjectRelease(s);return r; }
void states_smc_close(uint32_t c) {if(c)IOServiceClose(c);}
static int hex_digit(unsigned char c) { if(c>='0'&&c<='9')return c-'0';if(c>='a'&&c<='f')return c-'a'+10;return -1; }
static int temperature_type(uint32_t type,uint32_t size) {
 if(type==four("flt "))return size==4;
 if(type==four("ioft"))return size==8;
 unsigned char a=(type>>8)&255,b=type&255;
 int integer=hex_digit(a),fraction=hex_digit(b);
 return (type>>16)==(((uint32_t)'s'<<8)|'p') && size==2 && integer>=0 && fraction>=0 && integer+fraction==15;
}
static int temperature_key(const char *k) {
 if(!k||strlen(k)!=4||k[0]!='T')return 0;
 for(int i=0;i<4;i++)if((unsigned char)k[i]<32 || (unsigned char)k[i]>126)return 0;
 return 1;
}
int32_t states_smc_key_count(uint32_t c,uint32_t *count) {
 if(!count)return kIOReturnBadArgument;*count=0;
 Wire in={0},out={0};in.key=four("#KEY");in.command=9;
 int32_t r=call(c,&in,&out);if(r)return r;
 if(out.info.size!=4||out.info.type!=four("ui32"))return kIOReturnUnsupported;
 in.info.size=4;in.command=5;r=call(c,&in,&out);if(r)return r;
 uint32_t n=((uint32_t)out.bytes[0]<<24)|((uint32_t)out.bytes[1]<<16)|((uint32_t)out.bytes[2]<<8)|out.bytes[3];
 if(n==0||n>10000)return kIOReturnNoResources;
 *count=n;return 0;
}
int32_t states_smc_temperature_key_at_index(uint32_t c,uint32_t index,char key[5]) {
 if(!key||index>=10000)return kIOReturnBadArgument;memset(key,0,5);
 Wire in={0},out={0};in.command=8;in.data=index;
 int32_t r=call(c,&in,&out);if(r)return r;
 char candidate[5]={(out.key>>24)&255,(out.key>>16)&255,(out.key>>8)&255,out.key&255,0};
 if(!temperature_key(candidate))return kIOReturnNotFound;
 in=(Wire){0};in.key=out.key;in.command=9;r=call(c,&in,&out);if(r)return r;
 if(!temperature_type(out.info.type,out.info.size))return kIOReturnUnsupported;
 memcpy(key,candidate,5);return 0;
}
static int allowed(const char *k) {
 if(!k || strlen(k)!=4)return 0;
 if(!strcmp(k,"FNum")||!strcmp(k,"FS! ")||!strcmp(k,"Ftst"))return 1;
 if(k[0]=='F' && k[1]>='0' && k[1]<='7' && (!strcmp(k+2,"Ac")||!strcmp(k+2,"Mn")||!strcmp(k+2,"Mx")||!strcmp(k+2,"Tg")||!strcmp(k+2,"Md")||!strcmp(k+2,"md")))return 1;
 if(temperature_key(k))return 1;
 /* Fixed power telemetry key, never identifying values. */
 const char *sensors[]={"Tp01","Tp02","Tp03","Tp04","Tp05","Tp06","Tp07","Tp08","Tp09","Tp0a","Tp0b","Tp0c","Tp0d","Tp0e","Te05","Te09","Te0H","Te0S","Tg05","Tg0D","Tg0L","Tg0T","TC0P","TC0D","TB0T","Ts0P","PSTR"};
 for(size_t i=0;i<sizeof(sensors)/sizeof(sensors[0]);i++)if(!strcmp(k,sensors[i]))return 1;
 return 0;
}
int32_t states_smc_read(uint32_t c,const char *key,StatesSMCValue *v) {
 if(!allowed(key)||!v)return kIOReturnBadArgument;
 Wire in={0},out={0}; in.key=four(key);in.command=9;
 int32_t r=call(c,&in,&out);if(r)return r;
 if(out.info.size<1||out.info.size>32)return kIOReturnBadArgument;
 if(temperature_key(key)&&!temperature_type(out.info.type,out.info.size))return kIOReturnUnsupported;
 v->size=out.info.size;v->type=out.info.type;in.info.size=v->size;in.command=5;
 r=call(c,&in,&out);if(!r)memcpy(v->bytes,out.bytes,v->size);return r;
}
