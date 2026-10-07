#ifndef _DESIGN_HOOKS_H_
#define _DESIGN_HOOKS_H_
#include <stdint.h>

// Per-design firmware hooks. Weak no-op defaults are in design_hooks.c; a
// design overrides them from soc/<design>/ (see design.mk).

// Called once after the board and LLRF are initialized.
void design_init(void);
// Called from the IRQ handler with the pending IRQ flags (ext_irq is [7:4]).
void design_irq(uint32_t irqs);
// Called on every main-loop iteration.
void design_poll(void);

#endif
