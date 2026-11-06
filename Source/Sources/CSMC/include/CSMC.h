#ifndef PULSE_CSMC_H
#define PULSE_CSMC_H
#include <stdint.h>
typedef struct { uint32_t size; uint32_t type; uint8_t bytes[32]; } StatesSMCValue;
int32_t states_smc_open(uint32_t *connection);
void states_smc_close(uint32_t connection);
int32_t states_smc_read(uint32_t connection, const char *key, StatesSMCValue *value);
/* Read-only bounded discovery: only numeric T-prefixed temperature keys leave C. */
int32_t states_smc_key_count(uint32_t connection, uint32_t *count);
int32_t states_smc_temperature_key_at_index(uint32_t connection, uint32_t index, char key[5]);
#endif
