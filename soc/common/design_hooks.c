#include "design_hooks.h"

__attribute__((weak)) void design_init(void) {}
__attribute__((weak)) void design_irq(uint32_t irqs) { (void)irqs; }
__attribute__((weak)) void design_poll(void) {}
