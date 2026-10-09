#ifndef _INIT_MODBUS_H
#define _INIT_MODBUS_H

void mb_update_reg_map(int id, int mbData);
unsigned int mb_get_reg_map(int id);
void modbus_init(void);
void mb_write_callback(uint16_t mbRegId, uint16_t mbData);
void regmap_poll(void);
uint32_t reimplement_millis(void);

#endif /* ndef _INIT_MODBUS_H */
